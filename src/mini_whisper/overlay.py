"""Floating connected-dots overlay that reacts to audio volume during recording."""

import math
import random
import time

import AppKit
import objc
from Foundation import NSMakeRect, NSMakePoint

# -- Constants ----------------------------------------------------------------

NUM_DOTS = 24
WINDOW_SIZE = 300
DOT_AREA_RADIUS = 100
NUM_RING_DOTS = 10
RING_RADIAL_JITTER = 0.10    # ±10% of DOT_AREA_RADIUS
RING_ANGULAR_JITTER = 0.15   # ±15% of one angular slot width
DOT_RADIUS_MIN = 2.0
DOT_RADIUS_MAX = 5.0
CONNECTION_DISTANCE = 120.0
BG_CORNER_RADIUS = 20.0
BG_ALPHA = 0.7

# Physics
SPRING_K = 30.0
DAMPING = 10.0
AMBIENT_AMPLITUDE = 10.0
AMBIENT_SPEED = 1.2  # rad/s — orbital rotation speed for idle drift
AUDIO_AMPLITUDE = 130.0
PROCESSING_ROTATION_SPEED = 3.0  # rad/s (~0.5 rev/sec) for processing mode
AUDIO_ANGLE_DRIFT = 2.0   # base std dev of audio direction random walk (rad/s)
AUDIO_ANGLE_BOOST = 40.0  # multiplier on drift speed at max audio level

# Audio level normalization (raw RMS range)
LEVEL_FLOOR = 0.005
LEVEL_CEIL = 0.06
SMOOTH_ATTACK = 0.6   # fast ramp-up when audio rises
SMOOTH_DECAY = 0.08   # slow fade when audio drops

FPS = 60.0


# -- Dot data -----------------------------------------------------------------


def _random_dot_position(center_x, center_y, index, total):
    if index < NUM_RING_DOTS:
        slot_width = 2 * math.pi / NUM_RING_DOTS
        base_angle = index * slot_width
        angle = base_angle + random.uniform(-RING_ANGULAR_JITTER, RING_ANGULAR_JITTER) * slot_width
        dist = DOT_AREA_RADIUS * (1.0 + random.uniform(-RING_RADIAL_JITTER, RING_RADIAL_JITTER))
    else:
        angle = random.uniform(0, 2 * math.pi)
        dist = DOT_AREA_RADIUS * math.sqrt(random.uniform(0, 1))
    return center_x + dist * math.cos(angle), center_y + dist * math.sin(angle)


class Dot:
    __slots__ = (
        "home_x", "home_y", "x", "y", "vx", "vy",
        "radius", "phase", "audio_angle",
    )

    def __init__(self, center_x: float, center_y: float, index: int = 0, total: int = 1):
        self.home_x, self.home_y = _random_dot_position(center_x, center_y, index, total)
        self.x = self.home_x
        self.y = self.home_y
        self.vx = 0.0
        self.vy = 0.0
        self.radius = random.uniform(DOT_RADIUS_MIN, DOT_RADIUS_MAX)
        self.phase = random.uniform(0, 2 * math.pi)
        self.audio_angle = random.uniform(0, 2 * math.pi)


# -- NSView subclass ----------------------------------------------------------


