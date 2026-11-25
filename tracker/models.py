"""Modelli MediaPipe (.task): scaricati alla prima richiesta in tracker/models/."""
from __future__ import annotations

import logging
import urllib.request
from pathlib import Path

log = logging.getLogger(__name__)

MODELS_DIR = Path(__file__).resolve().parent / "models"

URLS: dict[str, str] = {
    f"pose_landmarker_{v}": (
        f"https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        f"pose_landmarker_{v}/float16/1/pose_landmarker_{v}.task"
    )
    for v in ("lite", "full", "heavy")
}


def ensure_model(name: str) -> Path:
    if name not in URLS:
        raise ValueError(f"modello sconosciuto '{name}'. Disponibili: {', '.join(sorted(URLS))}")
    path = MODELS_DIR / f"{name}.task"
    if not path.exists():
        MODELS_DIR.mkdir(parents=True, exist_ok=True)
        log.info("scarico il modello %s ...", name)
        tmp = path.with_suffix(".part")
        urllib.request.urlretrieve(URLS[name], tmp)
        tmp.rename(path)
    return path
