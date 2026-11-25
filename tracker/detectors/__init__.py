"""Rilevatori. Ogni modulo si registra in DETECTORS; aggiungerne uno qui sotto lo rende
attivabile da config.json → "detectors"."""
from .base import DETECTORS, Detector  # noqa: F401
from . import pose  # noqa: F401  (registra "pose")
