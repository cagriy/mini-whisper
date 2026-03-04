"""Mini Whisper menu bar application."""

import logging
from pathlib import Path

import rumps

from mini_whisper import config
from mini_whisper.controller import Controller, UIEvent
from mini_whisper.hotkey import HotkeyListener
from mini_whisper.overlay import DotsOverlayWindow
from mini_whisper.settings import SettingsWindow

logger = logging.getLogger(__name__)


def _notify(title: str, subtitle: str, message: str, sound: bool = True):
    """Send a macOS notification, silently ignoring failures."""
    try:
        rumps.notification(title, subtitle, message, sound=sound)
    except RuntimeError:
        logger.debug("Notification failed (missing Info.plist?): %s", message)


TITLE_IDLE = ""
TITLE_RECORDING = "🔴"
TITLE_RECORDING_TOGGLE = "🔴"
TITLE_PROCESSING = "⏳"
_ICON_PATH = str(Path(__file__).parent / "assets" / "mini-whisper.png")


class MiniWhisperApp(rumps.App):
    def __init__(self):
        super().__init__(TITLE_IDLE, icon=_ICON_PATH, template=True, quit_button=None)

        self.cfg = config.load()
        self.controller = Controller()

        self.status_item = rumps.MenuItem("Status: Idle")
        self.last_item = rumps.MenuItem('Last: ""')

        self.menu = [
            self.status_item,
            self.last_item,
            None,
            rumps.MenuItem("Settings...", callback=self._open_settings),
            None,
            rumps.MenuItem("About Mini Whisper", callback=self._about),
            rumps.MenuItem("Quit", callback=self._quit),
        ]

        self.hotkey_listener = HotkeyListener()

        paste_combo = self.cfg.get("hotkey", "shift+cmd_r")
        self.hotkey_listener.register(
            "paste",
            paste_combo,
            on_press=lambda: self.controller.on_hotkey_press("paste"),
            on_release=lambda: self.controller.on_hotkey_release("paste"),
        )

        submit_combo = self.cfg.get("submit_hotkey", "cmd_r")
        self.hotkey_listener.register(
            "paste_submit",
            submit_combo,
            on_press=lambda: self.controller.on_hotkey_press("paste_submit"),
            on_release=lambda: self.controller.on_hotkey_release("paste_submit"),
        )

        self.overlay = DotsOverlayWindow(self.controller.recorder)
        self.poll_timer = rumps.Timer(self._poll_ui_events, 0.1)
        self._settings_window = None

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
                self.overlay.show()
            elif event.kind == "recording_toggle":
                self.title = TITLE_RECORDING_TOGGLE
                self.status_item.title = "Status: Recording (tap to stop)..."
            elif event.kind == "processing":
                self.title = TITLE_PROCESSING
                self.status_item.title = "Status: Processing..."
                self.overlay.set_mode("processing")
            elif event.kind == "idle":
                self.title = TITLE_IDLE
                self.status_item.title = "Status: Idle"
                self.overlay.hide()
            elif event.kind == "result":
                self.title = TITLE_IDLE
                self.status_item.title = "Status: Idle"
                self.overlay.hide()
                truncated = event.text[:50] + ("..." if len(event.text) > 50 else "")
                self.last_item.title = f'Last: "{truncated}"'
            elif event.kind == "error":
                self.title = TITLE_IDLE
                self.status_item.title = "Status: Error"
                self.overlay.hide()
                _notify("Mini Whisper", "Error", event.text, sound=False)

    # ------------------------------------------------------------------
    # Menu callbacks
    # ------------------------------------------------------------------

    def _open_settings(self, _):
        if self._settings_window is None:
            self._settings_window = SettingsWindow(
                self.hotkey_listener, self.cfg, self._on_settings_changed
            )
        self._settings_window.show()

    def _on_settings_changed(self, new_cfg):
        self.cfg = new_cfg

    def _about(self, _):
        rumps.alert(
            title="Mini Whisper",
            message=(
                "Version 0.1.0\n\n"
                "Hold your hotkey to talk, or tap to toggle recording.\n"
                "Transcribed text is pasted into the active app.\n\n"
                "Powered by OpenAI Whisper + GPT-4o-mini."
            ),
        )

    def _quit(self, _):
        if self._settings_window is not None:
            self._settings_window.close()
        self.overlay.cleanup()
        self.hotkey_listener.stop()
        self.controller.recorder.close()
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
        self._open_settings(None)


def main():
    import os
    level = os.environ.get("LOG_LEVEL", "INFO").upper()
    logging.basicConfig(level=getattr(logging, level, logging.INFO), force=True)
    logging.getLogger("httpx").setLevel(logging.DEBUG if level == "DEBUG" else logging.WARNING)
    MiniWhisperApp().run()


if __name__ == "__main__":
    main()
