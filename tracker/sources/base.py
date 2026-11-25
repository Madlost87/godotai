"""Interfaccia comune delle sorgenti (camera, video, LiDAR, ...)."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from ..registry import Registry
from ..structs import Frame


class FrameSource(ABC):
    """Una sorgente produce Frame. `produces` dice che tipo di dato c'è in Frame.data
    ("image" = array BGR di OpenCV; un LiDAR potrebbe produrre "scan2d", una camera di
    profondità "depth"...). La pipeline controlla che i rilevatori lo accettino."""

    produces: str = "image"

    def __init__(self, params: dict[str, Any]) -> None:
        self.params = params

    @abstractmethod
    def read(self) -> Frame | None:
        """Prossimo frame (bloccante). None = sorgente finita."""

    def close(self) -> None:
        pass


SOURCES: Registry[type[FrameSource]] = Registry("sorgente")
