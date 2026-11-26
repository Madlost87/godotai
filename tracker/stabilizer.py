"""Stabilizzatore dei punti: stadio della pipeline dopo l'identità, uguale per ogni sensore.

Il problema misurato (registrazione reale, docs/SPEC.md §10.2): il tremolio dei punti è
piccolo, ma i punti incerti (polsi vicino al bordo dell'immagine) **compaiono e scompaiono**
più volte al secondo, perché la loro affidabilità oscilla attorno alla soglia. In gioco
la mano sparisce e ricompare: scatti. Qui, per ogni giocatore e ogni punto:

1. isteresi: un punto compare se conf ≥ show_conf e scompare solo se conf < hide_conf;
2. tenuta: se il punto non arriva, resta dov'era per hold_time secondi (affidabilità
   dimezzata), poi sparisce;
3. salti impossibili: uno spostamento > max_jump (in altezze dell'immagine) in un frame
   viene ignorato, a meno che si ripeta al frame dopo (allora era vero).
Il filtro anti-tremolio resta in Godot (PlayerState), per tutti i sensori.
Configurazione: sezione "stabilizer" di config.py."""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from .structs import FrameResult, Point


@dataclass
class _PointState:
    point: Point
    t: float  # ultima volta che è arrivato davvero
    shown: bool = True
    pending: Point | None = None  # candidato a un salto, in attesa di conferma


@dataclass
class _PersonState:
    points: dict[str, _PointState] = field(default_factory=dict)
    effectors: dict[str, _PointState] = field(default_factory=dict)
    t: float = 0.0


class Stabilizer:
    def __init__(self, params: dict[str, Any] | None = None) -> None:
        p = params or {}
        self.enabled = bool(p.get("enabled", True))
        self.show_conf = float(p.get("show_conf", 0.5))
        self.hide_conf = float(p.get("hide_conf", 0.25))
        self.hold_time = float(p.get("hold_time", 0.25))
        self.max_jump = float(p.get("max_jump", 0.25))
        self.forget_after = float(p.get("forget_after", 2.0))
        self.aspect = 4 / 3  # per misurare i salti in unità uguali in x e y
        self._people: dict[str, _PersonState] = {}

    def set_camera_size(self, width: int, height: int) -> None:
        if width > 0 and height > 0:
            self.aspect = width / height

    def process(self, result: FrameResult) -> None:
        if not self.enabled:
            return
        t = result.frame.t
        result.raw = {}
        for person in result.persons:
            if person.id is None:
                continue
            result.raw[person.id] = dict(person.points)
            st = self._people.setdefault(person.id, _PersonState())
            st.t = t
            person.points = self._stabilize(person.points, st.points, t)
            person.effectors = self._stabilize(person.effectors, st.effectors, t)
        for pid in [pid for pid, s in self._people.items() if t - s.t > self.forget_after]:
            del self._people[pid]

    def _stabilize(self, incoming: dict[str, Point], states: dict[str, _PointState], t: float) -> dict[str, Point]:
        out: dict[str, Point] = {}
        for name, p in incoming.items():
            s = states.get(name)
            if s is None:
                if p.conf >= self.show_conf:
                    states[name] = _PointState(p, t)
                    out[name] = p
                continue
            if not s.shown:  # nascosto: torna solo se abbastanza sicuro
                if p.conf >= self.show_conf:
                    states[name] = _PointState(p, t)
                    out[name] = p
                continue
            if p.conf < self.hide_conf:  # troppo incerto: come se non fosse arrivato
                continue
            if self._dist(p, s.point) > self.max_jump:
                if s.pending is not None and self._dist(p, s.pending) <= self.max_jump:
                    s.point, s.t, s.pending = p, t, None  # il salto si è ripetuto: è vero
                    out[name] = p
                else:
                    s.pending = p  # salto isolato: aspetta conferma, intanto resta dov'era
                    out[name] = Point(s.point.x, s.point.y, s.point.conf)
                continue
            s.point, s.t, s.pending = p, t, None
            out[name] = p
        # punti non arrivati (o troppo incerti): tenuti per hold_time
        for name, s in states.items():
            if name in out or not s.shown:
                continue
            if t - s.t <= self.hold_time:
                out[name] = Point(s.point.x, s.point.y, s.point.conf * 0.5)
            else:
                s.shown = False
        return out

    def _dist(self, a: Point, b: Point) -> float:
        return math.hypot((a.x - b.x) * self.aspect, a.y - b.y)
