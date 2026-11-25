"""Rilevatori. Ogni modulo di questo pacchetto si registra in DETECTORS quando viene
importato, e vengono importati tutti in automatico: nuovo rilevatore = nuovo file qui,
poi lo si attiva da config.json → "detectors"."""
import sys

from ..plugins import load_plugins
from .base import DETECTORS, Detector  # noqa: F401

load_plugins(sys.modules[__name__])
