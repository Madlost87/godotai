"""Identità dei giocatori (SPEC §5): id stabili tra i frame e regola di assegnazione.

- PersonTracker aggancia ogni persona a quella del frame precedente più vicina.
- Un Assigner decide l'id di chi compare per la prima volta ("zones", "arrival"...).
- IdentityResolver mette insieme i pezzi secondo identity.mode.
Le distanze e le zone sono calcolate nello spazio dello schermo (dopo la proiezione)."""
from __future__ import annotations

import math
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

from .projection import Projection
from .registry import Registry
from .structs import FrameResult, Person


class Assigner(ABC):
    def __init__(self, max_players: int) -> None:
        self.max_players = max_players

    def ids(self) -> list[str]:
        return [f"p{i + 1}" for i in range(self.max_players)]

    @abstractmethod
    def assign(self, ref: tuple[float, float], taken: set[str]) -> str | None:
        """Id per una persona nuova in posizione `ref`; None se non c'è posto."""


ASSIGNERS: Registry[type[Assigner]] = Registry("regola di assegnazione")


@ASSIGNERS.register("arrival")
class ArrivalAssigner(Assigner):
    def assign(self, ref: tuple[float, float], taken: set[str]) -> str | None:
        return next((i for i in self.ids() if i not in taken), None)


@ASSIGNERS.register("zones")
class ZonesAssigner(Assigner):
    """Schermo diviso in fasce verticali: p1 a sinistra, p2 a destra..."""

    def assign(self, ref: tuple[float, float], taken: set[str]) -> str | None:
        zone = min(max(int(ref[0] * self.max_players), 0), self.max_players - 1)
        preferred = f"p{zone + 1}"
        if preferred not in taken:
            return preferred
        return next((i for i in self.ids() if i not in taken), None)


@dataclass
class Track:
    id: str
    ref: tuple[float, float]
    last_seen: float
    vel: tuple[float, float] = (0.0, 0.0)  # unità normalizzate al secondo

    VEL_SMOOTHING = 0.5

    def predict(self, t: float, horizon: float) -> tuple[float, float]:
        """Posizione prevista al tempo t (velocità costante, al massimo per `horizon` s)."""
        dt = min(max(t - self.last_seen, 0.0), horizon)
        return self.ref[0] + self.vel[0] * dt, self.ref[1] + self.vel[1] * dt

    def observe(self, ref: tuple[float, float], t: float) -> None:
        dt = t - self.last_seen
        if dt > 0:
            a = self.VEL_SMOOTHING
            inst = ((ref[0] - self.ref[0]) / dt, (ref[1] - self.ref[1]) / dt)
            self.vel = (self.vel[0] * (1 - a) + inst[0] * a, self.vel[1] * (1 - a) + inst[1] * a)
        self.ref = ref
        self.last_seen = t


class PersonTracker:
    """Aggancia le persone di un frame alle tracce del precedente. Il confronto usa la
    posizione *prevista* di ogni traccia (velocità costante), così due persone che si
    incrociano non si scambiano l'id."""

    def __init__(self, assigner: Assigner, max_distance: float = 0.15, hold_time: float = 0.5) -> None:
        self.assigner = assigner
        self.max_distance = max_distance
        self.hold_time = hold_time
        self.tracks: dict[str, Track] = {}

    def update(self, persons: list[Person], refs: list[tuple[float, float] | None], t: float) -> None:
        """Imposta person.id per ogni persona (None se senza riferimento o senza posto)."""
        for p in persons:
            p.id = None
        # Accoppiamento greedy per distanza crescente con le tracce esistenti.
        predicted = {tid: track.predict(t, self.hold_time) for tid, track in self.tracks.items()}
        pairs = sorted(
            (math.dist(predicted[tid], ref), tid, i)
            for tid in self.tracks
            for i, ref in enumerate(refs)
            if ref is not None
        )
        used_tracks: set[str] = set()
        for dist, tid, i in pairs:
            if dist > self.max_distance:
                break
            if tid in used_tracks or persons[i].id is not None:
                continue
            persons[i].id = tid
            used_tracks.add(tid)
        # Persone nuove: le tracce in attesa occupano ancora il loro id.
        for i, p in enumerate(persons):
            ref = refs[i]
            if p.id is None and ref is not None:
                p.id = self.assigner.assign(ref, set(self.tracks))
                if p.id is not None:
                    self.tracks[p.id] = Track(p.id, ref, t)
        for i, p in enumerate(persons):
            ref = refs[i]
            if p.id is not None and ref is not None:
                self.tracks[p.id].observe(ref, t)
        for tid in [tid for tid, tr in self.tracks.items() if t - tr.last_seen > self.hold_time]:
            del self.tracks[tid]


class IdentityResolver:
    def __init__(self, cfg: dict[str, Any], projection: Projection) -> None:
        self.mode = cfg.get("mode", "markerless")
        if self.mode != "markerless":
            raise NotImplementedError(f"identity.mode '{self.mode}' arriva con i marker colorati (fase 5)")
        self._assigner_cls = ASSIGNERS.get(cfg.get("assign", "zones"))
        self.tracker = PersonTracker(
            self._assigner_cls(int(cfg.get("max_players", 2))),
            float(cfg.get("max_distance", 0.15)),
            float(cfg.get("hold_time", 0.5)),
        )
        self.projection = projection

    @property
    def max_players(self) -> int:
        return self.tracker.assigner.max_players

    def set_max_players(self, n: int) -> None:
        """Cambia il numero di giocatori a caldo (es. su richiesta del gioco).
        Le tracce con id oltre il nuovo limite vengono scartate."""
        self.tracker.assigner = self._assigner_cls(n)
        allowed = set(self.tracker.assigner.ids())
        for tid in [tid for tid in self.tracker.tracks if tid not in allowed]:
            del self.tracker.tracks[tid]

    def resolve(self, result: FrameResult) -> None:
        refs: list[tuple[float, float] | None] = []
        for p in result.persons:
            r = p.reference()
            refs.append(self.projection.project(r.x, r.y) if r else None)
        self.tracker.update(result.persons, refs, result.frame.t)
