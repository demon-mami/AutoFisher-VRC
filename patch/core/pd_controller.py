"""
FISH! white-bar controller patch.

Base application:
  day123123123/vrc-auto-fish release 26031901

Controller model:
  TheRealShieri/VRCAutoFisher-style predictive HOLD/RELEASE

Characteristics:
- persistent HOLD / RELEASE; no timed sleep pulse
- white-bar velocity estimation
- 150 ms look-ahead
- dynamic dead-zone
- early brake while falling/rising
- temporary single-object miss tolerance
"""

from dataclasses import dataclass
import time
import config


@dataclass
class PDAction:
    should_press: bool
    hold_s: float = 0.0  # compatibility only
    log_message: str = ""


class PDController:
    LOOKAHEAD_S = 0.150
    BRAKE_VELOCITY = 40.0
    FISH_JUMP_REJECT_PX = 80.0

    def __init__(self):
        self.reset()

    def reset(self):
        self.bar_prev_cy = None
        self.bar_prev_time = None
        self.bar_velocity = 0.0

        self.last_bar_cy = None
        self.last_bar_h = None

        self.last_fish_cy = None
        self.fish_smooth_cy = None

        self.frames = 0
        self.last_hold = False

    def _update_bar(self, bar, now):
        if bar is None:
            return

        bar_cy = float(bar[1]) + float(bar[3]) / 2.0

        if self.bar_prev_cy is not None and self.bar_prev_time is not None:
            dt = now - self.bar_prev_time
            if dt > 0.001:
                raw_velocity = (bar_cy - self.bar_prev_cy) / dt
                self.bar_velocity = self.bar_velocity * 0.5 + raw_velocity * 0.5

        self.bar_prev_cy = bar_cy
        self.bar_prev_time = now
        self.last_bar_cy = bar_cy
        self.last_bar_h = max(float(bar[3]), 1.0)

    def _update_fish(self, fish):
        if fish is None:
            return

        raw_fish_cy = float(fish[1]) + float(fish[3]) / 2.0

        if self.last_fish_cy is None:
            fish_cy = raw_fish_cy
        else:
            distance = abs(raw_fish_cy - self.last_fish_cy)
            if distance > self.FISH_JUMP_REJECT_PX:
                fish_cy = self.last_fish_cy
            else:
                fish_cy = self.last_fish_cy * 0.4 + raw_fish_cy * 0.6

        self.last_fish_cy = fish_cy
        self.fish_smooth_cy = fish_cy

    def decide(
        self,
        fish,
        bar,
        search_region=None,
        current_fish_name="",
        detect_roi=None,
    ) -> PDAction:
        self.frames += 1

        # Do not drive the bar from fully stale state.
        if fish is None and bar is None:
            self.last_hold = False
            return PDAction(False)

        now = time.perf_counter()
        self._update_bar(bar, now)
        self._update_fish(fish)

        # One temporarily missing object may reuse its most recent valid
        # observation. day123's own end-of-minigame logic handles longer loss.
        bar_cy = self.last_bar_cy
        bar_h = self.last_bar_h
        fish_cy = self.last_fish_cy

        if bar_cy is None or bar_h is None or fish_cy is None:
            self.last_hold = False
            return PDAction(False)

        # Screen Y grows downward:
        # positive error = bar is below fish -> HOLD to move bar upward.
        error = bar_cy - fish_cy

        half_bar = bar_h / 2.0
        fixed_dead_zone = float(getattr(config, "DEAD_ZONE", 12))
        dead_zone = max(fixed_dead_zone, half_bar * 0.30)

        predicted_error = error + self.bar_velocity * self.LOOKAHEAD_S

        if predicted_error > dead_zone:
            hold = True
            reason = "HOLD-PREDICT"
        elif predicted_error < -dead_zone:
            hold = False
            reason = "RELEASE-PREDICT"
        else:
            if self.bar_velocity > self.BRAKE_VELOCITY:
                hold = True
                reason = "BRAKE-FALL"
            elif self.bar_velocity < -self.BRAKE_VELOCITY:
                hold = False
                reason = "BRAKE-RISE"
            else:
                hold = error > 0
                reason = "HOVER-UP" if hold else "HOVER-DOWN"

        self.last_hold = hold

        log_message = ""
        if self.frames % 15 == 0:
            fish_name = (
                current_fish_name.replace("fish_", "")
                if current_fish_name
                else "?"
            )
            log_message = (
                f"  [SHIERI:{fish_name}] "
                f"e={error:+.0f}px "
                f"pe={predicted_error:+.0f}px "
                f"v={self.bar_velocity:+.0f}px/s "
                f"dz={dead_zone:.0f}px -> {reason}"
            )

        return PDAction(
            should_press=hold,
            hold_s=0.0,
            log_message=log_message,
        )

    def control(
        self,
        fish,
        bar,
        search_region,
        current_fish_name,
        input_controller,
        detect_roi,
    ) -> bool:
        from core.control_executor import ControlExecutor

        action = self.decide(
            fish,
            bar,
            search_region,
            current_fish_name,
            detect_roi,
        )
        return ControlExecutor(input_controller).execute(action)
