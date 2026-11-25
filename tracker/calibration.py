"""Calibrazione camera → schermo (SPEC §7).

Godot proietta 4 marker ArUco (DICT_4X4_50, id 0–3) e manda sul canale di controllo
dove si trovano i loro angoli in coordinate schermo normalizzate. Il tracker li cerca
nell'immagine della camera, accumula alcuni frame in cui li vede tutti, e calcola
l'omografia camera → schermo con i 16 angoli. Il risultato va in calibration.json."""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from .projection import HomographyProjection

log = logging.getLogger(__name__)

MARKER_IDS = (0, 1, 2, 3)

Layout = dict[int, np.ndarray]  # id → (4, 2) angoli normalizzati sullo schermo (TL, TR, BR, BL)


@dataclass
class CalibrationStatus:
    state: str  # "waiting_layout" | "searching" | "collecting" | "done" | "failed"
    found: list[int] = field(default_factory=list)
    progress: float = 0.0
    error: float | None = None
    message: str = ""

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {"state": self.state, "found": self.found, "progress": round(self.progress, 2)}
        if self.error is not None:
            d["error"] = round(self.error, 5)
        if self.message:
            d["message"] = self.message
        return d


def parse_layout(msg: dict[str, Any]) -> Layout:
    """Layout dal messaggio di controllo "calibration_layout"."""
    markers = msg.get("markers")
    if not isinstance(markers, dict):
        raise ValueError("layout senza 'markers'")
    layout: Layout = {}
    for key, corners in markers.items():
        arr = np.asarray(corners, dtype=np.float64)
        if arr.shape != (4, 2):
            raise ValueError(f"marker {key}: servono 4 angoli [x, y]")
        layout[int(key)] = arr
    if set(layout) != set(MARKER_IDS):
        raise ValueError(f"servono i marker {MARKER_IDS}, ricevuti {sorted(layout)}")
    return layout


def solve_homography(cam: np.ndarray, screen: np.ndarray) -> tuple[np.ndarray, float]:
    """Omografia ai minimi quadrati e errore RMS (in unità di schermo normalizzate)."""
    h, _ = cv2.findHomography(cam.reshape(-1, 1, 2), screen.reshape(-1, 1, 2), 0)
    if h is None:
        raise ValueError("omografia non calcolabile (punti degeneri)")
    proj = cv2.perspectiveTransform(cam.reshape(-1, 1, 2), h).reshape(-1, 2)
    err = float(np.sqrt(np.mean(np.sum((proj - screen.reshape(-1, 2)) ** 2, axis=1))))
    return h, err


