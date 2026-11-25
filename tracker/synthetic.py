"""Sorgente e rilevatore sintetici: persone finte che camminano e agitano le braccia.
Servono per provare Godot e i test end-to-end senza camera (./tracker.sh --synthetic)."""
from __future__ import annotations

import math
import time
from typing import Any

import numpy as np

from .capture import SOURCES, FrameSource
from .detectors.base import DETECTORS, Detector
from .structs import Frame, FrameResult, Person, Point


@SOURCES.register("synthetic")
class SyntheticSource(FrameSource):
    """Frame neri al ritmo indicato (default 30 fps)."""

    def __init__(self, params: dict[str, Any]) -> None:
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


@DETECTORS.register("synthetic")
class SyntheticPeople(Detector):
    """`count` persone (spazio camera) che oscillano avanti e indietro; braccia che salgono e scendono."""

    def process(self, frame: Frame, result: FrameResult) -> None:
        count = int(self.params.get("count", 2))
        t = frame.index / 30.0
        for i in range(count):
            cx = (i + 0.5) / count + 0.12 * math.sin(t * 0.8 + i)
            result.persons.append(_body(cx, 0.35, arm=math.sin(t * 2.0 + i * 1.5)))


def _body(cx: float, sy: float, arm: float) -> Person:
    """Corpo stilizzato; `arm` da -1 (braccia giù) a 1 (braccia in alto)."""
    half = 0.06
    p = Person()
    pts = {
        "nose": (cx, sy - 0.12),
        "shoulder_l": (cx + half, sy), "shoulder_r": (cx - half, sy),
        "hip_l": (cx + half * 0.8, sy + 0.3), "hip_r": (cx - half * 0.8, sy + 0.3),
    }
    for side, sign in (("l", 1.0), ("r", -1.0)):
        sx = cx + sign * half
        ang = arm * 1.2  # radianti rispetto all'orizzontale
        ex, ey = sx + sign * 0.1 * math.cos(ang * 0.5), sy + 0.1 * math.sin(-ang * 0.5) + 0.05
        wx, wy = sx + sign * 0.18 * math.cos(ang), sy - 0.18 * math.sin(ang)
        pts[f"elbow_{side}"] = (ex, ey)
        pts[f"wrist_{side}"] = (wx, wy)
    for name, (x, y) in pts.items():
        p.points[name] = Point(x, y, 0.95)
    p.points["shoulder_c"] = Point(cx, sy, 0.95)
    p.points["hip_c"] = Point(cx, sy + 0.3, 0.95)
    return p
