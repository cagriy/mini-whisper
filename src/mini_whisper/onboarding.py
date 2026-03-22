"""Onboarding window — blocks app until all required permissions are granted."""

import logging

import AppKit
import objc
from Foundation import NSMakeRect, NSObject

logger = logging.getLogger(__name__)

WINDOW_WIDTH = 460
WINDOW_HEIGHT = 310

SETTINGS_URLS = {
    "microphone": "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
    "accessibility": "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
}

PERM_LABELS = {
    "microphone": "Microphone",
    "accessibility": "Accessibility",
}

PERM_DESCRIPTIONS = {
    "microphone": "Record audio for speech-to-text",
    "accessibility": "Type transcribed text into any app",
}

PERM_SYMBOLS = {
    "microphone": "mic.fill",
    "accessibility": "keyboard.fill",
}


# -- Permission checks --------------------------------------------------------


def check_microphone() -> bool:
    import AVFoundation

    status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
        AVFoundation.AVMediaTypeAudio
    )
    return status == AVFoundation.AVAuthorizationStatusAuthorized


def check_accessibility() -> bool:
    from ApplicationServices import AXIsProcessTrusted

    result = bool(AXIsProcessTrusted())
    logger.debug("check_accessibility: AXIsProcessTrusted=%s", result)
    return result


def check_all_permissions() -> dict[str, bool]:
    return {
        "microphone": check_microphone(),
        "accessibility": check_accessibility(),
    }


# -- Helper NSObject subclasses ----------------------------------------------


class _OnboardingDelegate(NSObject):
    """Prevents closing the onboarding window."""

    def windowShouldClose_(self, _sender):
        return False


class _PollTimerTarget(NSObject):
    _callback = None

    def fire_(self, _timer):
        if self._callback is not None:
            self._callback()


class _OpenSettingsTarget(NSObject):
    _perm_key = None
    _onboarding = None

    def open_(self, _sender):
        if self._onboarding is not None and self._perm_key is not None:
            self._onboarding._open_settings(self._perm_key)


class _ContinueTarget(NSObject):
    _onboarding = None

    def continue_(self, _sender):
        if self._onboarding is not None:
            self._onboarding._on_continue()


# -- Onboarding Window -------------------------------------------------------


PERM_ORDER = ("microphone", "accessibility")


