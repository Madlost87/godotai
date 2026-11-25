"""Sorgenti di dati. Ogni modulo di questo pacchetto si registra in SOURCES quando
viene importato, e vengono importati tutti in automatico.
Nuovo sensore = nuovo file qui (vedi docs/GUIDA_NUOVO_SENSORE.md)."""
import sys

from ..plugins import load_plugins
from .base import SOURCES, FrameSource  # noqa: F401

load_plugins(sys.modules[__name__])
