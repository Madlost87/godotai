"""Configurazione: valori di default + config.json (unione profonda) + override da riga di comando."""
from __future__ import annotations

import copy
import json
import logging
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

TRACKER_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG_PATH = TRACKER_DIR / "config.json"

DEFAULTS: dict[str, Any] = {
    "source": {
        "type": "camera",  # "camera" | "video"
        "device": "auto",  # "auto" = primo nodo /dev/video* che dà immagini
        "path": "",  # per "video"
        "loop": False,  # per "video"
        # 16:9: stessa altezza del 4:3 ma il 31% in più in larghezza, stesso costo di
        # MediaPipe (misurato: 30 fps, ~14 ms per frame anche a 1280×720)
        "width": 1280,
        "height": 720,
        "fps": 30,
        "fourcc": "MJPG",
        "buffers": 2,  # buffer del driver: 1 fa perdere frame
        "controls": {},  # controlli v4l2-ctl, es. {"auto_exposure": 1, "exposure_time_absolute": 200}
    },
    # Ordine = ordine di esecuzione. Solo quelli con "enabled": true vengono creati.
    "detectors": {
        "pose": {
            "enabled": True,
            "model": "full",  # "lite" | "full" | "heavy"
            "num_poses": 2,
            "min_detection_confidence": 0.5,
            "min_presence_confidence": 0.5,
            "min_tracking_confidence": 0.5,
            # sotto questa soglia il punto è scartato; tra questa e stabilizer.show_conf
            # decide lo stabilizzatore (isteresi), così i polsi incerti non lampeggiano
            "min_visibility": 0.15,
            "margin": 0.05,  # punti oltre questo margine fuori dall'immagine scartati
        },
    },
    "identity": {
        "mode": "markerless",  # "markerless" | "markers" | "mixed" (gli ultimi due: fase 5)
        "assign": "zones",  # "zones" | "arrival"
        "max_players": 2,
        "max_distance": 0.15,
        "hold_time": 0.5,
    },
    # Dopo l'identità, per ogni sensore: niente punti che lampeggiano o saltano (§10.2).
    "stabilizer": {
        "enabled": True,
        "show_conf": 0.5,  # un punto compare solo con affidabilità ≥ show_conf...
        "hide_conf": 0.25,  # ...e scompare solo sotto hide_conf
        "hold_time": 0.25,  # secondi: un punto che manca resta dov'era
        "max_jump": 0.25,  # salto in un frame (altezze immagine) ignorato se isolato
    },
    "projection": {
        # "auto" = proiettore calibrato se c'è calibration.json, altrimenti `uncalibrated`.
        # Modalità: homography, body_zone, mirror, stretch (vedi projection.py).
        "mode": "auto",
        "uncalibrated": "body_zone",
        "mirror": True,  # camera rivolta ai giocatori: immagine a specchio
        "calibration_file": "calibration.json",
        "body_zone": {
            "width_sw": 3.2,  # larghezza della zona, in larghezze delle spalle
            "top_sw": 1.1,  # bordo alto: quante larghezze spalle sopra le spalle
            "smoothing": 1.0,  # secondi: quanto lentamente la zona segue la persona
        },
    },
    "outputs": [
        {"type": "udp", "host": "127.0.0.1", "port": 4242},
    ],
    # Canale Godot → tracker (layout di calibrazione, in futuro altri comandi).
    "control": {"host": "127.0.0.1", "port": 4243},
    "calibration": {
        "method": "aruco",  # plugin in calibration.CALIBRATION_METHODS
        "frames_needed": 15,  # frame consecutivi con tutti i 4 marker visibili
        "max_error": 0.02,  # errore RMS massimo accettato (frazione dello schermo)
    },
}


def deep_merge(base: dict[str, Any], override: dict[str, Any], path: str = "") -> dict[str, Any]:
    """Unisce `override` su una copia di `base`. Avvisa per chiavi sconosciute
    (tranne dentro dizionari liberi come detectors e controls)."""
    out = copy.deepcopy(base)
    for key, value in override.items():
        here = f"{path}.{key}" if path else key
        if key not in out:
            if path not in ("detectors", "source.controls") and not path.startswith("detectors."):
                log.warning("config: chiave sconosciuta '%s'", here)
            out[key] = copy.deepcopy(value)
        elif isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = deep_merge(out[key], value, here)
        else:
            out[key] = copy.deepcopy(value)
    return out


def load_config(path: Path | None = None) -> dict[str, Any]:
    path = path or DEFAULT_CONFIG_PATH
    user: dict[str, Any] = {}
    if path.exists():
        with path.open(encoding="utf-8") as f:
            user = json.load(f)
    elif path != DEFAULT_CONFIG_PATH:
        raise FileNotFoundError(path)
    cfg = deep_merge(DEFAULTS, user)
    validate(cfg)
    return cfg


def validate(cfg: dict[str, Any]) -> None:
    ident = cfg["identity"]
    if ident["mode"] not in ("markerless", "markers", "mixed"):
        raise ValueError(f"identity.mode non valido: {ident['mode']}")
    if not 1 <= int(ident["max_players"]) <= 8:
        raise ValueError("identity.max_players deve stare tra 1 e 8")
    if not isinstance(cfg["outputs"], list):
        raise ValueError("outputs deve essere una lista")
