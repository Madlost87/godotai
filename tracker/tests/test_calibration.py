"""Calibrazione su immagini sintetiche: lo schermo con i 4 marker (disegnati dagli stessi
pattern che usa Godot) viene deformato in prospettiva come lo vedrebbe la camera."""
import json
import socket
from pathlib import Path

import cv2
import numpy as np
import pytest

from tracker.calibration import MARKER_IDS, Calibrator, parse_layout, solve_homography
from tracker.control import ControlChannel
from tracker.projection import HomographyProjection

ARUCO_FILE = Path(__file__).resolve().parents[2] / "data" / "aruco_4x4_50.json"
SCREEN = (1280, 720)
CAMERA = (640, 480)
# Dove finiscono gli angoli dello schermo nell'immagine della camera (px): prospettiva obliqua.
SCREEN_IN_CAMERA = np.float32([[90, 70], [575, 95], [600, 410], [60, 385]])


def layout_px(w: int, h: int) -> dict[int, np.ndarray]:
    """Stessa regola della scena Godot (scripts/calibration.gd)."""
    s = min(w, h)
    side, margin = 0.22 * s, 0.04 * s
    origins = {0: (margin, margin), 1: (w - margin - side, margin),
               2: (w - margin - side, h - margin - side), 3: (margin, h - margin - side)}
    return {i: np.array([[x, y], [x + side, y], [x + side, y + side], [x, y + side]]) for i, (x, y) in origins.items()}


def screen_image() -> np.ndarray:
    patterns = json.loads(ARUCO_FILE.read_text())["markers"]
    img = np.full((SCREEN[1], SCREEN[0]), 255, np.uint8)
    for i, corners in layout_px(*SCREEN).items():
        x0, y0 = corners[0]
        cell = (corners[1][0] - x0) / 6
        for r, row in enumerate(patterns[str(i)]):
            for c, bit in enumerate(row):
                if bit == "0":
                    cv2.rectangle(img, (round(x0 + c * cell), round(y0 + r * cell)),
                                  (round(x0 + (c + 1) * cell) - 1, round(y0 + (r + 1) * cell) - 1), 0, -1)
    return img


def camera_view(hide: tuple[int, ...] = ()) -> np.ndarray:
    screen = screen_image()
    for i in hide:  # copre un marker (es. una persona davanti)
        c = layout_px(*SCREEN)[i].astype(int)
        cv2.rectangle(screen, tuple(c[0]), tuple(c[2]), 255, -1)
    src = np.float32([[0, 0], [SCREEN[0], 0], [SCREEN[0], SCREEN[1]], [0, SCREEN[1]]])
    m = cv2.getPerspectiveTransform(src, SCREEN_IN_CAMERA)
    cam = cv2.warpPerspective(screen, m, CAMERA, borderValue=40)
    cam = cv2.GaussianBlur(cam, (3, 3), 0)
    return cv2.cvtColor(cam, cv2.COLOR_GRAY2BGR)


def layout_msg() -> dict:
    w, h = SCREEN
    return {"type": "calibration_layout", "screen": [w, h],
            "markers": {str(i): (c / [w, h]).tolist() for i, c in layout_px(w, h).items()}}


def test_shared_patterns_match_opencv_dictionary():
    patterns = json.loads(ARUCO_FILE.read_text())["markers"]
    d = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    for i in MARKER_IDS:
        img = cv2.aruco.generateImageMarker(d, i, 6)
        assert patterns[str(i)] == ["".join("1" if v > 127 else "0" for v in row) for row in img]


def test_calibration_recovers_homography(tmp_path):
    cal = Calibrator(frames_needed=5)
    assert cal.feed(camera_view()).state == "waiting_layout"
    cal.set_layout(parse_layout(layout_msg()))
    image = camera_view()
    states = [cal.feed(image).state for _ in range(5)]
    assert states == ["collecting"] * 4 + ["done"], states
    assert cal.status.error < 0.002
    proj = HomographyProjection(cal.homography)
    expected = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for (cx, cy), exp in zip(SCREEN_IN_CAMERA / CAMERA, expected):
        assert proj.project(cx, cy) == pytest.approx(exp, abs=0.005)
    path = tmp_path / "calibration.json"
    cal.save(path, CAMERA)
    data = json.loads(path.read_text())
    assert data["camera_size"] == list(CAMERA) and set(data["layout"]) == {"0", "1", "2", "3"}


