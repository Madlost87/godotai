"""Utilità per i test: persone e frame sintetici."""
from __future__ import annotations

import numpy as np

from tracker.structs import Frame, FrameResult, Person, Point


def person_at(x: float, y: float = 0.4) -> Person:
    """Persona con spalle e polsi attorno a (x, y) nello spazio camera."""
    p = Person()
    p.points["shoulder_l"] = Point(x + 0.05, y)
    p.points["shoulder_r"] = Point(x - 0.05, y)
    p.points["shoulder_c"] = Point(x, y)
    p.points["wrist_r"] = Point(x - 0.08, y + 0.2, 0.9)
    return p


def frame(t: float, index: int = 0) -> Frame:
    return Frame(np.zeros((48, 64, 3), dtype=np.uint8), t, index)


def result_with(t: float, *xs: float) -> FrameResult:
    r = FrameResult(frame(t))
    r.persons = [person_at(x) for x in xs]
    return r
