"""Pipeline completa con sorgente e rilevatore finti (niente camera né MediaPipe),
fino ai pacchetti UDP ricevuti su un socket locale."""
import json
import socket

from tracker.detectors.base import Detector
from tracker.identity import IdentityResolver
from tracker.pipeline import Pipeline
from tracker.projection import CameraProjection
from tracker.sinks import SINKS
from tracker.structs import FrameResult

from .helpers import frame, person_at


class FakeSource:
    def __init__(self, n: int) -> None:
        self.n, self.i, self.closed = n, 0, False

    def read(self):
        if self.i >= self.n:
            return None
        f = frame(self.i / 30, self.i)
        self.i += 1
        return f

    def close(self):
        self.closed = True


class WalkingPeople(Detector):
    """Due persone che camminano una verso l'altra."""

    def process(self, f, result: FrameResult) -> None:
        result.persons += [person_at(0.2 + f.index * 0.01), person_at(0.8 - f.index * 0.01)]


def test_pipeline_end_to_end_udp():
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.bind(("127.0.0.1", 0))
    rx.settimeout(1.0)
    port = rx.getsockname()[1]

    proj = CameraProjection(mirror=False)
    source = FakeSource(20)
    pipe = Pipeline(
        source,
        [WalkingPeople({})],
        proj,
        IdentityResolver({"mode": "markerless", "assign": "zones", "max_players": 2}, proj),
        [SINKS.get("udp")({"host": "127.0.0.1", "port": port})],
    )
    collected = []
    n = pipe.run(lambda r, pkt: collected.append(pkt))
    pipe.close()
    assert n == 20 and source.closed
    assert 29.0 < pipe.fps < 31.0

    packets = [json.loads(rx.recv(65536)) for _ in range(20)]
    rx.close()
    assert packets == collected
    last = packets[-1]
    assert [p["id"] for p in last["players"]] == ["p1", "p2"]
    assert last["players"][0]["pose"]["shoulder_c"][0] == 0.39  # p1 = quella partita a sinistra
    assert all([p["id"] for p in pkt["players"]] == ["p1", "p2"] for pkt in packets)


def test_pipeline_stops_on_callback_and_max_frames():
    proj = CameraProjection()
    mk = lambda: Pipeline(FakeSource(50), [], proj, IdentityResolver({"mode": "markerless"}, proj), [])  # noqa: E731
    assert mk().run(lambda r, p: r.frame.index < 4) == 5
    assert mk().run(max_frames=7) == 7


def test_udp_sink_survives_no_listener():
    sink = SINKS.get("udp")({"host": "127.0.0.1", "port": 9})
    sink.send({"v": 1, "players": []})  # nessuno in ascolto: nessuna eccezione
    sink.close()


def test_session_from_game_limits_players():
    """Il gioco chiede 1 giocatore sul canale di controllo: da lì in poi solo p1."""
    import time

    from tracker.control import ControlChannel

    class Recorder(WalkingPeople):
        sessions: list = []

        def apply_session(self, session):
            self.sessions.append(session)

    proj = CameraProjection(mirror=False)
    control = ControlChannel(port=0)
    det = Recorder({})
    pipe = Pipeline(FakeSource(40), [det], proj,
                    IdentityResolver({"mode": "markerless", "max_players": 2}, proj), [], control)
    out = []
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def on_result(r, pkt):
        out.append([p["id"] for p in pkt["players"]])
        if r.frame.index == 9:
            tx.sendto(b'{"type": "session", "max_players": 1.0}', ("127.0.0.1", control.port))
            time.sleep(0.05)
        if r.frame.index == 20:
            tx.sendto(b'{"type": "session", "max_players": "tanti"}', ("127.0.0.1", control.port))
            tx.sendto(b'{"type": "session", "max_players": 1}', ("127.0.0.1", control.port))  # uguale: nessun cambio
            time.sleep(0.05)

    pipe.run(on_result)
    pipe.close()
    tx.close()
    assert out[5] == ["p1", "p2"]
    assert all(ids == ["p1"] for ids in out[11:]), out[11:]
    assert pipe.session == {"max_players": 1} and pipe.identity.max_players == 1
    assert det.sessions == [{"max_players": 1}]  # applicata una volta sola


def test_jsonl_recording_sink(tmp_path):
    """--record: ogni frame su file, con i punti grezzi e il pacchetto; lo script di
    analisi la legge."""
    import json as _json

    from tracker.tools.analyze_recording import main as analyze

    path = tmp_path / "rec.jsonl"
    proj = CameraProjection(mirror=False)
    sink = SINKS.get("jsonl")({"path": str(path)})
    pipe = Pipeline(FakeSource(30), [WalkingPeople({})], proj,
                    IdentityResolver({"mode": "markerless", "max_players": 2}, proj), [sink])
    pipe.run()
    pipe.close()
    rows = [_json.loads(x) for x in path.read_text().splitlines()]
    assert len(rows) == 30
    assert rows[5]["raw"][0]["points"]["shoulder_c"] and rows[5]["packet"]["players"][0]["id"] in ("p1", "p2")
    assert analyze([str(path)]) == 0
