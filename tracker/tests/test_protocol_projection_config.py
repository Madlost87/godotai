import json

import numpy as np
import pytest

from tracker import projection as projection_mod
from tracker.config import DEFAULTS, deep_merge, load_config
from tracker.projection import CameraProjection, HomographyProjection, load_projection
from tracker.protocol import MAX_PACKET_BYTES, build_packet, encode
from tracker.structs import Face, Hand, Point

from .helpers import person_at, result_with


def test_packet_structure_and_projection():
    r = result_with(1.23456, 0.3, 0.7)
    r.persons[0].id = "p2"
    r.persons[1].id = None  # non giocatore: non inviato
    r.persons[0].hands["r"] = Hand({"wrist": Point(0.2, 0.6)}, {"open": 0.91234})
    r.persons[0].face = Face(Point(0.3, 0.2), {"yaw": -12.3456})
    pkt = build_packet(r, CameraProjection(mirror=True), 29.97)
    assert pkt["v"] == 1 and pkt["space"] == "camera" and pkt["fps"] == 30.0 and pkt["t"] == 1.2346
    assert [p["id"] for p in pkt["players"]] == ["p2"]
    p = pkt["players"][0]
    assert p["pose"]["shoulder_c"] == [0.7, 0.4, 1.0]  # specchiato
    assert p["hands"]["r"] == {"wrist": [0.8, 0.6, 1.0], "open": 0.912}
    assert p["face"] == {"x": 0.7, "y": 0.2, "yaw": -12.346}
    assert "marker" not in p


def test_packet_size_with_three_full_bodies():
    from types import SimpleNamespace

    from tracker.detectors.pose import landmarks_to_person

    r = result_with(0.0)
    for i in range(3):
        lms = [SimpleNamespace(x=0.123456, y=0.654321, visibility=0.987, presence=0.99) for _ in range(33)]
        person = landmarks_to_person(lms)
        person.id = f"p{i + 1}"
        r.persons.append(person)
    data = encode(build_packet(r, CameraProjection(), 30.0))
    assert len(data) < MAX_PACKET_BYTES
    assert json.loads(data)["players"][2]["id"] == "p3"


def test_homography_projection(tmp_path, monkeypatch):
    h = np.array([[2.0, 0, -0.5], [0, 2.0, -0.5], [0, 0, 1.0]])  # zoom 2x centrato
    proj = HomographyProjection(h)
    assert proj.project(0.5, 0.5) == pytest.approx((0.5, 0.5))
    assert proj.project(0.25, 0.75) == pytest.approx((0.0, 1.0))
    proj.save(tmp_path / "calibration.json")
    monkeypatch.setattr(projection_mod, "TRACKER_DIR", tmp_path)
    loaded = load_projection({"calibration_file": "calibration.json"})
    assert isinstance(loaded, HomographyProjection) and loaded.space == "screen"
    assert loaded.project(0.25, 0.75) == pytest.approx((0.0, 1.0))
    none = load_projection({"calibration_file": "manca.json", "mirror": False})
    assert isinstance(none, CameraProjection) and none.project(0.2, 0.3) == (0.2, 0.3)


def test_config_merge_and_validation(tmp_path, caplog):
    merged = deep_merge(DEFAULTS, {"identity": {"max_players": 3}, "detectors": {"hands": {"enabled": False}}, "boh": 1})
    assert merged["identity"]["max_players"] == 3
    assert merged["identity"]["assign"] == "zones"  # default conservato
    assert "hands" in merged["detectors"]
    assert "boh" in caplog.text  # chiave sconosciuta segnalata
    assert DEFAULTS["identity"]["max_players"] == 2  # i default non vengono modificati

    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps({"identity": {"mode": "telepatia"}}))
    with pytest.raises(ValueError):
        load_config(bad)


def test_project_config_file_is_valid():
    cfg = load_config()
    assert cfg["identity"]["mode"] == "markerless"
    assert cfg["detectors"]["pose"]["enabled"] is True


def test_person_helper_sanity():
    assert person_at(0.3).reference().x == 0.3
