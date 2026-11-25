"""Interfaccia comune dei rilevatori."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from ..registry import Registry
from ..structs import Frame, FrameResult


class Detector(ABC):
    """Un rilevatore legge il frame e arricchisce `result`: aggiunge persone (pose),
    o completa quelle esistenti (mani, faccia), o aggiunge marker (colori).
    I rilevatori girano nell'ordine di config.json."""

    def __init__(self, params: dict[str, Any]) -> None:
        self.params = params

    @abstractmethod
    def process(self, frame: Frame, result: FrameResult) -> None: ...

    def apply_session(self, session: dict[str, Any]) -> None:
        """Il gioco ha chiesto una nuova sessione (es. {"max_players": 1}): adattati se serve."""

    def close(self) -> None:
        pass


DETECTORS: Registry[type[Detector]] = Registry("rilevatore")
