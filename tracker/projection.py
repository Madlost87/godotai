"""Mappatura sensore → schermo: come le coordinate del sensore (0..1 sull'immagine) diventano
coordinate dello schermo di gioco (0..1). Modalità (config "projection.mode", --mapping):

- "homography": proiettore calibrato (tools/calibration): la mano cade sulla sua ombra.
- "body_zone":  senza proiettore (es. webcam del portatile). Attorno a ogni giocatore c'è
                una zona di gioco misurata sulle sue spalle (quanto arriva comodamente a
                destra, a sinistra e sopra la testa): quella zona diventa tutto lo schermo.
                Si raggiunge ogni angolo con movimenti naturali, a qualsiasi distanza dalla
                camera; la zona segue lentamente i suoi spostamenti.
- "mirror":     tutta l'immagine come uno specchio, con le proporzioni giuste (taglia i
                bordi invece di deformare).
- "stretch":    tutta l'immagine stirata sullo schermo (vecchio comportamento).
- "auto":       "homography" se c'è la calibrazione, altrimenti `uncalibrated`.

Le proporzioni dello schermo arrivano da Godot (messaggio "session", campo "screen"),
quelle della camera dai frame. Nuove modalità: classe + @PROJECTIONS.register."""
from __future__ import annotations

import json
import logging
import math
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .config import TRACKER_DIR
from .registry import Registry
from .structs import FrameResult, Person

log = logging.getLogger(__name__)

DEFAULT_SCREEN_ASPECT = 16 / 9
DEFAULT_CAMERA_ASPECT = 4 / 3


class Projection(ABC):
    space: str = "screen"  # valore del campo "space" del protocollo

    def __init__(self) -> None:
        self.camera_aspect = DEFAULT_CAMERA_ASPECT
        self.screen_aspect = DEFAULT_SCREEN_ASPECT

    @abstractmethod
    def project(self, x: float, y: float) -> tuple[float, float]:
        """Mappatura globale (uguale per tutti: usata anche per l'identità)."""

    def for_person(self, person: Person) -> "Projection":
        """Mappatura da usare per i punti di questa persona (default: la globale)."""
        return self

    def update(self, result: FrameResult) -> None:
        """Chiamata a ogni frame dopo l'identità (per mappature che seguono le persone)."""

    def set_camera_size(self, width: int, height: int) -> None:
        if width > 0 and height > 0:
            self.camera_aspect = width / height

    def set_screen_aspect(self, aspect: float) -> None:
        if aspect > 0:
            self.screen_aspect = aspect

    def zone_of(self, person_id: str) -> tuple[float, float, float, float] | None:
        """Zona di gioco di una persona in coordinate camera (x0, y0, x1, y1), se c'è."""
        return None


PROJECTIONS: Registry[type[Projection]] = Registry("mappatura")


@PROJECTIONS.register("stretch")
class CameraProjection(Projection):
    space = "camera"

    def __init__(self, mirror: bool = True) -> None:
        super().__init__()
        self.mirror = mirror

    def project(self, x: float, y: float) -> tuple[float, float]:
        return (1.0 - x if self.mirror else x), y


@PROJECTIONS.register("mirror")
class MirrorProjection(Projection):
    """Specchio senza deformazioni: l'immagine copre lo schermo e i bordi in più si tagliano."""

    def __init__(self, mirror: bool = True) -> None:
        super().__init__()
        self.mirror = mirror

    def project(self, x: float, y: float) -> tuple[float, float]:
        if self.mirror:
            x = 1.0 - x
        if self.screen_aspect >= self.camera_aspect:  # schermo più largo: si taglia sopra e sotto
            f = self.camera_aspect / self.screen_aspect
            return x, (y - (1.0 - f) / 2.0) / f
        g = self.screen_aspect / self.camera_aspect  # schermo più stretto: si taglia ai lati
        return (x - (1.0 - g) / 2.0) / g, y


@dataclass
class _Zone:
    cx: float  # centro orizzontale, in altezze dell'immagine, già specchiato
    top: float  # bordo alto, in altezze dell'immagine
    width: float  # in altezze dell'immagine
    t: float  # ultimo aggiornamento


