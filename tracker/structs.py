"""Tipi dati condivisi. Coordinate normalizzate 0..1 nello spazio della camera
(origine in alto a sinistra, immagine non specchiata), finché la proiezione non le
porta nello spazio dello schermo."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np


@dataclass(slots=True)
class Frame:
    """Un campione della sorgente. `kind` dice cosa c'è in `data`:
    "image" = array BGR di OpenCV (camera, video); altri sensori useranno altri tipi
    (es. "scan2d" per un LiDAR, "depth" per una camera di profondità)."""

    data: Any
    t: float  # secondi, orologio monotono
    index: int
    kind: str = "image"

    @property
    def image(self) -> np.ndarray:
        if self.kind != "image":
            raise TypeError(f"questo frame contiene '{self.kind}', non un'immagine")
        return self.data

    @property
    def size(self) -> tuple[int, int]:
        """Larghezza e altezza dell'immagine (0, 0 se il frame non è un'immagine)."""
        if self.kind != "image":
            return 0, 0
        h, w = self.data.shape[:2]
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
    # Punti che possono "toccare" i giochi, quando il sensore non dà uno scheletro
    # (es. i tocchi di un LiDAR). Con la pose Godot usa le mani: qui resta vuoto.
    effectors: dict[str, Point] = field(default_factory=dict)
    hands: dict[str, Hand] = field(default_factory=dict)  # "l" / "r" della persona
    face: Face | None = None
    marker: Marker | None = None
    id: str | None = None

    # Punti usati, in ordine di preferenza, per seguire la persona tra i frame.
    REFERENCE_POINTS = ("shoulder_c", "nose", "hip_c", "center")

    def reference(self) -> Point | None:
        for name in self.REFERENCE_POINTS:
            if name in self.points:
                return self.points[name]
        if self.effectors:  # senza scheletro: media degli effettori
            pts = list(self.effectors.values())
            return Point(sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts))
        return None


@dataclass(slots=True)
class FrameResult:
    frame: Frame
    persons: list[Person] = field(default_factory=list)
    markers: list[Marker] = field(default_factory=list)
    timings: dict[str, float] = field(default_factory=dict)  # ms per stadio
    # punti del sensore prima dello stabilizzatore, per id (per registrazioni e analisi)
    raw: dict[str, dict[str, Point]] | None = None

    def players(self) -> list[Person]:
        return sorted((p for p in self.persons if p.id is not None), key=lambda p: p.id or "")
