"""Protocollo tracker → Godot, versione 1 (SPEC §5). Unico punto che conosce il formato."""
from __future__ import annotations

import json
from typing import Any

from .projection import Projection
from .structs import FrameResult, Point

PROTOCOL_VERSION = 1
MAX_PACKET_BYTES = 8192


def build_packet(
    result: FrameResult, projection: Projection, fps: float, capabilities: list[str] | tuple[str, ...] = ()
) -> dict[str, Any]:
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
        if person.effectors:
            entry["effectors"] = {name: pt(p) for name, p in person.effectors.items()}
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
        "caps": list(capabilities),
        "players": players,
    }


def encode(packet: dict[str, Any]) -> bytes:
    return json.dumps(packet, separators=(",", ":")).encode("utf-8")


KNOWN_CAPABILITIES = {"pose", "hands", "face", "markers", "effectors"}


def validate_packet(packet: Any) -> list[str]:
    """Controlla un pacchetto v1 e restituisce l'elenco dei problemi (vuoto = valido).
    È il contratto che ogni sensore/tracker deve rispettare per parlare con Godot."""
    errs: list[str] = []

    def is_num(v: Any) -> bool:
        return isinstance(v, (int, float)) and not isinstance(v, bool)

    def check_point(where: str, v: Any) -> None:
        if not (isinstance(v, list) and len(v) in (2, 3) and all(is_num(x) for x in v)):
            errs.append(f"{where}: atteso [x, y] o [x, y, conf]")

    if not isinstance(packet, dict):
        return ["il pacchetto non è un oggetto JSON"]
    if packet.get("v") != PROTOCOL_VERSION:
        errs.append(f"v deve essere {PROTOCOL_VERSION}")
    if packet.get("space", "camera") not in ("camera", "screen"):
        errs.append("space deve essere 'camera' o 'screen'")
    caps = packet.get("caps", [])
    if not isinstance(caps, list) or any(c not in KNOWN_CAPABILITIES for c in caps):
        errs.append(f"caps deve essere una lista di {sorted(KNOWN_CAPABILITIES)}")
    players = packet.get("players")
    if not isinstance(players, list):
        return errs + ["players deve essere una lista"]
    ids = set()
    for i, pl in enumerate(players):
        w = f"players[{i}]"
        if not isinstance(pl, dict) or not isinstance(pl.get("id"), str) or not pl["id"]:
            errs.append(f"{w}: serve un 'id' stringa")
            continue
        if pl["id"] in ids:
            errs.append(f"{w}: id '{pl['id']}' ripetuto")
        ids.add(pl["id"])
        for group in ("pose", "effectors"):
            for name, v in (pl.get(group) or {}).items():
                check_point(f"{w}.{group}.{name}", v)
        for side, hand in (pl.get("hands") or {}).items():
            if side not in ("l", "r"):
                errs.append(f"{w}.hands: lato '{side}' non valido")
            for name, v in hand.items():
                if isinstance(v, list):
                    check_point(f"{w}.hands.{side}.{name}", v)
                elif not is_num(v):
                    errs.append(f"{w}.hands.{side}.{name}: atteso punto o numero")
        for group in ("marker", "face"):
            g = pl.get(group)
            if g is not None and not (isinstance(g, dict) and is_num(g.get("x")) and is_num(g.get("y"))):
                errs.append(f"{w}.{group}: servono x e y numerici")
    return errs
