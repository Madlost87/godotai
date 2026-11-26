"""Uscite dei pacchetti. Oggi UDP verso Godot; domani altre (file, WebSocket, OSC...)
si aggiungono registrando una nuova classe."""
from __future__ import annotations

import json
import logging
import socket
from abc import ABC, abstractmethod
from typing import Any

from .protocol import MAX_PACKET_BYTES, encode
from .registry import Registry

log = logging.getLogger(__name__)


class Sink(ABC):
    def __init__(self, params: dict[str, Any]) -> None:
        self.params = params

    @abstractmethod
    def send(self, packet: dict[str, Any]) -> None: ...

    def close(self) -> None:
        pass


SINKS: Registry[type[Sink]] = Registry("uscita")


@SINKS.register("udp")
class UdpSink(Sink):
    def __init__(self, params: dict[str, Any]) -> None:
        super().__init__(params)
        self.addr = (str(params.get("host", "127.0.0.1")), int(params.get("port", 4242)))
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._warned = False

    def send(self, packet: dict[str, Any]) -> None:
        data = encode(packet)
        if len(data) > MAX_PACKET_BYTES and not self._warned:
            log.warning("pacchetto di %d byte oltre il limite di %d", len(data), MAX_PACKET_BYTES)
            self._warned = True
        try:
            self._sock.sendto(data, self.addr)
        except OSError as e:  # Godot non in ascolto ecc.: non deve fermare il tracker
            log.debug("invio UDP fallito: %s", e)

    def close(self) -> None:
        self._sock.close()


@SINKS.register("jsonl")
class JsonlSink(Sink):
    """Registra ogni frame su file (una riga JSON): i punti grezzi del sensore (coordinate
    camera, prima di stabilizzatore, filtri e mappatura) e il pacchetto mandato al gioco. Serve per
    analizzare tremolio, scatti e ritardi (`./tracker.sh --record file.jsonl`)."""

    def __init__(self, params: dict[str, Any]) -> None:
        super().__init__(params)
        from pathlib import Path

        self.path = Path(str(params.get("path", "registrazione.jsonl")))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._f = self.path.open("w", encoding="utf-8")

    def send(self, packet: dict[str, Any]) -> None:
        self._f.write(json.dumps({"packet": packet}, separators=(",", ":")) + "\n")

    def send_frame(self, result: Any, packet: dict[str, Any]) -> None:
        def pts(person: Any) -> dict[str, Any]:
            src = person.points if result.raw is None else result.raw.get(person.id or "", person.points)
            return {n: [round(pt.x, 5), round(pt.y, 5), round(pt.conf, 3)] for n, pt in src.items()}

        raw = [{"id": p.id, "points": pts(p)} for p in result.persons]
        row: dict[str, Any] = {"t": round(result.frame.t, 4), "raw": raw, "packet": packet}
        if result.frame.kind == "image":
            row["camera"] = list(result.frame.size)
        self._f.write(json.dumps(row,
                                 separators=(",", ":")) + "\n")

    def close(self) -> None:
        self._f.close()