@PROJECTIONS.register("body_zone")
class BodyZoneProjection(MirrorProjection):
    """Zona di gioco attorno alle spalle di ogni giocatore → tutto lo schermo.
    Larghezza = width_sw × larghezza spalle; altezza dalle proporzioni dello schermo;
    il bordo alto è top_sw larghezze spalle sopra le spalle. Senza spalle: specchio."""

    def __init__(self, mirror: bool = True, width_sw: float = 3.2, top_sw: float = 1.1,
                 smoothing: float = 1.0, forget_after: float = 2.0) -> None:
        super().__init__(mirror)
        self.width_sw = width_sw
        self.top_sw = top_sw
        self.smoothing = smoothing  # secondi: quanto lentamente la zona segue la persona
        self.forget_after = forget_after
        self.zones: dict[str, _Zone] = {}

    def _u(self, x: float) -> float:
        """x normalizzata della camera → orizzontale in altezze dell'immagine, specchiata."""
        return ((1.0 - x) if self.mirror else x) * self.camera_aspect

    def update(self, result: FrameResult) -> None:
        t = result.frame.t
        for person in result.persons:
            if person.id is None:
                continue
            sl, sr = person.points.get("shoulder_l"), person.points.get("shoulder_r")
            if sl is None or sr is None:
                continue
            ul, ur = self._u(sl.x), self._u(sr.x)
            sw = math.hypot(ul - ur, sl.y - sr.y)
            if sw <= 1e-4:
                continue
            width = min(max(self.width_sw * sw, 0.25), 3.0 * self.camera_aspect)
            target = _Zone((ul + ur) / 2.0, (sl.y + sr.y) / 2.0 - self.top_sw * sw, width, t)
            z = self.zones.get(person.id)
            if z is None or t - z.t > self.forget_after:
                self.zones[person.id] = target
                continue
            a = 1.0 - math.exp(-max(t - z.t, 0.0) / self.smoothing) if self.smoothing > 0 else 1.0
            z.cx += (target.cx - z.cx) * a
            z.top += (target.top - z.top) * a
            z.width += (target.width - z.width) * a
            z.t = t
        for pid in [p for p, z in self.zones.items() if t - z.t > self.forget_after]:
            del self.zones[pid]

    def for_person(self, person: Person) -> Projection:
        z = self.zones.get(person.id or "")
        return self if z is None else _ZoneMapper(self, z)

    def zone_of(self, person_id: str) -> tuple[float, float, float, float] | None:
        z = self.zones.get(person_id)
        if z is None:
            return None
        h = z.width / self.screen_aspect
        u0, u1 = z.cx - z.width / 2.0, z.cx + z.width / 2.0
        x0, x1 = u0 / self.camera_aspect, u1 / self.camera_aspect
        if self.mirror:
            x0, x1 = 1.0 - x1, 1.0 - x0
        return x0, z.top, x1, z.top + h


class _ZoneMapper(Projection):
    """Mappatura di una persona: la sua zona → tutto lo schermo."""

    def __init__(self, parent: BodyZoneProjection, zone: _Zone) -> None:
        super().__init__()
        self.parent = parent
        self.zone = zone

    def project(self, x: float, y: float) -> tuple[float, float]:
        z = self.zone
        h = z.width / self.parent.screen_aspect
        return (self.parent._u(x) - (z.cx - z.width / 2.0)) / z.width, (y - z.top) / h


@PROJECTIONS.register("homography")
class HomographyProjection(Projection):
    def __init__(self, matrix: np.ndarray) -> None:
        super().__init__()
        self.matrix = np.asarray(matrix, dtype=np.float64).reshape(3, 3)

    def project(self, x: float, y: float) -> tuple[float, float]:
        v = self.matrix @ np.array([x, y, 1.0])
        if abs(v[2]) < 1e-12:
            return x, y
        return float(v[0] / v[2]), float(v[1] / v[2])

    def save(self, path: Path, extra: dict[str, Any] | None = None) -> None:
        data = {"homography": self.matrix.tolist(), **(extra or {})}
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def _calibration_path(cfg: dict[str, Any]) -> Path:
    path = Path(cfg.get("calibration_file", "calibration.json"))
    return path if path.is_absolute() else TRACKER_DIR / path


def load_projection(cfg: dict[str, Any]) -> Projection:
    """Crea la mappatura da config. Senza "mode" vale il vecchio comportamento
    (calibrazione se c'è, altrimenti "stretch")."""
    mode = cfg.get("mode", "auto")
    mirror = bool(cfg.get("mirror", True))
    path = _calibration_path(cfg)
    if mode == "auto":
        mode = "homography" if path.exists() else cfg.get("uncalibrated", "stretch")
    if mode == "homography":
        if not path.exists():
            raise FileNotFoundError(f"mappatura 'homography' senza calibrazione: manca {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        log.info("mappatura: proiettore calibrato (%s)", path)
        return HomographyProjection(np.array(data["homography"]))
    cls = PROJECTIONS.get(mode)
    if cls is BodyZoneProjection:
        bz = cfg.get("body_zone", {})
        log.info("mappatura: zona di gioco attorno al corpo")
        return BodyZoneProjection(mirror, float(bz.get("width_sw", 3.2)), float(bz.get("top_sw", 1.1)),
                                  float(bz.get("smoothing", 1.0)))
    log.info("mappatura: %s%s", mode, " (specchiata)" if mirror else "")
    return cls(mirror)
