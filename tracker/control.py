"""Canale di controllo Godot → tracker (UDP JSON, di default 127.0.0.1:4243).

Ogni messaggio è un oggetto JSON con un campo "type". Oggi:
- "calibration_layout": posizione dei marker ArUco proiettati (vedi calibration.py).
In futuro lo stesso canale potrà servire, per esempio, perché un gioco dica al tracker
quali rilevatori attivare."""
from __future__ import annotations

import json
import logging
import socket
from typing import Any

log = logging.getLogger(__name__)


class ControlChannel:
    def __init__(self, host: str = "127.0.0.1", port: int = 4243) -> None:
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self._sock.bind((host, port))
        except OSError as e:
            self._sock.close()
            raise RuntimeError(f"porta di controllo {host}:{port} occupata (un altro tracker è aperto?)") from e
        self._sock.setblocking(False)
        self.port = self._sock.getsockname()[1]

    def poll(self) -> list[dict[str, Any]]:
        """Messaggi validi arrivati dall'ultima chiamata (non bloccante)."""
        out: list[dict[str, Any]] = []
        while True:
            try:
                data = self._sock.recv(65536)
            except (BlockingIOError, InterruptedError):
                break
            try:
                msg = json.loads(data.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                log.debug("messaggio di controllo non valido ignorato")
                continue
            if isinstance(msg, dict) and isinstance(msg.get("type"), str):
                out.append(msg)
        return out

    def close(self) -> None:
        self._sock.close()
