"""Proiezione camera → schermo. Senza calibrazione: coordinate camera (eventualmente
specchiate). Con calibrazione (fase 3): omografia salvata in calibration.json."""
from __future__ import annotations

import json
import logging
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import numpy as np

from .config import TRACKER_DIR

log = logging.getLogger(__name__)


class Projection(ABC):
    space: str  # valore del campo "space" del protocollo

    @abstractmethod
    def project(self, x: float, y: float) -> tuple[float, float]: ...


class CameraProjection(Projection):
    space = "camera"

    def __init__(self, mirror: bool = True) -> None:
        self.mirror = mirror

    def project(self, x: float, y: float) -> tuple[float, float]:
        return (1.0 - x if self.mirror else x), y


class HomographyProjection(Projection):
    space = "screen"

    def __init__(self, matrix: np.ndarray) -> None:
        self.matrix = np.asarray(matrix, dtype=np.float64).reshape(3, 3)

    def project(self, x: float, y: float) -> tuple[float, float]:
        v = self.matrix @ np.array([x, y, 1.0])
        if abs(v[2]) < 1e-12:
            return x, y
        return float(v[0] / v[2]), float(v[1] / v[2])

    def save(self, path: Path, extra: dict[str, Any] | None = None) -> None:
        data = {"homography": self.matrix.tolist(), **(extra or {})}
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_projection(cfg: dict[str, Any]) -> Projection:
    path = Path(cfg.get("calibration_file", "calibration.json"))
    if not path.is_absolute():
        path = TRACKER_DIR / path
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        log.info("calibrazione caricata da %s", path)
        return HomographyProjection(np.array(data["homography"]))
    log.info("nessuna calibrazione: coordinate camera%s", " specchiate" if cfg.get("mirror", True) else "")
    return CameraProjection(bool(cfg.get("mirror", True)))
