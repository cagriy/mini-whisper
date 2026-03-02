"""Settings window for Mini Whisper."""

import logging
import subprocess

import AppKit
import objc
from Foundation import NSMakeRect, NSObject
from pynput.keyboard import Key

from mini_whisper import config
from mini_whisper.hotkey import (
    HotkeyListener,
    build_combo_string,
    format_hotkey,
    parse_hotkey,
)

logger = logging.getLogger(__name__)

_SIDED_MODIFIERS = {Key.cmd_r, Key.shift_r, Key.ctrl_r, Key.alt_r}

WINDOW_WIDTH = 480
WINDOW_HEIGHT = 420


# -- Helper: dispatch from pynput background thread to main thread ----------

class _MainThreadDispatcher(NSObject):
    """Dispatches a Python callable on the main thread."""

    _callable = None

    def initWithCallable_(self, fn):
        self = objc.super(_MainThreadDispatcher, self).init()
        if self is not None:
            self._callable = fn
        return self

    def dispatch_(self, _sender):
        if self._callable is not None:
            self._callable()


def _run_on_main_thread(fn):
    dispatcher = _MainThreadDispatcher.alloc().initWithCallable_(fn)
    dispatcher.performSelectorOnMainThread_withObject_waitUntilDone_(
        "dispatch:", None, False
    )


# -- Custom NSWindow subclass for ESC handling ------------------------------

class _SettingsNSWindow(AppKit.NSWindow):
    """NSWindow subclass that routes ESC to the settings controller."""

    _settings_controller = None

    def cancelOperation_(self, _sender):
        if self._settings_controller is not None:
            self._settings_controller._cancel_capture()


# -- Window delegate --------------------------------------------------------

class _SettingsWindowDelegate(NSObject):
    """Handles window lifecycle events."""

    _settings_controller = None

    def windowWillClose_(self, _notification):
        if self._settings_controller is not None:
            self._settings_controller._on_window_close()


# -- Custom hotkey capture field --------------------------------------------

class _HotkeyField(AppKit.NSTextField):
    """NSTextField that starts hotkey capture on click."""

    _settings_controller = None
    _field_name = None  # "record" or "submit"

    def acceptsFirstResponder(self):
        return True

    def mouseDown_(self, event):
        if self._settings_controller is not None and self._field_name is not None:
            self._settings_controller._start_capture(self._field_name)


# -- Settings Window --------------------------------------------------------

