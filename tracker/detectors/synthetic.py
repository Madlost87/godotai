"""Rilevatori sintetici: dati finti ma realistici, per test e prove senza sensore.

- "synthetic": persone con scheletro che oscillano e agitano le braccia (come la pose).
- "synthetic_contacts": solo punti di contatto, senza scheletro, come farebbe un LiDAR
  che vede le mani sul muro. Serve a verificare che i giochi funzionino anche con
  sensori che non danno la pose (usano gli effettori)."""
from __future__ import annotations

import math

from ..structs import Frame, FrameResult, Person, Point
from .base import DETECTORS, Detector


@DETECTORS.register("synthetic")
class SyntheticPeople(Detector):
    """`count` persone (spazio camera) che oscillano; braccia che salgono e scendono."""

    accepts = ("*",)
    provides = ("pose", "effectors")

    def process(self, frame: Frame, result: FrameResult) -> None:
        count = int(self.params.get("count", 2))
        t = frame.index / 30.0
        for i in range(count):
            cx = (i + 0.5) / count + 0.12 * math.sin(t * 0.8 + i)
            result.persons.append(_body(cx, 0.35, arm=math.sin(t * 2.0 + i * 1.5)))


@DETECTORS.register("synthetic_contacts")
class SyntheticContacts(Detector):
    """`count` persone viste solo come due punti di contatto (mani) che girano in cerchio."""

    accepts = ("*",)
    provides = ("effectors",)

    def process(self, frame: Frame, result: FrameResult) -> None:
        count = int(self.params.get("count", 1))
        t = frame.index / 30.0
        for i in range(count):
            cx = (i + 0.5) / count
            p = Person()
            for k, name in enumerate(("e0", "e1")):
                a = t * 1.5 + k * math.pi + i
                p.effectors[name] = Point(cx + 0.15 * math.cos(a), 0.5 + 0.25 * math.sin(a), 0.9)
            result.persons.append(p)


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
