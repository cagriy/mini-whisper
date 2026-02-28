"""Mini Whisper menu bar application."""

import logging
import subprocess
import threading
import time

import AppKit
from Foundation import NSMakeRect
import rumps

from mini_whisper import config
from mini_whisper.controller import Controller, UIEvent
from mini_whisper.hotkey import HotkeyListener, format_hotkey

logger = logging.getLogger(__name__)


def _notify(title: str, subtitle: str, message: str, sound: bool = True):
    """Send a macOS notification, silently ignoring failures."""
    try:
        rumps.notification(title, subtitle, message, sound=sound)
    except RuntimeError:
        logger.debug("Notification failed (missing Info.plist?): %s", message)


class _ModalStopper(AppKit.NSObject):
    """Helper to dismiss a modal dialog from a background thread."""

    def stop_(self, sender):
        AppKit.NSApp.stopModal()


def _input_dialog(title: str, message: str, default_text: str = "") -> str | None:
    """Show a modal input dialog with proper keyboard focus.

    Temporarily switches the app to Regular activation policy so macOS
    treats it as a real foreground app that can own keyboard focus.
    Returns the entered text, or None if cancelled.
    """
    alert = AppKit.NSAlert.alloc().init()
    alert.setMessageText_(title)
    alert.setInformativeText_(message)
    alert.addButtonWithTitle_("Save")
    alert.addButtonWithTitle_("Cancel")
    alert.setAlertStyle_(AppKit.NSAlertStyleInformational)

    tf = AppKit.NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 24))
    tf.setStringValue_(default_text)
    alert.setAccessoryView_(tf)
    alert.window().setInitialFirstResponder_(tf)

    # Temporarily become a Regular app so we can properly own keyboard focus.
    # Accessory/LSUIElement apps cannot sustain key window status.
    prev_policy = AppKit.NSApp.activationPolicy()
    AppKit.NSApp.setActivationPolicy_(AppKit.NSApplicationActivationPolicyRegular)
    AppKit.NSApp.activateIgnoringOtherApps_(True)

    clicked_save = alert.runModal() == 1000  # NSAlertFirstButtonReturn

    # Restore menu-bar-only mode (hides dock icon)
    AppKit.NSApp.setActivationPolicy_(prev_policy)

    return tf.stringValue() if clicked_save else None


TITLE_IDLE = "MW"
TITLE_RECORDING = "🔴"
TITLE_PROCESSING = "⏳"


