"""Tipi dati condivisi. Coordinate normalizzate 0..1 nello spazio della camera
(origine in alto a sinistra, immagine non specchiata), finché la proiezione non le
porta nello spazio dello schermo."""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np


@dataclass(slots=True)
class Frame:
    image: np.ndarray  # BGR, come lo dà OpenCV
    t: float  # secondi, orologio monotono
    index: int

    @property
    def size(self) -> tuple[int, int]:
        h, w = self.image.shape[:2]
        return w, h


@dataclass(slots=True)
class Point:
    x: float
    y: float
    conf: float = 1.0


@dataclass(slots=True)
class Hand:
    points: dict[str, Point] = field(default_factory=dict)  # "wrist", "index_tip"...
    values: dict[str, float] = field(default_factory=dict)  # "open", "pinch"...


@dataclass(slots=True)
class Face:
    center: Point
    values: dict[str, float] = field(default_factory=dict)  # "yaw", "pitch", "mouth_open"...


@dataclass(slots=True)
class Marker:
    color: str
    x: float
    y: float
    area: float


@dataclass(slots=True)
class Person:
    """Una persona in un frame. `id` lo assegna lo strato di identità (None = non è un giocatore)."""

    points: dict[str, Point] = field(default_factory=dict)  # nomi della pose (SPEC §5)
    hands: dict[str, Hand] = field(default_factory=dict)  # "l" / "r" della persona
    face: Face | None = None
    marker: Marker | None = None
    id: str | None = None

    # Punti usati, in ordine di preferenza, per seguire la persona tra i frame.
    REFERENCE_POINTS = ("shoulder_c", "nose", "hip_c")

    def reference(self) -> Point | None:
        for name in self.REFERENCE_POINTS:
            if name in self.points:
                return self.points[name]
        return None


@dataclass(slots=True)
class FrameResult:
    frame: Frame
    persons: list[Person] = field(default_factory=list)
    markers: list[Marker] = field(default_factory=list)
    timings: dict[str, float] = field(default_factory=dict)  # ms per stadio

    def players(self) -> list[Person]:
        return sorted((p for p in self.persons if p.id is not None), key=lambda p: p.id or "")
