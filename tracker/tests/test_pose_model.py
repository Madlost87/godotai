"""Il modello MediaPipe si carica e gira (su immagini senza persone)."""
import numpy as np
import pytest

from tracker.models import MODELS_DIR
from tracker.structs import Frame, FrameResult

pytestmark = pytest.mark.skipif(
    not (MODELS_DIR / "pose_landmarker_lite.task").exists(), reason="modello non scaricato"
)


def test_pose_detector_runs_on_empty_frames():
    from tracker.detectors import DETECTORS

    det = DETECTORS.get("pose")({"model": "lite", "num_poses": 2})
    try:
        for i in range(3):
            r = FrameResult(Frame(np.full((240, 320, 3), 40, dtype=np.uint8), i / 30, i))
            det.process(r.frame, r)
            assert r.persons == []
    finally:
        det.close()


def test_pose_detector_session_changes_num_poses():
    from tracker.detectors import DETECTORS

    det = DETECTORS.get("pose")({"model": "lite", "num_poses": 2})
    try:
        det.apply_session({"max_players": 1})
        assert det.num_poses == 1
        r = FrameResult(Frame(np.full((240, 320, 3), 40, dtype=np.uint8), 1.0, 0))
        det.process(r.frame, r)  # il nuovo landmarker funziona
        det.apply_session({"max_players": 1})  # uguale: nessuna ricreazione
        assert det.num_poses == 1
    finally:
        det.close()
