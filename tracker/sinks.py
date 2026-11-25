"""Uscite dei pacchetti. Oggi UDP verso Godot; domani altre (file, WebSocket, OSC...)
si aggiungono registrando una nuova classe."""
from __future__ import annotations

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