class DotsView(AppKit.NSView):
    def initWithFrame_(self, frame):
        self = objc.super(DotsView, self).initWithFrame_(frame)
        if self is None:
            return None
        self._dots: list[Dot] = []
        self._connections: list[tuple[Dot, Dot, float]] = []
        self._duration_text: str = ""
        return self

    def isFlipped(self):
        return False

    def drawRect_(self, rect):
        # Background rounded rect
        bounds = self.bounds()
        bg_path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            bounds, BG_CORNER_RADIUS, BG_CORNER_RADIUS
        )
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
            0.0, 0.0, 0.0, BG_ALPHA
        ).setFill()
        bg_path.fill()

        # Draw connection lines
        white = AppKit.NSColor.whiteColor()
        for dot_a, dot_b, alpha in self._connections:
            white.colorWithAlphaComponent_(alpha * 0.6).setStroke()
            line = AppKit.NSBezierPath.bezierPath()
            line.setLineWidth_(1.0)
            line.moveToPoint_(NSMakePoint(dot_a.x, dot_a.y))
            line.lineToPoint_(NSMakePoint(dot_b.x, dot_b.y))
            line.stroke()

        # Draw dots on top
        white.colorWithAlphaComponent_(0.9).setFill()
        for dot in self._dots:
            r = dot.radius
            dot_rect = NSMakeRect(dot.x - r, dot.y - r, r * 2, r * 2)
            oval = AppKit.NSBezierPath.bezierPathWithOvalInRect_(dot_rect)
            oval.fill()

        # Draw duration text in bottom-right corner
        if self._duration_text:
            attrs = {
                AppKit.NSFontAttributeName: AppKit.NSFont.monospacedDigitSystemFontOfSize_weight_(11.0, AppKit.NSFontWeightRegular),
                AppKit.NSForegroundColorAttributeName: AppKit.NSColor.whiteColor().colorWithAlphaComponent_(0.9),
            }
            text_str = AppKit.NSAttributedString.alloc().initWithString_attributes_(
                self._duration_text, attrs
            )
            text_size = text_str.size()
            text_point = NSMakePoint(
                bounds.size.width - text_size.width - 12,
                10,
            )
            text_str.drawAtPoint_(text_point)


# -- Timer callback target (NSObject so NSTimer can send it a selector) -------


class _TimerTarget(AppKit.NSObject):
    def init(self):
        self = objc.super(_TimerTarget, self).init()
        if self is None:
            return None
        self._callback = None
        return self

    def fire_(self, timer):
        if self._callback is not None:
            self._callback()


# -- Overlay window -----------------------------------------------------------


