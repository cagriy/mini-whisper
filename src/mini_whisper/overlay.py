"""Floating waveform overlay shown during recording."""

import AppKit
import objc
from Foundation import NSMakeRect

BAR_COUNT = 40
PANEL_WIDTH = 300
PANEL_HEIGHT = 40


class WaveformView(AppKit.NSView):
    """Custom view that draws vertical waveform bars."""

    def initWithFrame_(self, frame):
        self = objc.super(WaveformView, self).initWithFrame_(frame)
        if self is None:
            return None
        self._amplitudes = [0.0] * BAR_COUNT
        return self

    def drawRect_(self, rect):
        bounds = self.bounds()
        w, h = bounds.size.width, bounds.size.height

        # Dark rounded-rect background
        bg = AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.1, 0.1, 0.1, 0.85)
        bg_path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            bounds, 12.0, 12.0
        )
        bg.setFill()
        bg_path.fill()

        # Bar geometry
        total_bars = len(self._amplitudes)
        gap = 2.0
        bar_w = (w - gap * (total_bars + 1)) / total_bars
        max_h = h * 0.8
        min_h = 2.0

        bar_color = AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
            0.85, 0.85, 0.85, 0.9
        )
        bar_color.setFill()

        for i, amp in enumerate(self._amplitudes):
            x = gap + i * (bar_w + gap)
            bar_h = max(min_h, amp * max_h)
            y = (h - bar_h) / 2.0
            bar_rect = NSMakeRect(x, y, bar_w, bar_h)
            radius = bar_w / 2.0
            bar_path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
                bar_rect, radius, radius
            )
            bar_path.fill()

    def updateAmplitudes_(self, amplitudes):
        self._amplitudes = amplitudes
        self.setNeedsDisplay_(True)


def _create_panel(view):
    """Create a non-activating floating panel for the waveform overlay."""
    screen = AppKit.NSScreen.mainScreen().frame()
    x = (screen.size.width - PANEL_WIDTH) / 2.0
    y = screen.size.height - PANEL_HEIGHT - 50

    style = AppKit.NSWindowStyleMaskBorderless | AppKit.NSWindowStyleMaskNonactivatingPanel
    panel = AppKit.NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
        NSMakeRect(x, y, PANEL_WIDTH, PANEL_HEIGHT),
        style,
        AppKit.NSBackingStoreBuffered,
        False,
    )
    panel.setLevel_(AppKit.NSFloatingWindowLevel)
    panel.setOpaque_(False)
    panel.setBackgroundColor_(AppKit.NSColor.clearColor())
    panel.setHasShadow_(True)
    panel.setIgnoresMouseEvents_(True)
    panel.setCollectionBehavior_(
        AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
        | AppKit.NSWindowCollectionBehaviorFullScreenAuxiliary
    )
    panel.setContentView_(view)
    return panel


class _TimerTarget(AppKit.NSObject):
    """NSObject helper so NSTimer can call back into WaveformOverlay."""

    overlay = None

    def tick_(self, timer):
        if self.overlay is not None:
            self.overlay._tick()


class WaveformOverlay:
    """Manages the waveform overlay panel lifecycle and animation."""

    def __init__(self):
        self._view = WaveformView.alloc().initWithFrame_(
            NSMakeRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT)
        )
        self._panel = _create_panel(self._view)
        self._timer = None
        self._amplitude_source = None
        self._target = _TimerTarget.alloc().init()
        self._target.overlay = self

    def show(self, amplitude_source):
        """Show the overlay and start animating at ~30fps."""
        self._amplitude_source = amplitude_source
        self._view._amplitudes = [0.0] * BAR_COUNT
        self._panel.orderFront_(None)
        self._timer = (
            AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                1.0 / 30.0, self._target, b"tick:", None, True
            )
        )

    def hide(self):
        """Hide the overlay and stop animation."""
        if self._timer is not None:
            self._timer.invalidate()
            self._timer = None
        self._amplitude_source = None
        self._panel.orderOut_(None)

    def _tick(self):
        """Timer callback: shift amplitudes left, append new value, redraw."""
        if self._amplitude_source is None:
            return
        new_amp = self._amplitude_source()
        amps = self._view._amplitudes
        amps.pop(0)
        amps.append(new_amp)
        self._view.updateAmplitudes_(amps)
