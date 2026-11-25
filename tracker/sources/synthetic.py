"""Sorgente "synthetic": frame neri a ritmo fisso, da usare con i rilevatori sintetici
(detectors/synthetic.py) per provare Godot e i test senza nessun sensore."""
from __future__ import annotations

import time
from typing import Any

import numpy as np

from ..structs import Frame
from .base import SOURCES, FrameSource


@SOURCES.register("synthetic")
class SyntheticSource(FrameSource):
    produces = "image"

    def __init__(self, params: dict[str, Any]) -> None:
        super().__init__(params)
        self._dt = 1.0 / float(params.get("fps", 30))
        self._image = np.zeros((int(params.get("height", 120)), int(params.get("width", 160)), 3), np.uint8)
        self._index = 0
        self._start = time.monotonic()

    def read(self) -> Frame | None:
        t = self._start + self._index * self._dt
        delay = t - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        frame = Frame(self._image, t, self._index)
        self._index += 1
        return frame