class SettingsWindow:
    """Consolidated settings window for Mini Whisper."""

    _instance = None

    def __init__(self, hotkey_listener: HotkeyListener, cfg: dict, on_save):
        self.hotkey_listener = hotkey_listener
        self.cfg = cfg
        self.on_save = on_save

        self._capturing_field = None  # "record" or "submit"
        self._previous_combo_text = None

        self._build_window()

    def _build_window(self):
        style = (
            AppKit.NSTitledWindowMask
            | AppKit.NSClosableWindowMask
        )
        frame = NSMakeRect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        self.window = _SettingsNSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame, style, AppKit.NSBackingStoreBuffered, False
        )
        self.window.setTitle_("Mini Whisper Settings")
        self.window.setReleasedWhenClosed_(False)
        self.window.center()
        self.window._settings_controller = self

        delegate = _SettingsWindowDelegate.alloc().init()
        delegate._settings_controller = self
        self._delegate = delegate  # prevent GC
        self.window.setDelegate_(delegate)

        content = self.window.contentView()
        y = WINDOW_HEIGHT - 50  # start from top, leaving title bar space

        # -- API Key section ------------------------------------------------
        y = self._add_section_label(content, "API Key", y)
        y -= 30

        self.api_key_field = AppKit.NSSecureTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, 300, 24)
        )
        current_key = config.get_api_key()
        if current_key:
            self.api_key_field.setStringValue_(f"sk-...{current_key[-4:]}")
        self.api_key_field.setPlaceholderString_("sk-...")
        content.addSubview_(self.api_key_field)

        save_key_btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(330, y, 80, 24)
        )
        save_key_btn.setTitle_("Save")
        save_key_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        save_key_btn.setTarget_(self)
        save_key_btn.setAction_(objc.selector(self._save_api_key, signature=b"v@:@"))
        content.addSubview_(save_key_btn)

        y -= 20
        self.api_key_error = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, 390, 16)
        )
        self.api_key_error.setStringValue_("")
        self.api_key_error.setBezeled_(False)
        self.api_key_error.setDrawsBackground_(False)
        self.api_key_error.setEditable_(False)
        self.api_key_error.setSelectable_(False)
        self.api_key_error.setTextColor_(AppKit.NSColor.systemRedColor())
        self.api_key_error.setFont_(AppKit.NSFont.systemFontOfSize_(11))
        content.addSubview_(self.api_key_error)

        # -- Hotkeys section ------------------------------------------------
        y -= 15
        y = self._add_section_label(content, "Hotkeys", y)
        y -= 30

        # Record hotkey
        record_label = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, 120, 24)
        )
        record_label.setStringValue_("Record Hotkey")
        record_label.setBezeled_(False)
        record_label.setDrawsBackground_(False)
        record_label.setEditable_(False)
        record_label.setSelectable_(False)
        content.addSubview_(record_label)

        self.record_field = _HotkeyField.alloc().initWithFrame_(
            NSMakeRect(150, y, 200, 24)
        )
        self.record_field._settings_controller = self
        self.record_field._field_name = "record"
        self.record_field.setEditable_(False)
        self.record_field.setSelectable_(False)
        self.record_field.setAlignment_(AppKit.NSTextAlignmentCenter)
        self._set_hotkey_display(self.record_field, self.cfg.get("hotkey", "shift+cmd_r"))
        content.addSubview_(self.record_field)

        y -= 30

        # Submit hotkey
        submit_label = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, 120, 24)
        )
        submit_label.setStringValue_("Submit Hotkey")
        submit_label.setBezeled_(False)
        submit_label.setDrawsBackground_(False)
        submit_label.setEditable_(False)
        submit_label.setSelectable_(False)
        content.addSubview_(submit_label)

        self.submit_field = _HotkeyField.alloc().initWithFrame_(
            NSMakeRect(150, y, 200, 24)
        )
        self.submit_field._settings_controller = self
        self.submit_field._field_name = "submit"
        self.submit_field.setEditable_(False)
        self.submit_field.setSelectable_(False)
        self.submit_field.setAlignment_(AppKit.NSTextAlignmentCenter)
        self._set_hotkey_display(self.submit_field, self.cfg.get("submit_hotkey", "cmd_r"))
        content.addSubview_(self.submit_field)

        # -- Text Cleanup section -------------------------------------------
        y -= 35
        y = self._add_section_label(content, "Text Cleanup", y)
        y -= 28

        self.cleanup_checkbox = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(20, y, 200, 20)
        )
        self.cleanup_checkbox.setButtonType_(AppKit.NSSwitchButton)
        self.cleanup_checkbox.setTitle_("Enable Text Cleanup")
        self.cleanup_checkbox.setState_(
            1 if self.cfg.get("cleanup_enabled", True) else 0
        )
        self.cleanup_checkbox.setTarget_(self)
        self.cleanup_checkbox.setAction_(
            objc.selector(self._toggle_cleanup, signature=b"v@:@")
        )
        content.addSubview_(self.cleanup_checkbox)

        y -= 110

        scroll = AppKit.NSScrollView.alloc().initWithFrame_(
            NSMakeRect(20, y, 440, 100)
        )
        scroll.setHasVerticalScroller_(True)
        scroll.setBorderType_(AppKit.NSBezelBorder)

        text_frame = NSMakeRect(0, 0, 440, 100)
        self.prompt_view = AppKit.NSTextView.alloc().initWithFrame_(text_frame)
        self.prompt_view.setMinSize_((0, 100))
        self.prompt_view.setMaxSize_((1e7, 1e7))
        self.prompt_view.setVerticallyResizable_(True)
        self.prompt_view.setHorizontallyResizable_(False)
        self.prompt_view.textContainer().setWidthTracksTextView_(True)
        self.prompt_view.setFont_(AppKit.NSFont.systemFontOfSize_(12))

        config.ensure_config_dir()
        prompt_text = config.PROMPT_FILE.read_text() if config.PROMPT_FILE.exists() else ""
        self.prompt_view.setString_(prompt_text)

        scroll.setDocumentView_(self.prompt_view)
        content.addSubview_(scroll)

        y -= 30

        save_prompt_btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(20, y, 110, 24)
        )
        save_prompt_btn.setTitle_("Save Prompt")
        save_prompt_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        save_prompt_btn.setTarget_(self)
        save_prompt_btn.setAction_(
            objc.selector(self._save_prompt, signature=b"v@:@")
        )
        content.addSubview_(save_prompt_btn)

        open_editor_btn = AppKit.NSButton.alloc().initWithFrame_(
            NSMakeRect(140, y, 130, 24)
        )
        open_editor_btn.setTitle_("Open in Editor")
        open_editor_btn.setBezelStyle_(AppKit.NSBezelStyleRounded)
        open_editor_btn.setTarget_(self)
        open_editor_btn.setAction_(
            objc.selector(self._open_in_editor, signature=b"v@:@")
        )
        content.addSubview_(open_editor_btn)

    # -- Helpers ------------------------------------------------------------

    def _add_section_label(self, view, text, y):
        label = AppKit.NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, y, 440, 20)
        )
        label.setStringValue_(text)
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setEditable_(False)
        label.setSelectable_(False)
        label.setFont_(AppKit.NSFont.boldSystemFontOfSize_(13))
        view.addSubview_(label)
        return y

    def _set_hotkey_display(self, field, combo_str):
        try:
            modifiers, trigger, _is_mod = parse_hotkey(combo_str)
            field.setStringValue_(format_hotkey(modifiers, trigger))
        except ValueError:
            field.setStringValue_(combo_str)

    def _get_field(self, name):
        return self.record_field if name == "record" else self.submit_field

    # -- Show / close -------------------------------------------------------

    def show(self):
        AppKit.NSApp.setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyRegular
        )
        AppKit.NSApp.activateIgnoringOtherApps_(True)
        self.window.makeKeyAndOrderFront_(None)

    def close(self):
        if self.window is not None:
            self.window.close()

    def _on_window_close(self):
        self._cancel_capture()
        AppKit.NSApp.setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyAccessory
        )

    # -- API Key callbacks --------------------------------------------------

    @objc.python_method
    def _save_api_key(self, _sender):
        key = self.api_key_field.stringValue().strip()
        if not key or key.startswith("sk-..."):
            self.api_key_error.setStringValue_("Enter a new API key to save.")
            return
        if not key.startswith("sk-"):
            self.api_key_error.setStringValue_("Invalid key — must start with 'sk-'.")
            return
        config.set_api_key(key)
        self.api_key_error.setStringValue_("")
        self.api_key_field.setStringValue_(f"sk-...{key[-4:]}")

    # -- Hotkey capture callbacks -------------------------------------------

    @objc.python_method
    def _start_capture(self, field_name):
        # Cancel any existing capture first
        if self._capturing_field is not None:
            self._cancel_capture()

        field = self._get_field(field_name)
        self._capturing_field = field_name
        self._previous_combo_text = field.stringValue()
        field.setStringValue_("Press shortcut...")
        field.setTextColor_(AppKit.NSColor.placeholderTextColor())

        self.hotkey_listener.enter_capture_mode(
            lambda mods, trigger: self._on_capture(mods, trigger)
        )

    @objc.python_method
    def _on_capture(self, modifiers, trigger):
        """Called from pynput background thread when a combo is captured."""
        # Reject bare non-modifier keys (require a modifier or right-side modifier trigger)
        is_modifier_trigger = isinstance(trigger, Key) and trigger in _SIDED_MODIFIERS
        if not modifiers and not is_modifier_trigger:
            # Re-enter capture mode to try again
            self.hotkey_listener.enter_capture_mode(
                lambda mods, trig: self._on_capture(mods, trig)
            )
            return

        combo_str = build_combo_string(modifiers, trigger)
        display = format_hotkey(modifiers, trigger)

        def apply():
            field_name = self._capturing_field
            if field_name is None:
                return

            field = self._get_field(field_name)
            field.setStringValue_(display)
            field.setTextColor_(AppKit.NSColor.controlTextColor())

            # Update config and hotkey listener
            if field_name == "record":
                config_key = "hotkey"
                binding_name = "paste"
            else:
                config_key = "submit_hotkey"
                binding_name = "paste_submit"

            self.hotkey_listener.update_hotkey(binding_name, combo_str)
            self.cfg[config_key] = combo_str
            config.save(self.cfg)
            self.on_save(self.cfg)

            self._capturing_field = None
            self._previous_combo_text = None

        _run_on_main_thread(apply)

    @objc.python_method
    def _cancel_capture(self):
        if self._capturing_field is None:
            return
        self.hotkey_listener.cancel_capture()
        field = self._get_field(self._capturing_field)
        field.setStringValue_(self._previous_combo_text or "")
        field.setTextColor_(AppKit.NSColor.controlTextColor())
        self._capturing_field = None
        self._previous_combo_text = None

    # -- Text cleanup callbacks ---------------------------------------------

    @objc.python_method
    def _toggle_cleanup(self, _sender):
        enabled = self.cleanup_checkbox.state() == 1
        self.cfg["cleanup_enabled"] = enabled
        config.save(self.cfg)
        self.on_save(self.cfg)

    @objc.python_method
    def _save_prompt(self, _sender):
        text = self.prompt_view.string()
        config.ensure_config_dir()
        config.PROMPT_FILE.write_text(text)

    @objc.python_method
    def _open_in_editor(self, _sender):
        # Save current text first
        self._save_prompt(None)
        subprocess.run(["open", str(config.PROMPT_FILE)])
