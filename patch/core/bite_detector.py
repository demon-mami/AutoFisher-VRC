"""HIT/bite detector for AutoFisher-VRC.

The detection model is based on the proven bite detector from
abligail/vrc-fish:
- two FISH! exclamation templates
- full VRChat client-frame template matching
- reference capture geometry 1280x960
- threshold-based confirmation

The templates are fetched once from a pinned upstream Git commit and cached
under patch/assets. Their Git blob SHA-1 is verified before use.
"""

from __future__ import annotations

import hashlib
import os
import time

import cv2
import numpy as np

import config


UPSTREAM_COMMIT = "a196a4ba4ee2be216b21c1a024968345f7b99531"
REFERENCE_HEIGHT = 960
MATCH_THRESHOLD = 0.75
CONFIRM_FRAMES = 1
CHECK_INTERVAL_S = 0.05

_TEMPLATE_SPECS = (
    {
        "name": "bite_exclamation_bottom.png",
        "size": 28166,
        "git_blob_sha": "f711a38afb2ab8f0f68cd0983fde7db269c833d4",
    },
    {
        "name": "bite_exclamation_full.png",
        "size": 18031,
        "git_blob_sha": "eb628229a45ee625076d90b3aaf0fcdcb9f902f3",
    },
)

_RAW_BASE = (
    "https://raw.githubusercontent.com/abligail/vrc-fish/"
    + UPSTREAM_COMMIT
    + "/Resource-VRChat/"
)


def _git_blob_sha(data: bytes) -> str:
    header = ("blob %d\0" % len(data)).encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def _patch_root() -> str:
    here = os.path.abspath(os.path.dirname(__file__))
    return os.path.dirname(here)


def _download_bytes(url: str, timeout: float = 15.0) -> bytes:
    errors = []

    try:
        from urllib.request import Request, urlopen

        req = Request(url, headers={"User-Agent": "AutoFisher-VRC/0.2"})
        with urlopen(req, timeout=timeout) as response:
            data = response.read()
        if data:
            return data
    except Exception as exc:
        errors.append("urllib=%s" % exc)

    try:
        import requests

        response = requests.get(
            url,
            timeout=timeout,
            headers={"User-Agent": "AutoFisher-VRC/0.2"},
        )
        response.raise_for_status()
        if response.content:
            return bytes(response.content)
    except Exception as exc:
        errors.append("requests=%s" % exc)

    raise RuntimeError("template download failed: " + " | ".join(errors))


def _validate_template_bytes(data: bytes, spec: dict) -> None:
    if len(data) != spec["size"]:
        raise RuntimeError(
            "%s size mismatch: %d != %d"
            % (spec["name"], len(data), spec["size"])
        )
    actual = _git_blob_sha(data)
    if actual != spec["git_blob_sha"]:
        raise RuntimeError("%s blob SHA mismatch: %s" % (spec["name"], actual))


def _decode_template(data: bytes):
    raw = cv2.imdecode(
        np.frombuffer(data, dtype=np.uint8),
        cv2.IMREAD_UNCHANGED,
    )
    if raw is None or raw.size == 0:
        raise RuntimeError("template decode failed")

    mask = None
    if raw.ndim == 3 and raw.shape[2] == 4:
        alpha = raw[:, :, 3]
        bgr = raw[:, :, :3]
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        if int(alpha.min()) < 255:
            _, mask = cv2.threshold(alpha, 0, 255, cv2.THRESH_BINARY)
    elif raw.ndim == 2:
        gray = raw
    else:
        gray = cv2.cvtColor(raw, cv2.COLOR_BGR2GRAY)

    return gray, mask


