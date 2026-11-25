"""Sorgenti di frame: camera (thread dedicato, solo l'ultimo frame) e file video."""
from __future__ import annotations

import logging
import shutil
import subprocess
import threading
import time
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import cv2

from .registry import Registry
from .structs import Frame

log = logging.getLogger(__name__)


class FrameSource(ABC):
    @abstractmethod
    def read(self) -> Frame | None:
        """Prossimo frame (bloccante). None = sorgente finita."""

    def close(self) -> None:
        pass


SOURCES: Registry[type[FrameSource]] = Registry("sorgente")


def list_cameras(max_index: int = 10) -> list[dict[str, Any]]:
    """Nodi /dev/videoN che danno davvero immagini (le webcam UVC espongono anche un
    nodo di soli metadati, che qui viene escluso)."""
    found = []
    for i in range(max_index):
        if not Path(f"/dev/video{i}").exists():
            continue
        name_file = Path(f"/sys/class/video4linux/video{i}/name")
        name = name_file.read_text().strip() if name_file.exists() else "?"
        cap = cv2.VideoCapture(i, cv2.CAP_V4L2)
        ok = cap.isOpened() and cap.read()[0]
        cap.release()
        found.append({"index": i, "name": name, "capture": bool(ok)})
    return found


def apply_v4l2_controls(device: str, controls: dict[str, Any]) -> None:
    """Imposta controlli della camera (esposizione, bilanciamento del bianco...) con v4l2-ctl."""
    if not controls:
        return
    if shutil.which("v4l2-ctl") is None:
        log.warning("v4l2-ctl non trovato: controlli della camera ignorati")
        return
    for key, value in controls.items():
        r = subprocess.run(["v4l2-ctl", "-d", device, "-c", f"{key}={value}"], capture_output=True, text=True)
        if r.returncode != 0:
            log.warning("controllo %s=%s non applicato: %s", key, value, r.stderr.strip())


@SOURCES.register("camera")
class CameraSource(FrameSource):
    def __init__(self, params: dict[str, Any]) -> None:
        device = params.get("device", "auto")
        if device == "auto":
            cams = [c for c in list_cameras() if c["capture"]]
            if not cams:
                raise RuntimeError("nessuna camera che dia immagini trovata in /dev/video*")
            index = cams[0]["index"]
            log.info("camera: /dev/video%d (%s)", index, cams[0]["name"])
        else:
            index = int(device)
        self._cap = cv2.VideoCapture(index, cv2.CAP_V4L2)
        if not self._cap.isOpened():
            raise RuntimeError(f"impossibile aprire /dev/video{index}")
        fourcc = params.get("fourcc")
        if fourcc:
            self._cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fourcc))
        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, int(params.get("width", 640)))
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, int(params.get("height", 480)))
        self._cap.set(cv2.CAP_PROP_FPS, int(params.get("fps", 30)))
        # 2 buffer: con 1 il driver perde frame (misurato: 20 fps invece di 30 sulla HP FHD).
        # La latenza non cresce perché il thread di cattura tiene solo l'ultimo frame.
        self._cap.set(cv2.CAP_PROP_BUFFERSIZE, int(params.get("buffers", 2)))
        apply_v4l2_controls(f"/dev/video{index}", params.get("controls", {}))

        self._cond = threading.Condition()
        self._latest: Frame | None = None
        self._index = 0
        self._running = True
        self._thread = threading.Thread(target=self._loop, name="camera", daemon=True)
        self._thread.start()

    def _loop(self) -> None:
        while self._running:
            ok, image = self._cap.read()
            t = time.monotonic()
            if not ok:
                time.sleep(0.01)
                continue
            with self._cond:
                self._latest = Frame(image, t, self._index)
                self._index += 1
                self._cond.notify_all()

    def read(self) -> Frame | None:
        with self._cond:
            if not self._cond.wait_for(lambda: self._latest is not None or not self._running, timeout=2.0):
                raise RuntimeError("la camera non manda frame da 2 s")
            frame, self._latest = self._latest, None
            return frame

    def close(self) -> None:
        self._running = False
        self._thread.join(timeout=1.0)
        self._cap.release()


@SOURCES.register("video")
class VideoFileSource(FrameSource):
    """Rilegge un file video: utile per provare e tarare senza camera.
    Il tempo dei frame segue gli fps del file, così il risultato è ripetibile."""

    def __init__(self, params: dict[str, Any]) -> None:
        path = params.get("path", "")
        self._cap = cv2.VideoCapture(str(path))
        if not self._cap.isOpened():
            raise RuntimeError(f"impossibile aprire il video '{path}'")
        self._fps = self._cap.get(cv2.CAP_PROP_FPS) or 30.0
        self._loop = bool(params.get("loop", False))
        self._index = 0
        self._realtime = bool(params.get("realtime", True))
        self._start = time.monotonic()

    def read(self) -> Frame | None:
        ok, image = self._cap.read()
        if not ok and self._loop:
            self._cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ok, image = self._cap.read()
        if not ok:
            return None
        t = self._index / self._fps
        if self._realtime:
            delay = self._start + t - time.monotonic()
            if delay > 0:
                time.sleep(delay)
        frame = Frame(image, t, self._index)
        self._index += 1
        return frame

    def close(self) -> None:
        self._cap.release()