class OnboardingWindow:
    def __init__(self, on_complete):
        self._on_complete = on_complete
        self._timer = None
        self._timer_target = None
        self._button_targets = []  # prevent GC
        self._current_step = 0  # index into PERM_ORDER

        self._build_window()

    def _build_window(self):
        style = (
            AppKit.NSTitledWindowMask
            | AppKit.NSFullSizeContentViewWindowMask
        )
        frame = NSMakeRect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        self._window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame, style, AppKit.NSBackingStoreBuffered, False
        )
        self._window.setTitle_("Mini Whisper — Setup")
        self._window.setTitlebarAppearsTransparent_(True)
        self._window.setReleasedWhenClosed_(False)
        self._window.center()

        delegate = _OnboardingDelegate.alloc().init()
        self._delegate = delegate
        self._window.setDelegate_(delegate)

        content = self._window.contentView()
        pad = 30
        y = WINDOW_HEIGHT - 60

        # Title
        title = self._make_label(
            NSMakeRect(pad, y, WINDOW_WIDTH - 2 * pad, 28),
            "Mini Whisper needs a few permissions",
            AppKit.NSFont.boldSystemFontOfSize_(18),
        )
        content.addSubview_(title)

        # Subtitle
        y -= 22
        subtitle = self._make_label(
            NSMakeRect(pad, y, WINDOW_WIDTH - 2 * pad, 16),
            "Grant the permissions below so Mini Whisper can work properly.",
            AppKit.NSFont.systemFontOfSize_(12),
            AppKit.NSColor.secondaryLabelColor(),
        )
        content.addSubview_(subtitle)

        # Permission rows
        y -= 16
        self._indicators = {}
        self._open_buttons = {}
        for perm_key in PERM_ORDER:
            y -= 52
            self._add_permission_row(content, perm_key, y)

        # Status label
        y -= 36
        self._status_label = self._make_label(
            NSMakeRect(pad, y, WINDOW_WIDTH - 2 * pad, 18),
            "Grant all permissions to continue.",
            AppKit.NSFont.systemFontOfSize_(12),
            AppKit.NSColor.secondaryLabelColor(),
        )
        content.addSubview_(self._status_label)

        # Continue button — right-aligned, prominent style
        y -= 40
        self._continue_btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(WINDOW_WIDTH - pad - 110, y, 110, 32)
        )
        self._continue_btn.setTitle_("Continue")
        self._continue_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        self._continue_btn.setEnabled_(False)
        self._continue_btn.setKeyEquivalent_("\r")

        target = _ContinueTarget.alloc().init()
        target._onboarding = self
        self._continue_target = target
        self._continue_btn.setTarget_(target)
        self._continue_btn.setAction_(objc.selector(_ContinueTarget.continue_, signature=b"v@:@"))
        content.addSubview_(self._continue_btn)

    @staticmethod
    def _make_label(frame, text, font, color=None):
        label = AppKit.NSTextField.alloc().initWithFrame_(frame)
        label.setStringValue_(text)
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setEditable_(False)
        label.setSelectable_(False)
        label.setFont_(font)
        if color is not None:
            label.setTextColor_(color)
        return label

    def _add_permission_row(self, content, perm_key, y):
        pad = 30
        # Row is 44px tall; y is the bottom edge.
        # Vertically: label at top half, description at bottom half.
        # Left side: indicator (14px) + gap(6) + icon (22px) + gap(10) + text
        # Right side: Open Settings button, vertically centered.

        icon_size = 22
        indicator_x = pad
        icon_x = pad + icon_size + 8
        text_x = icon_x + icon_size + 10
        text_w = WINDOW_WIDTH - text_x - 130  # leave room for button
        icon_y = y + 11  # vertically centered in 44px row

        # Status indicator (tick/cross, same size & vertical position as icon)
        indicator = AppKit.NSImageView.alloc().initWithFrame_(
            NSMakeRect(indicator_x, icon_y, icon_size, icon_size)
        )
        self._indicators[perm_key] = indicator
        content.addSubview_(indicator)

        # Icon (SF Symbol for the permission type, aligned with indicator)
        icon_view = AppKit.NSImageView.alloc().initWithFrame_(
            NSMakeRect(icon_x, icon_y, icon_size, icon_size)
        )
        symbol = AppKit.NSImage.imageWithSystemSymbolName_accessibilityDescription_(
            PERM_SYMBOLS[perm_key], PERM_LABELS[perm_key]
        )
        if symbol is not None:
            config = AppKit.NSImageSymbolConfiguration.configurationWithPointSize_weight_(
                13, AppKit.NSFontWeightMedium
            )
            symbol = symbol.imageWithSymbolConfiguration_(config)
            icon_view.setImage_(symbol)
        icon_view.setContentTintColor_(AppKit.NSColor.secondaryLabelColor())
        content.addSubview_(icon_view)

        # Label (permission name) — top half of row
        label = self._make_label(
            NSMakeRect(text_x, y + 23, text_w, 18),
            PERM_LABELS[perm_key],
            AppKit.NSFont.systemFontOfSize_weight_(13, AppKit.NSFontWeightMedium),
        )
        content.addSubview_(label)

        # Description — bottom half of row
        desc = self._make_label(
            NSMakeRect(text_x, y + 5, text_w, 16),
            PERM_DESCRIPTIONS[perm_key],
            AppKit.NSFont.systemFontOfSize_(11),
            AppKit.NSColor.secondaryLabelColor(),
        )
        content.addSubview_(desc)

        # Open Settings button — vertically centered in row
        btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(WINDOW_WIDTH - pad - 110, y + 9, 100, 28)
        )
        btn.setTitle_("Open Settings")
        btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        btn.setControlSize_(AppKit.NSControlSizeSmall)
        btn.setFont_(AppKit.NSFont.systemFontOfSize_(11))

        target = _OpenSettingsTarget.alloc().init()
        target._perm_key = perm_key
        target._onboarding = self
        self._button_targets.append(target)
        btn.setTarget_(target)
        btn.setAction_(objc.selector(_OpenSettingsTarget.open_, signature=b"v@:@"))
        content.addSubview_(btn)
        self._open_buttons[perm_key] = btn

    def show(self):
        # Skip past any permissions already granted
        self._advance_to_next_ungranted()
        # Request the first ungranted permission
        self._request_current_permission()
        self._update_indicators()

        # Start polling timer
        self._timer_target = _PollTimerTarget.alloc().init()
        self._timer_target._callback = self._poll
        self._timer = AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1.5, self._timer_target, "fire:", None, True
        )

        AppKit.NSApp.setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyRegular
        )
        AppKit.NSApp.activateIgnoringOtherApps_(True)
        self._window.makeKeyAndOrderFront_(None)

    def _advance_to_next_ungranted(self):
        """Move _current_step forward past any already-granted permissions."""
        checkers = {
            "microphone": check_microphone,
            "accessibility": check_accessibility,
        }
        while self._current_step < len(PERM_ORDER):
            perm_key = PERM_ORDER[self._current_step]
            if checkers[perm_key]():
                self._current_step += 1
            else:
                break

    def _request_current_permission(self):
        """Trigger the system prompt for the current permission only."""
        if self._current_step >= len(PERM_ORDER):
            return
        perm_key = PERM_ORDER[self._current_step]
        self._request_permission(perm_key)

    def _request_permission(self, perm_key):
        """Trigger the macOS system prompt for a specific permission."""
        if perm_key == "microphone":
            import AVFoundation

            status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
                AVFoundation.AVMediaTypeAudio
            )
            if status == AVFoundation.AVAuthorizationStatusNotDetermined:
                AVFoundation.AVCaptureDevice.requestAccessForMediaType_completionHandler_(
                    AVFoundation.AVMediaTypeAudio, lambda granted: None
                )

        elif perm_key == "accessibility":
            try:
                from ApplicationServices import AXIsProcessTrustedWithOptions
                from CoreFoundation import kCFBooleanTrue

                AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": kCFBooleanTrue})
            except Exception:
                logger.debug("Could not request accessibility trust", exc_info=True)

    def _poll(self):
        """Called by timer — check if current permission was granted, advance if so."""
        self._update_indicators()

        if self._current_step >= len(PERM_ORDER):
            return  # all done

        checkers = {
            "microphone": check_microphone,
            "accessibility": check_accessibility,
        }

        perm_key = PERM_ORDER[self._current_step]
        granted = checkers[perm_key]()
        logger.info("Poll step=%d perm=%s granted=%s", self._current_step, perm_key, granted)
        if granted:
            # Current permission just got granted — advance to next
            self._current_step += 1
            self._advance_to_next_ungranted()
            self._request_current_permission()
            self._update_indicators()

    def _update_indicators(self):
        """Refresh all indicator icons and the Continue button state."""
        checkers = {
            "microphone": check_microphone,
            "accessibility": check_accessibility,
        }
        all_granted = True
        for perm_key in PERM_ORDER:
            granted = checkers[perm_key]()
            symbol_name = "checkmark.circle.fill" if granted else "xmark.circle.fill"
            color = AppKit.NSColor.systemGreenColor() if granted else AppKit.NSColor.systemRedColor()
            img = AppKit.NSImage.imageWithSystemSymbolName_accessibilityDescription_(
                symbol_name, "granted" if granted else "not granted"
            )
            if img is not None:
                config = AppKit.NSImageSymbolConfiguration.configurationWithPointSize_weight_(
                    13, AppKit.NSFontWeightMedium
                )
                img = img.imageWithSymbolConfiguration_(config)
            self._indicators[perm_key].setImage_(img)
            self._indicators[perm_key].setContentTintColor_(color)
            self._open_buttons[perm_key].setHidden_(granted)
            if not granted:
                all_granted = False

        self._continue_btn.setEnabled_(all_granted)
        if all_granted:
            self._status_label.setStringValue_("All permissions granted!")
            self._status_label.setTextColor_(AppKit.NSColor.systemGreenColor())
        else:
            if self._current_step < len(PERM_ORDER):
                current = PERM_LABELS[PERM_ORDER[self._current_step]]
                self._status_label.setStringValue_(f"Please grant {current} access.")
            else:
                self._status_label.setStringValue_("Grant all permissions to continue.")
            self._status_label.setTextColor_(AppKit.NSColor.secondaryLabelColor())

    def _open_settings(self, perm_key):
        """Button click — open the relevant Settings pane."""
        url_str = SETTINGS_URLS[perm_key]
        url = AppKit.NSURL.URLWithString_(url_str)
        AppKit.NSWorkspace.sharedWorkspace().openURL_(url)

    def _on_continue(self):
        if self._timer is not None:
            self._timer.invalidate()
            self._timer = None
        if self._timer_target is not None:
            self._timer_target._callback = None
        self._window.close()
        # Relaunch via the bundle so _start_normal runs before the run loop,
        # avoiding TSM thread-safety crashes in the pynput listener.
        import subprocess, os
        bundle = AppKit.NSBundle.mainBundle().bundlePath()
        subprocess.Popen(["open", bundle])
        os._exit(0)
