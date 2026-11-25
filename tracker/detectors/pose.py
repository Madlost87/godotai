"""Rilevatore "pose": MediaPipe Pose Landmarker (fino a N persone, 33 punti ciascuna).
Funziona sia con il solo busto inquadrato sia con il corpo intero: i punti fuori
inquadratura o poco visibili semplicemente non vengono inviati."""
from __future__ import annotations

from typing import Any, Iterable

import cv2

from ..models import ensure_model
from ..structs import Frame, FrameResult, Person, Point
from .base import DETECTORS, Detector

# Indice MediaPipe → nome del protocollo (SPEC §5). l/r = lato della persona.
LANDMARK_NAMES: dict[int, str] = {
    0: "nose",
    2: "eye_l", 5: "eye_r", 7: "ear_l", 8: "ear_r", 9: "mouth_l", 10: "mouth_r",
    11: "shoulder_l", 12: "shoulder_r", 13: "elbow_l", 14: "elbow_r",
    15: "wrist_l", 16: "wrist_r", 19: "index_l", 20: "index_r",
    23: "hip_l", 24: "hip_r", 25: "knee_l", 26: "knee_r",
    27: "ankle_l", 28: "ankle_r", 29: "heel_l", 30: "heel_r", 31: "foot_l", 32: "foot_r",
}

# Punti calcolati: nome → coppia di punti di cui fare la media.
CENTERS: dict[str, tuple[str, str]] = {
    "shoulder_c": ("shoulder_l", "shoulder_r"),
    "hip_c": ("hip_l", "hip_r"),
}


def landmarks_to_person(landmarks: Iterable[Any], min_visibility: float = 0.5, margin: float = 0.05) -> Person:
    """Converte i landmark MediaPipe (oggetti con x, y, visibility, presence) in Person.
    Tiene solo i punti abbastanza visibili e dentro l'immagine (± margine)."""
    person = Person()
    for i, lm in enumerate(landmarks):
        name = LANDMARK_NAMES.get(i)
        if name is None:
            continue
        conf = min(_attr(lm, "visibility"), _attr(lm, "presence"))
        if conf < min_visibility:
            continue
        if not (-margin <= lm.x <= 1.0 + margin and -margin <= lm.y <= 1.0 + margin):
            continue
        person.points[name] = Point(float(lm.x), float(lm.y), float(conf))
    for name, (a, b) in CENTERS.items():
        pa, pb = person.points.get(a), person.points.get(b)
        if pa and pb:
            person.points[name] = Point((pa.x + pb.x) / 2, (pa.y + pb.y) / 2, min(pa.conf, pb.conf))
    return person


def _attr(lm: Any, name: str) -> float:
    v = getattr(lm, name, None)
    return 1.0 if v is None else float(v)


@DETECTORS.register("pose")
class PoseDetector(Detector):
    def __init__(self, params: dict[str, Any]) -> None:
        super().__init__(params)
        import mediapipe as mp  # import lento: solo quando serve
        from mediapipe.tasks.python import BaseOptions, vision

        self._mp = mp
        self._vision = vision
        self._base_options = BaseOptions(
            model_asset_path=str(ensure_model(f"pose_landmarker_{params.get('model', 'full')}"))
        )
        self.num_poses = int(params.get("num_poses", 2))
        self._landmarker = self._create(self.num_poses)
        self._min_visibility = float(params.get("min_visibility", 0.5))
        self._margin = float(params.get("margin", 0.05))
        self._last_ts = -1

    def _create(self, num_poses: int) -> Any:
        options = self._vision.PoseLandmarkerOptions(
            base_options=self._base_options,
            running_mode=self._vision.RunningMode.VIDEO,
            num_poses=num_poses,
            min_pose_detection_confidence=float(self.params.get("min_detection_confidence", 0.5)),
            min_pose_presence_confidence=float(self.params.get("min_presence_confidence", 0.5)),
            min_tracking_confidence=float(self.params.get("min_tracking_confidence", 0.5)),
        )
        return self._vision.PoseLandmarker.create_from_options(options)

    def apply_session(self, session: dict[str, Any]) -> None:
        """Cerca tante persone quanti sono i giocatori richiesti (meno CPU, niente
        passanti scambiati per giocatori)."""
        n = session.get("max_players")
        if isinstance(n, int) and n != self.num_poses:
            self._landmarker.close()
            self.num_poses = n
            self._landmarker = self._create(n)

    def process(self, frame: Frame, result: FrameResult) -> None:
        rgb = cv2.cvtColor(frame.image, cv2.COLOR_BGR2RGB)
        image = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=rgb)
        ts = max(int(frame.t * 1000), self._last_ts + 1)  # MediaPipe vuole tempi crescenti
        self._last_ts = ts
        out = self._landmarker.detect_for_video(image, ts)
        for landmarks in out.pose_landmarks:
            person = landmarks_to_person(landmarks, self._min_visibility, self._margin)
            if person.points:
                result.persons.append(person)

    def close(self) -> None:
        self._landmarker.close()
