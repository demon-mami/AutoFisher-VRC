"""
Non-blocking day123 ControlExecutor patch.

The original release converts each controller decision into:
  mouse_down -> sleep(hold_s) -> mouse_up

This patch keeps HOLD/RELEASE state until the next detection frame so the
predictive controller can reverse immediately.
"""

from utils.logger import log


class ControlExecutor:
    def __init__(self, input_controller, sleep_fn=None, logger=log):
        self.input = input_controller
        self._log = logger

    def release(self, log_message: str = "") -> bool:
        self.input.mouse_up()
        if log_message:
            self._log.info(log_message)
        return False

    def execute(self, action) -> bool:
        if action.should_press:
            self.input.mouse_down()
            if action.log_message:
                self._log.info(action.log_message)
            return True

        return self.release(action.log_message)
