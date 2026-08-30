"""AutoFisher-VRC minimal operating GUI."""

from __future__ import annotations

import threading
import tkinter as tk
from tkinter import ttk

import keyboard

import config
from core.bite_detector import install_bite_wait_patch, prepare_bite_detector
from core.bot import FishingBot


# Patch day123's fixed-time wait before any FishingBot instance is created.
install_bite_wait_patch(FishingBot)


class FishingApp:
    APP_VERSION = "0.2.1"

    def __init__(self, root: tk.Tk):
        self.root = root
        self.bot_thread = None
        self._closing = False

        # Fixed normal-use profile.
        config.IL_RECORD = False
        config.IL_USE_MODEL = False
        config.YOLO_COLLECT = False
        config.YOLO_RAW_DEBUG = False
        config.SHOW_DEBUG = False

        # Use the HIT reaction delay proven by Shieri as the hook pre-delay.
        config.HOOK_PRE_DELAY = 0.08

        # After dismissing the caught fish, one second is enough before the
        # next round starts.
        config.POST_CATCH_DELAY = 1.0

        self.bot = FishingBot()
        self.bot.debug_mode = False

        self.var_connection = tk.StringVar(value="VRChat: 検出中…")
        self.var_status = tk.StringVar(value="待機")
        self.var_count = tk.StringVar(value="釣果  0")
        self.var_debug = tk.BooleanVar(value=False)

        self._build_ui()
        self._register_hotkeys()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self._refresh_connection()
        self._poll()

    def _build_ui(self):
        self.root.title("AutoFisher-VRC")
        self.root.geometry("360x230")
        self.root.minsize(360, 230)
        self.root.maxsize(360, 230)
        self.root.resizable(False, False)

        main = ttk.Frame(self.root, padding=(18, 16))
        main.pack(fill="both", expand=True)

        ttk.Label(
            main,
            text="AutoFisher-VRC",
            font=("TkDefaultFont", 15, "bold"),
        ).pack(anchor="w")

        ttk.Label(
            main,
            textvariable=self.var_connection,
        ).pack(anchor="w", pady=(8, 0))

        row = ttk.Frame(main)
        row.pack(fill="x", pady=(12, 10))

        ttk.Label(
            row,
            textvariable=self.var_status,
            font=("TkDefaultFont", 11, "bold"),
        ).pack(side="left")

        ttk.Label(
            row,
            textvariable=self.var_count,
        ).pack(side="right")

        self.btn_main = ttk.Button(
            main,
            text="開始  [F9]",
            command=self._toggle_start_stop,
        )
        self.btn_main.pack(fill="x", ipady=8)

        debug_row = ttk.Frame(main)
        debug_row.pack(fill="x", pady=(12, 0))

        ttk.Checkbutton(
            debug_row,
            text="Debug表示  [F11]",
            variable=self.var_debug,
            command=self._toggle_debug_from_ui,
        ).pack(side="left")

        ttk.Label(
            debug_row,
            text="F10: 停止",
        ).pack(side="right")

        ttk.Label(
            main,
            text="開始時にHIT検出を確認してから自動釣りを開始します。",
            foreground="gray",
        ).pack(anchor="w", pady=(12, 0))

    def _register_hotkeys(self):
        keyboard.add_hotkey(
            config.HOTKEY_TOGGLE,
            lambda: self.root.after(0, self._toggle_start_stop),
        )
        keyboard.add_hotkey(
            config.HOTKEY_STOP,
            lambda: self.root.after(0, self._stop),
        )
        keyboard.add_hotkey(
            config.HOTKEY_DEBUG,
            lambda: self.root.after(0, self._toggle_debug_hotkey),
        )

    def _refresh_connection(self):
        try:
            if self.bot.window.is_valid() or self.bot.window.find():
                self.var_connection.set("VRChat: 接続済み")
                return True
        except Exception:
            pass

        self.var_connection.set("VRChat: 未検出")
        return False

    def _prepare_hit_detector(self):
        self.var_status.set("HIT検出を準備中…")
        self.root.update_idletasks()
        try:
            prepare_bite_detector(self.bot)
            return True
        except Exception as exc:
            self.var_status.set("HIT検出の準備エラー")
            # Keep the exact reason available without exposing the old log UI.
            self.bot._autofisher_prepare_error = str(exc)
            return False

    def _start(self):
        if self.bot.running or self._closing:
            return

        if not self._refresh_connection():
            self.var_status.set("VRChatを起動してください")
            return

        # Never enter an automation run with an unusable HIT detector.
        if not self._prepare_hit_detector():
            return

        try:
            self.bot.running = True
            self.bot.state = "status.running"

            if self.bot_thread is None or not self.bot_thread.is_alive():
                self.bot_thread = threading.Thread(
                    target=self.bot.run,
                    daemon=True,
                    name="AutoFisher",
                )
                self.bot_thread.start()

            self.var_status.set("自動釣り中")
            self.btn_main.config(text="停止  [F9]")
        except Exception:
            self.bot.running = False
            self.bot.input.safe_release()
            self.var_status.set("開始エラー")
            self.btn_main.config(text="開始  [F9]")

    def _stop(self):
        if self._closing:
            return

        self.bot.running = False
        self.bot._force_minigame = False
        self.bot.input.safe_release()
        self.var_status.set("待機")
        self.btn_main.config(text="開始  [F9]")

    def _toggle_start_stop(self):
        if self.bot.running:
            self._stop()
        else:
            self._start()

    def _set_debug(self, enabled: bool):
        enabled = bool(enabled)
        self.var_debug.set(enabled)
        self.bot.debug_mode = enabled
        config.SHOW_DEBUG = enabled

        if not enabled:
            self.bot.shutdown_debug_overlay()

    def _toggle_debug_from_ui(self):
        self._set_debug(self.var_debug.get())

    def _toggle_debug_hotkey(self):
        self._set_debug(not self.var_debug.get())

    def _poll(self):
        if self._closing:
            return

        try:
            if self.bot.running:
                self.var_status.set("自動釣り中")
                self.btn_main.config(text="停止  [F9]")
            elif self.var_status.get() == "自動釣り中":
                self.var_status.set("待機")
                self.btn_main.config(text="開始  [F9]")

            self.var_count.set("釣果  %d" % self.bot.fish_count)

            if self.bot.window.is_valid():
                self.var_connection.set("VRChat: 接続済み")
            else:
                self.var_connection.set("VRChat: 未検出")
        except Exception:
            pass

        self.root.after(250, self._poll)

    def _on_close(self):
        if self._closing:
            return

        self._closing = True

        try:
            self.bot.running = False
            self.bot._force_minigame = False
            self.bot.input.safe_release()
            self.bot.shutdown_debug_overlay()
        except Exception:
            pass

        try:
            keyboard.unhook_all_hotkeys()
        except Exception:
            pass

        self.root.destroy()