class MiniWhisperApp(rumps.App):
    def __init__(self):
        super().__init__(TITLE_IDLE, quit_button=None)

        self.cfg = config.load()
        self.controller = Controller()

        # Non-clickable info items (no callback = greyed out is fine, but we
        # want them to look like labels — pass a no-op so they appear enabled)
        self.status_item = rumps.MenuItem("Status: Idle")
        self.last_item = rumps.MenuItem('Last: ""')

        self.cleanup_item = rumps.MenuItem(
            "Enable Text Cleanup", callback=self._toggle_cleanup
        )
        self.cleanup_item.state = self.cfg.get("cleanup_enabled", True)

        self.menu = [
            self.status_item,
            self.last_item,
            None,
            rumps.MenuItem("Set API Key...", callback=self._set_api_key),
            rumps.MenuItem("Change Hotkey...", callback=self._change_hotkey),
            rumps.MenuItem("Edit Cleanup Prompt...", callback=self._edit_prompt),
            self.cleanup_item,
            None,
            rumps.MenuItem("About Mini Whisper", callback=self._about),
            rumps.MenuItem("Quit", callback=self._quit),
        ]

        combo = self.cfg.get("hotkey", "cmd+shift+space")
        self.hotkey_listener = HotkeyListener(
            combo,
            on_press=self.controller.on_hotkey_press,
            on_release=self.controller.on_hotkey_release,
        )

        self.poll_timer = rumps.Timer(self._poll_ui_events, 0.1)

    # ------------------------------------------------------------------
    # UI polling (runs on main thread via rumps Timer)
    # ------------------------------------------------------------------

    def _poll_ui_events(self, _timer):
        while True:
            try:
                event: UIEvent = self.controller.ui_queue.get_nowait()
            except Exception:
                break

            if event.kind == "recording":
                self.title = TITLE_RECORDING
                self.status_item.title = "Status: Recording..."
            elif event.kind == "processing":
                self.title = TITLE_PROCESSING
                self.status_item.title = "Status: Processing..."
            elif event.kind == "idle":
                self.title = TITLE_IDLE
                self.status_item.title = "Status: Idle"
            elif event.kind == "result":
                self.title = TITLE_IDLE
                self.status_item.title = "Status: Idle"
                truncated = event.text[:50] + ("..." if len(event.text) > 50 else "")
                self.last_item.title = f'Last: "{truncated}"'
            elif event.kind == "error":
                self.title = TITLE_IDLE
                self.status_item.title = "Status: Error"
                _notify("Mini Whisper", "Error", event.text, sound=False)

    # ------------------------------------------------------------------
    # Menu callbacks
    # ------------------------------------------------------------------

    def _set_api_key(self, _):
        current = config.get_api_key()
        masked = f"sk-...{current[-4:]}" if current else ""
        text = _input_dialog("Set API Key", "Enter your OpenAI API key:", masked)
        if text and text.strip():
            key = text.strip()
            if key.startswith("sk-"):
                config.set_api_key(key)
                _notify("Mini Whisper", "API Key Saved", "Key stored in Keychain.")
            else:
                rumps.alert("Invalid API key — it must start with 'sk-'.")

    def _change_hotkey(self, _):
        from pynput.keyboard import Key, KeyCode

        captured = {}

        def on_capture(modifiers, trigger):
            if not modifiers:
                # No modifier held — reject, re-enter capture for another try
                self.hotkey_listener.enter_capture_mode(on_capture)
                return
            captured["modifiers"] = modifiers
            captured["trigger"] = trigger
            # Dismiss the dialog from pynput's background thread
            stopper = _ModalStopper.alloc().init()
            stopper.performSelectorOnMainThread_withObject_waitUntilDone_(
                "stop:", None, False
            )

        self.hotkey_listener.enter_capture_mode(on_capture)

        # Show a dialog that stays open while we wait for the key combo
        alert = AppKit.NSAlert.alloc().init()
        alert.setMessageText_("Change Hotkey")
        alert.setInformativeText_(
            "Press your desired shortcut now...\n\n"
            "Must include \u2318 (Cmd) and/or \u21e7 (Shift) with another key."
        )
        alert.addButtonWithTitle_("Cancel")

        prev_policy = AppKit.NSApp.activationPolicy()
        AppKit.NSApp.setActivationPolicy_(AppKit.NSApplicationActivationPolicyRegular)
        AppKit.NSApp.activateIgnoringOtherApps_(True)

        alert.runModal()  # blocks until Cancel or stopModal() from capture

        AppKit.NSApp.setActivationPolicy_(prev_policy)
        self.hotkey_listener.cancel_capture()  # no-op if already captured

        if captured:
            modifiers = captured["modifiers"]
            trigger = captured["trigger"]
            display = format_hotkey(modifiers, trigger)

            reverse_mod = {Key.cmd: "cmd", Key.shift: "shift", Key.ctrl: "ctrl", Key.alt: "alt"}
            parts = [reverse_mod.get(m, str(m)) for m in modifiers]
            if isinstance(trigger, Key):
                parts.append(trigger.name)
            elif isinstance(trigger, KeyCode) and trigger.char:
                parts.append(trigger.char)
            else:
                parts.append(str(trigger))

            combo_str = "+".join(parts)
            self.hotkey_listener.update_hotkey(combo_str)
            self.cfg["hotkey"] = combo_str
            config.save(self.cfg)
            _notify("Mini Whisper", "Hotkey Changed", f"New hotkey: {display}")

    def _edit_prompt(self, _):
        config.ensure_config_dir()
        subprocess.run(["open", str(config.PROMPT_FILE)])

    def _toggle_cleanup(self, sender):
        sender.state = not sender.state
        self.cfg["cleanup_enabled"] = bool(sender.state)
        config.save(self.cfg)

    def _about(self, _):
        rumps.alert(
            title="Mini Whisper",
            message=(
                "Version 0.1.0\n\n"
                "Hold your hotkey, speak, release —\n"
                "transcribed text is pasted into the active app.\n\n"
                "Powered by OpenAI Whisper + GPT-4o-mini."
            ),
        )

    def _quit(self, _):
        self.hotkey_listener.stop()
        rumps.quit_application()

    # ------------------------------------------------------------------
    # App lifecycle
    # ------------------------------------------------------------------

    def run(self, **kwargs):
        self.hotkey_listener.start()
        self.poll_timer.start()
        if not config.get_api_key():
            rumps.Timer(self._first_run_prompt, 1).start()
        super().run(**kwargs)

    def _first_run_prompt(self, timer):
        timer.stop()
        rumps.alert(
            title="Welcome to Mini Whisper!",
            message=(
                "To get started, set your OpenAI API key.\n\n"
                "You'll also need to grant Microphone, Accessibility,\n"
                "and Input Monitoring access in:\n"
                "System Settings → Privacy & Security."
            ),
        )
        self._set_api_key(None)


def main():
    logging.basicConfig(level=logging.INFO)
    MiniWhisperApp().run()


if __name__ == "__main__":
    main()
