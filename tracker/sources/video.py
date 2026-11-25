"""Sorgente "video": rilegge un file video (prove e taratura senza camera)."""
from __future__ import annotations

import time
from typing import Any

import cv2

from ..structs import Frame
from .base import SOURCES, FrameSource


@SOURCES.register("video")
class VideoFileSource(FrameSource):
    """Rilegge un file video: utile per provare e tarare senza camera.
    Il tempo dei frame segue gli fps del file, così il risultato è ripetibile."""

    def __init__(self, params: dict[str, Any]) -> None:
        super().__init__(params)
        path = params.get("path", "")
        self._cap = cv2.VideoCapture(str(path))
        if not self._cap.isOpened():
            raise RuntimeError(f"impossibile aprire il video '{path}'")
        self._fps = self._cap.get(cv2.CAP_PROP_FPS) or 30.0
        self._loop = bool(params.get("loop", False))
        self._index = 0
        self._realtime = bool(params.get("realtime", True))
        self._start = time.monotonic()

    def read(self) -> Frame | None:
        ok, image = self._cap.read()
        if not ok and self._loop:
            self._cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ok, image = self._cap.read()
        if not ok:
            return None
        t = self._index / self._fps
        if self._realtime:
            delay = self._start + t - time.monotonic()
            if delay > 0:
                time.sleep(delay)
        frame = Frame(image, t, self._index)
        self._index += 1
        return frame

    def close(self) -> None:
        self._cap.release()
