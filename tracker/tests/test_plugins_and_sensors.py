"""Architettura a plugin e cambio di sensore: un sensore che non dà immagini né
scheletri (come un LiDAR) si collega alla pipeline senza toccare il codice esistente,
e produce pacchetti validi che i giochi capiscono (effettori)."""
import json
import socket

import pytest

from tracker.detectors import DETECTORS
from tracker.detectors.base import Detector
from tracker.identity import IdentityResolver
from tracker.pipeline import Pipeline, check_compatibility
from tracker.projection import CameraProjection
from tracker.protocol import build_packet, validate_packet
from tracker.sinks import SINKS
from tracker.sources import SOURCES
from tracker.sources.base import FrameSource
from tracker.structs import Frame, Point

from .helpers import result_with


def test_plugins_are_discovered_automatically():
    assert {"camera", "video", "synthetic"} <= set(SOURCES.names())
    assert {"pose", "synthetic", "synthetic_contacts"} <= set(DETECTORS.names())


# --- Un sensore nuovo, inventato: un LiDAR 2D che vede punti sul muro -------------

class FakeLidar(FrameSource):
    """Produce "scansioni": liste di punti (x, y) già normalizzati."""

    produces = "scan2d"

    def __init__(self, frames: int) -> None:
        super().__init__({})
        self.n, self.i = frames, 0

    def read(self):
        if self.i >= self.n:
            return None
        x = 0.2 + self.i * 0.01
        f = Frame([(x, 0.5), (x + 0.1, 0.55)], self.i / 30, self.i, kind="scan2d")
        self.i += 1
        return f


class LidarBlobs(Detector):
    """Raggruppa i punti di una scansione in una persona con due effettori."""

    accepts = ("scan2d",)
    provides = ("effectors",)

    def process(self, frame, result) -> None:
        from tracker.structs import Person

        p = Person()
        for k, (x, y) in enumerate(frame.data):
            p.effectors[f"e{k}"] = Point(x, y, 1.0)
        result.persons.append(p)


def test_new_sensor_plugs_into_pipeline_and_speaks_protocol():
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.bind(("127.0.0.1", 0))
    rx.settimeout(1.0)
    proj = CameraProjection(mirror=False)
    pipe = Pipeline(FakeLidar(10), [LidarBlobs({})], proj,
                    IdentityResolver({"mode": "markerless", "max_players": 1}, proj),
                    [SINKS.get("udp")({"port": rx.getsockname()[1]})])
    pipe.run()
    pipe.close()
    pkts = [json.loads(rx.recv(65536)) for _ in range(10)]
    rx.close()
    last = pkts[-1]
    assert last["caps"] == ["effectors"]
    assert last["players"][0]["id"] == "p1"  # identità anche senza scheletro
    assert set(last["players"][0]["effectors"]) == {"e0", "e1"}
    assert "pose" not in last["players"][0]
    assert all(validate_packet(p) == [] for p in pkts)


def test_incompatible_sensor_and_detector_fail_clearly():
    class ImageOnly(Detector):
        accepts = ("image",)

        def process(self, frame, result):
            pass

    with pytest.raises(ValueError, match="scan2d"):
        check_compatibility(FakeLidar(1), [ImageOnly({})])
    check_compatibility(FakeLidar(1), [LidarBlobs({})])  # compatibile: nessun errore


def test_frame_kinds():
    img = Frame([[0]], 0.0, 0)
    assert img.kind == "image"
    scan = Frame([(0.1, 0.2)], 0.0, 0, kind="scan2d")
    assert scan.size == (0, 0)
    with pytest.raises(TypeError):
        _ = scan.image


def test_synthetic_contacts_detector_is_a_lidar_stand_in():
    det = DETECTORS.get("synthetic_contacts")({"count": 2})
    assert det.provides == ("effectors",) and "*" in det.accepts
    r = result_with(0.0)
    det.process(r.frame, r)
    assert len(r.persons) == 2
    assert all(set(p.effectors) == {"e0", "e1"} and not p.points for p in r.persons)
    assert r.persons[0].reference() is not None  # riferimento = media degli effettori


def test_packets_from_synthetic_body_are_valid():
    det = DETECTORS.get("synthetic")({"count": 3})
    proj = CameraProjection()
    ident = IdentityResolver({"mode": "markerless", "max_players": 3}, proj)
    for i in range(5):
        r = result_with(i / 30)
        det.process(r.frame, r)
        ident.resolve(r)
        pkt = build_packet(r, proj, 30.0, ["pose", "effectors"])
        assert validate_packet(pkt) == [], validate_packet(pkt)
        assert len(pkt["players"]) == 3


@pytest.mark.parametrize("bad, fragment", [
    ("testo", "oggetto"),
    ({"v": 2, "players": []}, "v deve"),
    ({"v": 1, "players": "x"}, "players"),
    ({"v": 1, "players": [{"pose": {}}]}, "id"),
    ({"v": 1, "players": [{"id": "a"}, {"id": "a"}]}, "ripetuto"),
    ({"v": 1, "players": [{"id": "a", "pose": {"nose": [0.1]}}]}, "pose.nose"),
    ({"v": 1, "players": [{"id": "a", "effectors": {"e0": ["x", 1]}}]}, "effectors.e0"),
    ({"v": 1, "caps": ["telepatia"], "players": []}, "caps"),
    ({"v": 1, "players": [{"id": "a", "face": {"x": 1}}]}, "face"),
])
def test_validator_rejects_bad_packets(bad, fragment):
    errs = validate_packet(bad)
    assert errs and any(fragment in e for e in errs), errs
