"""
day123 minigame control backend patch.

The public class/function names and constructor signatures are intentionally
kept compatible with release 26031901.
"""

import config


class PDControlBackend:
    """Default predictive controller path."""

    def __init__(self, input_controller, pd_control):
        self.input = input_controller
        self._pd_control = pd_control

    def control(self, fish, bar, yolo_progress, runtime, ctx) -> bool:
        if runtime.skip_fish:
            self.input.mouse_up()
            return False

        # When both observations disappear, release immediately.
        if fish is None and bar is None:
            self.input.mouse_up()
            return False

        # A temporary miss of only one object is forwarded to PDController,
        # which may reuse the last valid observation for that object.
        return self._pd_control(fish, bar, ctx.search_region)


class ILRecordControlBackend:
    def __init__(self, input_controller, il_adapter):
        self.input = input_controller
        self.il = il_adapter

    def control(self, fish, bar, yolo_progress, runtime, ctx) -> bool:
        frame_det = (
            (fish is not None)
            + (bar is not None)
            + (yolo_progress is not None)
        )
        if runtime.skip_fish or frame_det < 2:
            self.input.mouse_up()
            return False
        self.il.record_frame(runtime.frame, fish, bar)
        return False


class ILModelControlBackend:
    def __init__(self, input_controller, il_adapter):
        self.input = input_controller
        self.il = il_adapter

    def control(self, fish, bar, yolo_progress, runtime, ctx) -> bool:
        frame_det = (
            (fish is not None)
            + (bar is not None)
            + (yolo_progress is not None)
        )
        if runtime.skip_fish or frame_det < 2:
            self.input.mouse_up()
            return False
        return self.il.model_control(fish, bar)


def build_control_backend(bot):
    if config.IL_RECORD:
        return ILRecordControlBackend(bot.input, bot.il)
    if config.IL_USE_MODEL and bot.il.policy is not None:
        return ILModelControlBackend(bot.input, bot.il)
    return PDControlBackend(bot.input, bot._control_mouse)
