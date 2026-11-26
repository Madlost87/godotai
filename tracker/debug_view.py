"""Finestra di debug (OpenCV): immagine della camera con scheletri, id, fps e tempi."""
from __future__ import annotations

from typing import Any

import cv2
import numpy as np

from .structs import FrameResult, Person

BONES = [
    ("shoulder_l", "shoulder_r"), ("shoulder_l", "elbow_l"), ("elbow_l", "wrist_l"),
    ("shoulder_r", "elbow_r"), ("elbow_r", "wrist_r"), ("wrist_l", "index_l"), ("wrist_r", "index_r"),
    ("shoulder_l", "hip_l"), ("shoulder_r", "hip_r"), ("hip_l", "hip_r"),
    ("hip_l", "knee_l"), ("knee_l", "ankle_l"), ("ankle_l", "heel_l"), ("heel_l", "foot_l"),
    ("hip_r", "knee_r"), ("knee_r", "ankle_r"), ("ankle_r", "heel_r"), ("heel_r", "foot_r"),
    ("ear_l", "eye_l"), ("eye_l", "nose"), ("nose", "eye_r"), ("eye_r", "ear_r"), ("mouth_l", "mouth_r"),
]

COLORS = {  # BGR
    "p1": (110, 230, 90), "p2": (255, 115, 215), "p3": (230, 230, 75),
    "red": (75, 75, 240), "blue": (255, 140, 75), "yellow": (60, 215, 255),
}
UNASSIGNED = (150, 150, 150)
WINDOW = "tracker (q / Esc per uscire)"


class DebugView:
    def __init__(self, mirror: bool = True, projection: Any = None) -> None:
        self.mirror = mirror  # mostra l'immagine come uno specchio, più naturale per chi si guarda
        self.projection = projection  # per disegnare la zona di gioco di ogni persona

    def show(self, result: FrameResult, packet: dict[str, Any], fps: float) -> bool:
        if result.frame.kind == "image":
            img = result.frame.image
        else:  # sensore senza immagine (es. LiDAR): sfondo nero, si vedono solo i dati
            img = np.zeros((480, 640, 3), np.uint8)
        if self.mirror:
            img = cv2.flip(img, 1)
        img = np.ascontiguousarray(img)
        h, w = img.shape[:2]
        for person in result.persons:
            self._draw_person(img, person, w, h)
        lines = [f"{fps:4.1f} fps   persone: {len(result.persons)}   giocatori: {len(packet['players'])}"]
        lines += [f"{k}: {v:.1f} ms" for k, v in result.timings.items()]
        warn = image_advice(result.frame.image) if result.frame.kind == "image" else ""
        if warn:
            cv2.putText(img, warn, (10, h - 16), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4, cv2.LINE_AA)
            cv2.putText(img, warn, (10, h - 16), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (80, 170, 255), 2, cv2.LINE_AA)
        for i, line in enumerate(lines):
            cv2.putText(img, line, (10, 22 + 20 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(img, line, (10, 22 + 20 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.imshow(WINDOW, img)
        key = cv2.waitKey(1) & 0xFF
        return key not in (ord("q"), 27)

    def _px(self, x: float, y: float, w: int, h: int) -> tuple[int, int]:
        if self.mirror:
            x = 1.0 - x
        return int(x * w), int(y * h)

    def _draw_person(self, img: np.ndarray, person: Person, w: int, h: int) -> None:
        color = COLORS.get(person.id or "", UNASSIGNED)
        zone = self.projection.zone_of(person.id) if self.projection is not None and person.id else None
        if zone is not None:  # zona di gioco = tutto lo schermo
            x0, y0, x1, y1 = zone
            a, b = self._px(x0, y0, w, h), self._px(x1, y1, w, h)
            cv2.rectangle(img, (min(a[0], b[0]), a[1]), (max(a[0], b[0]), b[1]), color, 2, cv2.LINE_AA)
            cv2.putText(img, "schermo", (min(a[0], b[0]) + 6, a[1] + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1, cv2.LINE_AA)
        pts = {n: self._px(p.x, p.y, w, h) for n, p in person.points.items()}
        for a, b in BONES:
            if a in pts and b in pts:
                cv2.line(img, pts[a], pts[b], color, 3, cv2.LINE_AA)
        for n, p in pts.items():
            cv2.circle(img, p, 6 if n.endswith("_c") else 4, (255, 255, 255) if n.endswith("_c") else color, -1)
        for e in person.effectors.values():
            cv2.circle(img, self._px(e.x, e.y, w, h), 12, color, 3, cv2.LINE_AA)
        ref = person.reference()
        if ref is not None:
            x, y = self._px(ref.x, ref.y, w, h)
            label = person.id or "-"
            cv2.putText(img, label, (x - 15, y - 25), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 0), 4, cv2.LINE_AA)
            cv2.putText(img, label, (x - 15, y - 25), cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2, cv2.LINE_AA)

    def close(self) -> None:
        cv2.destroyAllWindows()


DARK_LEVEL = 70  # luminosità media (0..255) sotto cui MediaPipe perde le mani


def image_advice(img: np.ndarray) -> str:
    """Consiglio sull'immagine (docs/SPEC.md §10.2): oggi solo la luce."""
    gray = cv2.cvtColor(img[::8, ::8], cv2.COLOR_BGR2GRAY)
    level = float(gray.mean())
    return f"Poca luce ({level:.0f}/255): le mani si perdono, accendi una luce" if level < DARK_LEVEL else ""