class Calibrator:
    def __init__(self, frames_needed: int = 15, max_error: float = 0.02) -> None:
        self.frames_needed = frames_needed
        self.max_error = max_error
        self.layout: Layout | None = None
        self.homography: np.ndarray | None = None
        self._samples: list[dict[int, np.ndarray]] = []
        params = cv2.aruco.DetectorParameters()
        params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
        self._detector = cv2.aruco.ArucoDetector(cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50), params)
        self.status = CalibrationStatus("waiting_layout", message="in attesa della scena di calibrazione di Godot")
        self.last_detection: tuple[Any, Any] = ((), None)

    def set_layout(self, layout: Layout) -> None:
        if self.layout is not None and all(np.allclose(layout[i], self.layout[i]) for i in MARKER_IDS):
            return
        self.layout = layout
        self._samples.clear()
        self.homography = None
        self.status = CalibrationStatus("searching")

    def detect(self, image: np.ndarray) -> dict[int, np.ndarray]:
        """Marker 0–3 visti nell'immagine: id → (4, 2) angoli normalizzati della camera."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
        corners, ids, _ = self._detector.detectMarkers(gray)
        self.last_detection = (corners, ids)
        h, w = gray.shape[:2]
        found: dict[int, np.ndarray] = {}
        if ids is not None:
            for c, i in zip(corners, ids.flatten()):
                if int(i) in MARKER_IDS:
                    found[int(i)] = c.reshape(4, 2) / np.array([w, h], dtype=np.float64)
        return found

    def feed(self, image: np.ndarray) -> CalibrationStatus:
        if self.layout is None or self.status.state == "done":
            return self.status
        found = self.detect(image)
        ids = sorted(found)
        if len(found) < len(MARKER_IDS):
            self._samples.clear()
            self.status = CalibrationStatus("searching", ids, message="non vedo tutti i 4 marker")
            return self.status
        self._samples.append(found)
        if len(self._samples) < self.frames_needed:
            self.status = CalibrationStatus("collecting", ids, len(self._samples) / self.frames_needed)
            return self.status
        cam = np.concatenate([np.mean([s[i] for s in self._samples], axis=0) for i in MARKER_IDS])
        screen = np.concatenate([self.layout[i] for i in MARKER_IDS])
        self._samples.clear()
        try:
            h, err = solve_homography(cam, screen)
        except ValueError as e:
            self.status = CalibrationStatus("failed", ids, message=str(e))
            return self.status
        if err > self.max_error:
            self.status = CalibrationStatus("failed", ids, 1.0, err, "errore troppo alto: camera o marker si muovono?")
            return self.status
        self.homography = h
        self.status = CalibrationStatus("done", ids, 1.0, err)
        return self.status

    def save(self, path: Path, camera_size: tuple[int, int]) -> None:
        if self.homography is None or self.layout is None:
            raise RuntimeError("calibrazione non completata")
        HomographyProjection(self.homography).save(
            path,
            {
                "error": self.status.error,
                "camera_size": list(camera_size),
                "created": time.strftime("%Y-%m-%d %H:%M:%S"),
                "layout": {str(i): self.layout[i].tolist() for i in MARKER_IDS},
            },
        )


def draw_debug(image: np.ndarray, calibrator: Calibrator) -> np.ndarray:
    out = image.copy()
    corners, ids = calibrator.last_detection
    if ids is not None and len(corners):
        cv2.aruco.drawDetectedMarkers(out, corners, ids)
    s = calibrator.status
    text = f"calibrazione: {s.state}  marker: {s.found}  {int(s.progress * 100)}%"
    if s.error is not None:
        text += f"  errore: {s.error * 100:.2f}%"
    for color, width in (((0, 0, 0), 3), ((255, 255, 255), 1)):
        cv2.putText(out, text, (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, width, cv2.LINE_AA)
        if s.message:
            cv2.putText(out, s.message, (10, 46), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, width, cv2.LINE_AA)
    return out


def run_calibration(cfg: dict[str, Any], debug: bool = False, timeout: float = 0.0) -> bool:
    """Ciclo di calibrazione con la camera. Manda lo stato a Godot nei pacchetti v1
    (campo "calibration", lista giocatori vuota). True se la calibrazione è riuscita."""
    from .capture import SOURCES
    from .config import TRACKER_DIR
    from .control import ControlChannel
    from .protocol import PROTOCOL_VERSION
    from .sinks import SINKS

    cal_cfg = cfg["calibration"]
    control = ControlChannel(cfg["control"]["host"], int(cfg["control"]["port"]))
    sinks = [SINKS.get(o.get("type", "udp"))(o) for o in cfg["outputs"]]
    source = SOURCES.get(cfg["source"].get("type", "camera"))(cfg["source"])
    calibrator = Calibrator(int(cal_cfg["frames_needed"]), float(cal_cfg["max_error"]))
    path = Path(cfg["projection"].get("calibration_file", "calibration.json"))
    if not path.is_absolute():
        path = TRACKER_DIR / path
    log.info("calibrazione: apri in Godot la scena res://tools/calibration/calibration.tscn sul proiettore")
    start = time.monotonic()
    last_state = ""
    ok = False
    try:
        while True:
            for msg in control.poll():
                if msg["type"] == "calibration_layout":
                    try:
                        calibrator.set_layout(parse_layout(msg))
                    except ValueError as e:
                        log.warning("layout non valido: %s", e)
            frame = source.read()
            if frame is None:
                break
            status = calibrator.feed(frame.image)
            if status.state != last_state:
                log.info("calibrazione: %s %s", status.state, status.message)
                last_state = status.state
            packet = {"v": PROTOCOL_VERSION, "t": round(frame.t, 4), "space": "camera", "players": [],
                      "calibration": status.to_dict()}
            for s in sinks:
                s.send(packet)
            if debug:
                cv2.imshow("calibrazione (q / Esc per annullare)", draw_debug(frame.image, calibrator))
                if cv2.waitKey(1) & 0xFF in (ord("q"), 27):
                    break
            if status.state == "done":
                calibrator.save(path, frame.size)
                log.info("calibrazione salvata in %s (errore %.2f%% dello schermo)", path, (status.error or 0) * 100)
                ok = True
                break
            if timeout and time.monotonic() - start > timeout:
                log.warning("calibrazione: tempo scaduto")
                break
    finally:
        if debug:
            cv2.destroyAllWindows()
        source.close()
        for s in sinks:
            s.close()
        control.close()
    return ok