def test_hidden_marker_keeps_searching():
    cal = Calibrator(frames_needed=3)
    cal.set_layout(parse_layout(layout_msg()))
    for _ in range(5):
        st = cal.feed(camera_view(hide=(2,)))
    assert st.state == "searching" and st.found == [0, 1, 3]
    # appena tutti i marker tornano visibili riparte da capo
    assert cal.feed(camera_view()).progress == pytest.approx(1 / 3)


def test_layout_change_restarts():
    cal = Calibrator(frames_needed=2)
    cal.set_layout(parse_layout(layout_msg()))
    cal.feed(camera_view())
    cal.set_layout(parse_layout(layout_msg()))  # stesso layout: nessun reset
    assert cal.feed(camera_view()).state == "done"
    other = layout_msg()
    other["markers"]["0"][0][0] += 0.01
    cal.set_layout(parse_layout(other))
    assert cal.status.state == "searching" and cal.homography is None


def test_parse_layout_rejects_bad_messages():
    with pytest.raises(ValueError):
        parse_layout({"markers": {"0": [[0, 0]] * 4}})
    with pytest.raises(ValueError):
        parse_layout({"markers": {str(i): [[0, 0]] * 3 for i in range(4)}})
    with pytest.raises(ValueError):
        parse_layout({})


def test_solve_homography_reports_error():
    cam = np.array([[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0.5]], float)
    screen = cam.copy()
    _, err = solve_homography(cam, screen)
    assert err < 1e-9
    screen[4] += 0.1  # punto incoerente
    _, err = solve_homography(cam, screen)
    assert err > 0.01


def test_control_channel_roundtrip():
    ch = ControlChannel(port=0)
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tx.sendto(b"non json", ("127.0.0.1", ch.port))
    tx.sendto(b'{"senza": "type"}', ("127.0.0.1", ch.port))
    tx.sendto(json.dumps(layout_msg()).encode(), ("127.0.0.1", ch.port))
    tx.close()
    import time

    msgs = []
    for _ in range(50):
        msgs += ch.poll()
        if msgs:
            break
        time.sleep(0.01)
    ch.close()
    assert [m["type"] for m in msgs] == ["calibration_layout"]


def _free_port() -> int:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def test_run_calibration_loop_end_to_end(tmp_path):
    """Ciclo completo: video sintetico come camera, layout inviato da un finto Godot,
    stato ricevuto sulla porta dati, calibration.json salvato e caricabile."""
    import threading
    import time

    from tracker.calibration import run_calibration
    from tracker.config import DEFAULTS, deep_merge
    from tracker.projection import load_projection

    video = tmp_path / "camera.avi"
    writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*"MJPG"), 30, CAMERA)
    img = camera_view()
    for _ in range(90):
        writer.write(img)
    writer.release()

    data_rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    data_rx.bind(("127.0.0.1", 0))
    data_rx.settimeout(0.5)
    control_port = _free_port()
    cal_file = tmp_path / "calibration.json"
    cfg = deep_merge(DEFAULTS, {
        "source": {"type": "video", "path": str(video), "realtime": True},
        "outputs": [{"type": "udp", "host": "127.0.0.1", "port": data_rx.getsockname()[1]}],
        "control": {"port": control_port},
        "calibration": {"frames_needed": 10},
        "projection": {"calibration_file": str(cal_file)},
    })

    stop = threading.Event()

    def fake_godot() -> None:
        tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        while not stop.is_set():
            tx.sendto(json.dumps(layout_msg()).encode(), ("127.0.0.1", control_port))
            time.sleep(0.1)
        tx.close()

    th = threading.Thread(target=fake_godot, daemon=True)
    th.start()
    try:
        assert run_calibration(cfg, timeout=10) is True
    finally:
        stop.set()
        th.join()

    states = []
    try:
        while True:
            states.append(json.loads(data_rx.recv(65536))["calibration"]["state"])
    except socket.timeout:
        pass
    data_rx.close()
    assert states[-1] == "done" and "collecting" in states
    proj = load_projection({"calibration_file": str(cal_file)})
    assert proj.space == "screen"
    tl = SCREEN_IN_CAMERA[0] / CAMERA
    assert proj.project(*tl) == pytest.approx((0.0, 0.0), abs=0.01)
