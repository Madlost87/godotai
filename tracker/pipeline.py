"""Assemblaggio ed esecuzione della pipeline:
sorgente → rilevatori → identità → stabilizzatore → mappatura → protocollo → uscite."""
from __future__ import annotations

import logging
import time
from typing import Any, Callable

from .sources import SOURCES, FrameSource
from .control import ControlChannel
from .detectors import DETECTORS, Detector
from .identity import IdentityResolver
from .projection import Projection, load_projection
from .protocol import build_packet
from .sinks import SINKS, Sink
from .stabilizer import Stabilizer
from .structs import FrameResult

log = logging.getLogger(__name__)

# Chiamata dopo ogni frame; restituire False ferma la pipeline.
ResultCallback = Callable[[FrameResult, dict[str, Any]], bool | None]


class Pipeline:
    def __init__(
        self,
        source: FrameSource,
        detectors: list[Detector],
        projection: Projection,
        identity: IdentityResolver,
        sinks: list[Sink],
        control: ControlChannel | None = None,
        stabilizer: Stabilizer | None = None,
    ) -> None:
        self.source = source
        self.detectors = detectors
        self.projection = projection
        self.identity = identity
        self.sinks = sinks
        self.control = control
        self.stabilizer = stabilizer
        self.session: dict[str, Any] = {}
        self.fps = 0.0
        self._last_t: float | None = None
        check_compatibility(source, detectors)
        # Capacità annunciate ai giochi (campo "caps" dei pacchetti).
        self.capabilities: list[str] = sorted({c for d in detectors for c in d.provides})

    def apply_session(self, session: dict[str, Any]) -> bool:
        """Richiesta del gioco (messaggio "session" sul canale di controllo), es.
        {"max_players": 1, "screen": [1152, 648]}. Restituisce True se qualcosa è cambiato."""
        changed = False
        scr = session.get("screen")
        if (isinstance(scr, list) and len(scr) == 2 and all(isinstance(v, (int, float)) for v in scr)
                and scr[0] > 0 and scr[1] > 0):
            aspect = float(scr[0]) / float(scr[1])
            if abs(aspect - self.projection.screen_aspect) > 1e-3:
                self.projection.set_screen_aspect(aspect)
                log.info("proporzioni dello schermo dal gioco: %.0f×%.0f (%.2f)", scr[0], scr[1], aspect)
                changed = True
        if "max_players" not in session:
            return changed
        n = session.get("max_players")
        if isinstance(n, float) and n.is_integer():  # da Godot/JSON può arrivare come 1.0
            n = int(n)
        if isinstance(n, bool) or not isinstance(n, int) or not 1 <= n <= 8:
            log.warning("sessione ignorata: max_players non valido (%r)", n)
            return changed
        clean = {"max_players": n}
        if clean == self.session:
            return changed
        self.session = clean
        self.identity.set_max_players(n)
        for det in self.detectors:
            det.apply_session(clean)
        log.info("sessione richiesta dal gioco: %d giocatore/i", n)
        return True

    def step(self) -> tuple[FrameResult, dict[str, Any]] | None:
        if self.control is not None:
            for msg in self.control.poll():
                if msg["type"] == "session":
                    self.apply_session(msg)
        frame = self.source.read()
        if frame is None:
            return None
        result = FrameResult(frame)
        if frame.kind == "image":
            self.projection.set_camera_size(*frame.size)
            if self.stabilizer is not None:
                self.stabilizer.set_camera_size(*frame.size)
        for det in self.detectors:
            t0 = time.perf_counter()
            det.process(frame, result)
            result.timings[type(det).__name__] = (time.perf_counter() - t0) * 1000
        self.identity.resolve(result)
        if self.stabilizer is not None:
            t0 = time.perf_counter()
            self.stabilizer.process(result)  # punti che non lampeggiano né saltano
            result.timings["Stabilizer"] = (time.perf_counter() - t0) * 1000
        self.projection.update(result)  # es. zone di gioco che seguono le persone
        self._update_fps(frame.t)
        packet = build_packet(result, self.projection, self.fps, self.capabilities)
        for sink in self.sinks:
            if hasattr(sink, "send_frame"):
                sink.send_frame(result, packet)  # uscite che vogliono anche i dati grezzi
            else:
                sink.send(packet)
        return result, packet

    def run(self, on_result: ResultCallback | None = None, max_frames: int = 0) -> int:
        n = 0
        while True:
            out = self.step()
            if out is None:
                break
            n += 1
            if on_result is not None and on_result(*out) is False:
                break
            if max_frames and n >= max_frames:
                break
        return n

    def _update_fps(self, t: float) -> None:
        if self._last_t is not None and t > self._last_t:
            inst = 1.0 / (t - self._last_t)
            self.fps = inst if self.fps == 0.0 else self.fps * 0.9 + inst * 0.1
        self._last_t = t

    def close(self) -> None:
        for det in self.detectors:
            det.close()
        for sink in self.sinks:
            sink.close()
        if self.control is not None:
            self.control.close()
        self.source.close()


def check_compatibility(source: Any, detectors: list[Detector]) -> None:
    """Errore chiaro se un rilevatore non sa leggere i dati della sorgente
    (es. la pose di MediaPipe con un LiDAR che produce scansioni)."""
    produces = getattr(source, "produces", "image")
    for det in detectors:
        if "*" not in det.accepts and produces not in det.accepts:
            raise ValueError(
                f"il rilevatore {type(det).__name__} accetta {list(det.accepts)}, "
                f"ma la sorgente {type(source).__name__} produce '{produces}'"
            )


def build_pipeline(cfg: dict[str, Any]) -> Pipeline:
    detectors: list[Detector] = []
    for name, params in cfg["detectors"].items():
        if params.get("enabled", True):
            detectors.append(DETECTORS.get(name)(params))
            log.info("rilevatore attivo: %s", name)
    if not detectors:
        log.warning("nessun rilevatore attivo")
    projection = load_projection(cfg["projection"])
    identity = IdentityResolver(cfg["identity"], projection)
    sinks = [SINKS.get(o.get("type", "udp"))(o) for o in cfg["outputs"]]
    src_cfg = cfg["source"]
    source = SOURCES.get(src_cfg.get("type", "camera"))(src_cfg)
    control: ControlChannel | None = None
    try:
        control = ControlChannel(cfg["control"]["host"], int(cfg["control"]["port"]))
    except RuntimeError as e:
        log.warning("canale di controllo non disponibile: %s", e)
    stabilizer = Stabilizer(cfg.get("stabilizer", {}))
    return Pipeline(source, detectors, projection, identity, sinks, control, stabilizer)
