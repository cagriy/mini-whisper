"""Onboarding window — blocks app until all required permissions are granted."""

import logging

import AppKit
import objc
from Foundation import NSMakeRect, NSObject

logger = logging.getLogger(__name__)

WINDOW_WIDTH = 420
WINDOW_HEIGHT = 300

SETTINGS_URLS = {
    "microphone": "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
    "input_monitoring": "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
    "accessibility": "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
}

PERM_LABELS = {
    "microphone": "Microphone",
    "input_monitoring": "Input Monitoring",
    "accessibility": "Accessibility",
}


# -- Permission checks --------------------------------------------------------


def check_microphone() -> bool:
    import AVFoundation

    status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
        AVFoundation.AVMediaTypeAudio
    )
    return status == AVFoundation.AVAuthorizationStatusAuthorized


def check_input_monitoring() -> bool:
    from Quartz import CGPreflightListenEventAccess

    return bool(CGPreflightListenEventAccess())


def check_accessibility() -> bool:
    from ApplicationServices import AXIsProcessTrustedWithOptions

    options = {"AXTrustedCheckOptionPrompt": False}
    return bool(AXIsProcessTrustedWithOptions(options))


def check_all_permissions() -> dict[str, bool]:
    return {
        "microphone": check_microphone(),
        "input_monitoring": check_input_monitoring(),
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


class OnboardingWindow:
    def __init__(self, on_complete):
        self._on_complete = on_complete
        self._timer = None
        self._timer_target = None
        self._button_targets = []  # prevent GC

        self._build_window()

    def _build_window(self):
        style = AppKit.NSTitledWindowMask
        frame = NSMakeRect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        self._window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame, style, AppKit.NSBackingStoreBuffered, False
        )
        self._window.setTitle_("Mini Whisper — Setup")
        self._window.setReleasedWhenClosed_(False)
        self._window.center()

        delegate = _OnboardingDelegate.alloc().init()
        self._delegate = delegate
        self._window.setDelegate_(delegate)

        content = self._window.contentView()
        y = WINDOW_HEIGHT - 50

        # Title
        title = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, WINDOW_WIDTH - 40, 24)
        )
        title.setStringValue_("Mini Whisper needs a few permissions")
        title.setBezeled_(False)
        title.setDrawsBackground_(False)
        title.setEditable_(False)
        title.setSelectable_(False)
        title.setFont_(AppKit.NSFont.boldSystemFontOfSize_(15))
        content.addSubview_(title)

        # Permission rows
        y -= 15
        self._indicators = {}
        for perm_key in ("microphone", "accessibility", "input_monitoring"):
            y -= 35
            self._add_permission_row(content, perm_key, y)

        # Status label
        y -= 40
        self._status_label = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, WINDOW_WIDTH - 40, 20)
        )
        self._status_label.setStringValue_("Grant all permissions to continue.")
        self._status_label.setBezeled_(False)
        self._status_label.setDrawsBackground_(False)
        self._status_label.setEditable_(False)
        self._status_label.setSelectable_(False)
        self._status_label.setFont_(AppKit.NSFont.systemFontOfSize_(12))
        self._status_label.setTextColor_(AppKit.NSColor.secondaryLabelColor())
        content.addSubview_(self._status_label)

        # Continue button
        y -= 35
        self._continue_btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(WINDOW_WIDTH - 120, y, 100, 30)
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

    def _add_permission_row(self, content, perm_key, y):
        # Status indicator
        indicator = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, 24, 24)
        )
        indicator.setStringValue_("❌")
        indicator.setBezeled_(False)
        indicator.setDrawsBackground_(False)
        indicator.setEditable_(False)
        indicator.setSelectable_(False)
        indicator.setFont_(AppKit.NSFont.systemFontOfSize_(14))
        content.addSubview_(indicator)
        self._indicators[perm_key] = indicator

        # Label
        label = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(48, y, 160, 24)
        )
        label.setStringValue_(PERM_LABELS[perm_key])
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setEditable_(False)
        label.setSelectable_(False)
        content.addSubview_(label)

        # Open Settings button
        btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(WINDOW_WIDTH - 140, y, 120, 24)
        )
        btn.setTitle_("Open Settings")
        btn.setBezelStyle_(AppKit.NSBezelStyleRounded)

        target = _OpenSettingsTarget.alloc().init()
        target._perm_key = perm_key
        target._onboarding = self
        self._button_targets.append(target)
        btn.setTarget_(target)
        btn.setAction_(objc.selector(_OpenSettingsTarget.open_, signature=b"v@:@"))
        content.addSubview_(btn)

    def show(self):
        # Request all permissions upfront so the app appears in System Settings
        self._request_permissions()
        self._update_status()

        # Start polling timer
        self._timer_target = _PollTimerTarget.alloc().init()
        self._timer_target._callback = self._update_status
        self._timer = AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1.5, self._timer_target, "fire:", None, True
        )

        AppKit.NSApp.setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyRegular
        )
        AppKit.NSApp.activateIgnoringOtherApps_(True)
        self._window.makeKeyAndOrderFront_(None)

    def _request_permissions(self):
        """Trigger system permission prompts so the app gets listed in System Settings."""
        # 1. Microphone — request access (triggers native prompt if NotDetermined)
        import AVFoundation

        mic_status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
            AVFoundation.AVMediaTypeAudio
        )
        if mic_status == AVFoundation.AVAuthorizationStatusNotDetermined:
            AVFoundation.AVCaptureDevice.requestAccessForMediaType_completionHandler_(
                AVFoundation.AVMediaTypeAudio, lambda granted: None
            )

        # 2. Accessibility — request with prompt
        try:
            from ApplicationServices import AXIsProcessTrustedWithOptions
            from CoreFoundation import kCFBooleanTrue

            AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": kCFBooleanTrue})
        except Exception:
            logger.debug("Could not request accessibility trust", exc_info=True)

        # 3. Input Monitoring — request access
        from Quartz import CGRequestListenEventAccess

        CGRequestListenEventAccess()

    def _update_status(self):
        perms = check_all_permissions()
        all_granted = True
        for perm_key in ("microphone", "accessibility", "input_monitoring"):
            granted = perms[perm_key]
            self._indicators[perm_key].setStringValue_("✅" if granted else "❌")
            if not granted:
                all_granted = False

        self._continue_btn.setEnabled_(all_granted)
        if all_granted:
            self._status_label.setStringValue_("All permissions granted!")
            self._status_label.setTextColor_(AppKit.NSColor.systemGreenColor())
        else:
            self._status_label.setStringValue_("Grant all permissions to continue.")
            self._status_label.setTextColor_(AppKit.NSColor.secondaryLabelColor())

    def _open_settings(self, perm_key):
        # For microphone, trigger native prompt if not yet determined
        if perm_key == "microphone":
            import AVFoundation

            status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
                AVFoundation.AVMediaTypeAudio
            )
            if status == AVFoundation.AVAuthorizationStatusNotDetermined:
                AVFoundation.AVCaptureDevice.requestAccessForMediaType_completionHandler_(
                    AVFoundation.AVMediaTypeAudio, lambda granted: None
                )
                return

        # For accessibility, request with prompt if not yet trusted
        if perm_key == "accessibility" and not check_accessibility():
            try:
                from ApplicationServices import AXIsProcessTrustedWithOptions
                from CoreFoundation import kCFBooleanTrue

                AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": kCFBooleanTrue})
            except Exception:
                pass

        # For input monitoring, request if not yet granted
        if perm_key == "input_monitoring" and not check_input_monitoring():
            from Quartz import CGRequestListenEventAccess

            CGRequestListenEventAccess()

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
        AppKit.NSApp.setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyAccessory
        )
        if self._on_complete is not None:
            self._on_complete()