class DotsOverlayWindow:
    def __init__(self, recorder):
        self._recorder = recorder
        self._smoothed_level = 0.0
        self._timer = None
        self._last_time = time.monotonic()
        self._start_time = 0.0
        self._mode = "recording"
        self._rotation_angle = 0.0

        # Create dots centered in the window
        cx = WINDOW_SIZE / 2
        cy = WINDOW_SIZE / 2
        self._dots = [Dot(cx, cy, i, NUM_DOTS) for i in range(NUM_DOTS)]

        # Timer target (must be NSObject for NSTimer selector dispatch)
        self._timer_target = _TimerTarget.alloc().init()
        self._timer_target._callback = self._tick

        # Window
        screen = AppKit.NSScreen.mainScreen()
        screen_frame = screen.frame()
        wx = (screen_frame.size.width - WINDOW_SIZE) / 2
        wy = (screen_frame.size.height - WINDOW_SIZE) / 2
        frame = NSMakeRect(wx, wy, WINDOW_SIZE, WINDOW_SIZE)

        self._window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            AppKit.NSWindowStyleMaskBorderless,
            AppKit.NSBackingStoreBuffered,
            False,
        )
        self._window.setLevel_(AppKit.NSFloatingWindowLevel)
        self._window.setBackgroundColor_(AppKit.NSColor.clearColor())
        self._window.setOpaque_(False)
        self._window.setHasShadow_(False)
        self._window.setIgnoresMouseEvents_(True)

        # Content view
        self._view = DotsView.alloc().initWithFrame_(
            NSMakeRect(0, 0, WINDOW_SIZE, WINDOW_SIZE)
        )
        self._view._dots = self._dots
        self._view._connections = []
        self._window.setContentView_(self._view)

    def set_mode(self, mode: str):
        self._mode = mode

    def show(self):
        self._smoothed_level = 0.0
        self._mode = "recording"
        self._rotation_angle = 0.0
        now = time.monotonic()
        self._last_time = now
        self._start_time = now
        # Reset dot positions
        cx = WINDOW_SIZE / 2
        cy = WINDOW_SIZE / 2
        for i, dot in enumerate(self._dots):
            dot.home_x, dot.home_y = _random_dot_position(cx, cy, i, NUM_DOTS)
            dot.x = dot.home_x
            dot.y = dot.home_y
            dot.vx = 0.0
            dot.vy = 0.0
            dot.audio_angle = random.uniform(0, 2 * math.pi)

        self._window.orderFront_(None)
        if self._timer is None:
            self._timer = AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                1.0 / FPS, self._timer_target, "fire:", None, True
            )

    def hide(self):
        if self._timer is not None:
            self._timer.invalidate()
            self._timer = None
        self._window.orderOut_(None)

    def cleanup(self):
        self.hide()
        self._timer_target._callback = None

    # -- Animation tick -------------------------------------------------------

    def _tick(self):
        now = time.monotonic()
        dt = min(now - self._last_time, 0.05)  # cap to avoid spiral on lag
        self._last_time = now

        t = now  # for ambient sinusoidal motion
        cx = WINDOW_SIZE / 2
        cy = WINDOW_SIZE / 2

        if self._mode == "processing":
            self._rotation_angle += PROCESSING_ROTATION_SPEED * dt
            angle = self._rotation_angle
            cos_a = math.cos(angle)
            sin_a = math.sin(angle)

            for dot in self._dots:
                # Rotate home position around window center
                dx = dot.home_x - cx
                dy = dot.home_y - cy
                rotated_x = cx + dx * cos_a - dy * sin_a
                rotated_y = cy + dx * sin_a + dy * cos_a

                # Ambient drift on top of rotated position
                orbit_angle = t * AMBIENT_SPEED + dot.phase
                ambient_x = AMBIENT_AMPLITUDE * math.cos(orbit_angle)
                ambient_y = AMBIENT_AMPLITUDE * math.sin(orbit_angle)

                target_x = rotated_x + ambient_x
                target_y = rotated_y + ambient_y

                fx = SPRING_K * (target_x - dot.x) - DAMPING * dot.vx
                fy = SPRING_K * (target_y - dot.y) - DAMPING * dot.vy

                dot.vx += fx * dt
                dot.vy += fy * dt
                dot.x += dot.vx * dt
                dot.y += dot.vy * dt

        else:  # recording mode
            # Read and normalize audio level
            raw = self._recorder.audio_level
            normalized = max(0.0, min(1.0, (raw - LEVEL_FLOOR) / (LEVEL_CEIL - LEVEL_FLOOR)))
            smooth = SMOOTH_ATTACK if normalized > self._smoothed_level else SMOOTH_DECAY
            self._smoothed_level += smooth * (normalized - self._smoothed_level)
            level = self._smoothed_level

            for dot in self._dots:
                # Ambient sinusoidal drift (always present, even at silence)
                orbit_angle = t * AMBIENT_SPEED + dot.phase
                ambient_x = AMBIENT_AMPLITUDE * math.cos(orbit_angle)
                ambient_y = AMBIENT_AMPLITUDE * math.sin(orbit_angle)

                # Audio-driven displacement: coherent direction per dot that drifts
                # slowly (random walk in angle), so the spring can actually track it.
                dot.audio_angle += random.gauss(0, AUDIO_ANGLE_DRIFT) * (1.0 + level * AUDIO_ANGLE_BOOST) * dt
                audio_x = level * AUDIO_AMPLITUDE * math.cos(dot.audio_angle)
                audio_y = level * AUDIO_AMPLITUDE * math.sin(dot.audio_angle)

                # Target = home + ambient + audio
                target_x = dot.home_x + ambient_x + audio_x
                target_y = dot.home_y + ambient_y + audio_y

                # Spring-damper force
                fx = SPRING_K * (target_x - dot.x) - DAMPING * dot.vx
                fy = SPRING_K * (target_y - dot.y) - DAMPING * dot.vy

                # Euler integration
                dot.vx += fx * dt
                dot.vy += fy * dt
                dot.x += dot.vx * dt
                dot.y += dot.vy * dt

        # Compute connections
        connections = []
        for i in range(len(self._dots)):
            for j in range(i + 1, len(self._dots)):
                a, b = self._dots[i], self._dots[j]
                dx = a.x - b.x
                dy = a.y - b.y
                dist = math.sqrt(dx * dx + dy * dy)
                if dist < CONNECTION_DISTANCE:
                    alpha = 1.0 - dist / CONNECTION_DISTANCE
                    connections.append((a, b, alpha))

        self._view._connections = connections
        if self._mode == "processing":
            self._view._duration_text = "processing..."
        else:
            elapsed = now - self._start_time
            self._view._duration_text = f"{elapsed:.1f}s"
        self._view.setNeedsDisplay_(True)