class BiteDetector:
    def __init__(self):
        self.templates = []
        self.ready = False
        self.last_error = ""
        self.last_score = 0.0

    @property
    def assets_dir(self) -> str:
        return os.path.join(_patch_root(), "assets")

    def prepare(self) -> None:
        if self.ready:
            return

        try:
            os.makedirs(self.assets_dir, exist_ok=True)
            loaded = []

            for spec in _TEMPLATE_SPECS:
                path = os.path.join(self.assets_dir, spec["name"])
                data = None

                if os.path.isfile(path):
                    try:
                        with open(path, "rb") as handle:
                            cached = handle.read()
                        _validate_template_bytes(cached, spec)
                        data = cached
                    except Exception:
                        try:
                            os.remove(path)
                        except OSError:
                            pass

                if data is None:
                    data = _download_bytes(_RAW_BASE + spec["name"])
                    _validate_template_bytes(data, spec)
                    tmp = path + ".tmp"
                    with open(tmp, "wb") as handle:
                        handle.write(data)
                    os.replace(tmp, path)

                loaded.append(_decode_template(data))

            self.templates = loaded
            self.ready = True
            self.last_error = ""
        except Exception as exc:
            self.templates = []
            self.ready = False
            self.last_error = str(exc)
            raise

    @staticmethod
    def _gray_frame(frame):
        if frame is None or not hasattr(frame, "shape") or frame.size == 0:
            return None
        h, w = frame.shape[:2]
        if h < 100 or w < 100:
            return None
        if frame.ndim == 2:
            return frame
        return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    @staticmethod
    def _scaled_template(template_gray, template_mask, scale: float):
        if abs(scale - 1.0) < 1e-6:
            return template_gray, template_mask

        tw = max(1, int(round(template_gray.shape[1] * scale)))
        th = max(1, int(round(template_gray.shape[0] * scale)))
        tmpl = cv2.resize(
            template_gray,
            (tw, th),
            interpolation=(cv2.INTER_AREA if scale < 1.0 else cv2.INTER_LINEAR),
        )
        mask = None
        if template_mask is not None:
            mask = cv2.resize(
                template_mask,
                (tw, th),
                interpolation=cv2.INTER_NEAREST,
            )
        return tmpl, mask

    @staticmethod
    def _match_one(gray, template_gray, template_mask, scale: float) -> float:
        tmpl, mask = BiteDetector._scaled_template(
            template_gray, template_mask, scale
        )
        if gray.shape[0] < tmpl.shape[0] or gray.shape[1] < tmpl.shape[1]:
            return 0.0

        try:
            if mask is not None:
                result = cv2.matchTemplate(
                    gray,
                    tmpl,
                    cv2.TM_CCOEFF_NORMED,
                    mask=mask,
                )
            else:
                result = cv2.matchTemplate(
                    gray,
                    tmpl,
                    cv2.TM_CCOEFF_NORMED,
                )
        except cv2.error:
            result = cv2.matchTemplate(
                gray,
                tmpl,
                cv2.TM_CCORR_NORMED,
                mask=mask,
            )

        _, max_val, _, _ = cv2.minMaxLoc(result)
        if not np.isfinite(max_val):
            return 0.0
        return float(max_val)

    def score(self, frame) -> float:
        if not self.ready:
            self.prepare()

        gray = self._gray_frame(frame)
        if gray is None:
            self.last_score = 0.0
            return 0.0

        h = gray.shape[0]
        base_scale = h / float(REFERENCE_HEIGHT)

        best = 0.0
        for template_gray, template_mask in self.templates:
            value = self._match_one(
                gray,
                template_gray,
                template_mask,
                base_scale,
            )
            if value > best:
                best = value

        if 0.45 <= best < MATCH_THRESHOLD:
            for rel in (0.92, 1.08):
                scale = base_scale * rel
                for template_gray, template_mask in self.templates:
                    value = self._match_one(
                        gray,
                        template_gray,
                        template_mask,
                        scale,
                    )
                    if value > best:
                        best = value

        self.last_score = best
        return best

    def detected(self, frame) -> bool:
        return self.score(frame) >= MATCH_THRESHOLD


def get_bite_detector(bot) -> BiteDetector:
    detector = getattr(bot, "_autofisher_bite_detector", None)
    if detector is None:
        detector = BiteDetector()
        bot._autofisher_bite_detector = detector
    return detector


def prepare_bite_detector(bot) -> None:
    get_bite_detector(bot).prepare()


def install_bite_wait_patch(FishingBot) -> None:
    if getattr(FishingBot, "_autofisher_bite_patch_installed", False):
        return

    def _wait_for_minigame_entry(self, start_in_minigame: bool, use_yolo: bool):
        entered_early = bool(start_in_minigame)

        if getattr(config, "IL_RECORD", False) or entered_early:
            return self.running, entered_early

        detector = get_bite_detector(self)
        detector.prepare()

        fallback_s = float(getattr(config, "BITE_FORCE_HOOK", 18.0))
        start_t = time.time()
        consecutive = 0

        while self.running:
            elapsed = time.time() - start_t

            try:
                screen = self._grab()
                self._tick_fps()
            except Exception:
                screen = None

            if screen is not None:
                try:
                    ready, fish, bar, progress = self._detect_minigame_ready_now(
                        screen
                    )
                except Exception:
                    ready, fish, bar, progress = False, None, None, None

                if ready:
                    self._set_minigame_preempt(
                        "AutoFisher: minigame UI already detected"
                    )
                    return True, True

                try:
                    score = detector.score(screen)
                except Exception:
                    score = 0.0

                if score >= MATCH_THRESHOLD:
                    consecutive += 1
                else:
                    consecutive = 0

                try:
                    self._show_debug_overlay(
                        screen,
                        fish,
                        bar,
                        progress=progress,
                        status_text=(
                            "HIT wait  score=%.3f  %d/%d"
                            % (score, consecutive, CONFIRM_FRAMES)
                        ),
                    )
                except Exception:
                    pass

                if consecutive >= CONFIRM_FRAMES:
                    preempted = bool(self._hook_fish())
                    return self.running, preempted

            if elapsed >= fallback_s:
                preempted = bool(self._hook_fish())
                return self.running, preempted

            time.sleep(CHECK_INTERVAL_S)

        return False, entered_early

    FishingBot._wait_for_minigame_entry = _wait_for_minigame_entry
    FishingBot._autofisher_bite_patch_installed = True
