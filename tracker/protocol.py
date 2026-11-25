"""Protocollo tracker → Godot, versione 1 (SPEC §5). Unico punto che conosce il formato."""
from __future__ import annotations

import json
from typing import Any

from .projection import Projection
from .structs import FrameResult, Point

PROTOCOL_VERSION = 1
MAX_PACKET_BYTES = 8192


def build_packet(result: FrameResult, projection: Projection, fps: float) -> dict[str, Any]:
    def pt(p: Point) -> list[float]:
        x, y = projection.project(p.x, p.y)
        return [round(x, 4), round(y, 4), round(p.conf, 3)]

    players: list[dict[str, Any]] = []
    for person in result.players():
        entry: dict[str, Any] = {"id": person.id}
        if person.marker is not None:
            mx, my = projection.project(person.marker.x, person.marker.y)
            entry["marker"] = {"x": round(mx, 4), "y": round(my, 4), "area": round(person.marker.area, 5)}
        if person.points:
            entry["pose"] = {name: pt(p) for name, p in person.points.items()}
        if person.hands:
            hands: dict[str, Any] = {}
            for side, hand in person.hands.items():
                h: dict[str, Any] = {name: pt(p) for name, p in hand.points.items()}
                h.update({k: round(v, 3) for k, v in hand.values.items()})
                hands[side] = h
            entry["hands"] = hands
        if person.face is not None:
            fx, fy = projection.project(person.face.center.x, person.face.center.y)
            face: dict[str, Any] = {"x": round(fx, 4), "y": round(fy, 4)}
            face.update({k: round(v, 3) for k, v in person.face.values.items()})
            entry["face"] = face
        players.append(entry)
    return {
        "v": PROTOCOL_VERSION,
        "t": round(result.frame.t, 4),
        "space": projection.space,
        "fps": round(fps, 1),
        "players": players,
    }


def encode(packet: dict[str, Any]) -> bytes:
    return json.dumps(packet, separators=(",", ":")).encode("utf-8")
