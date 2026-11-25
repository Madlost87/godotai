"""Mappatura sensore → schermo: specchio senza deformazioni e zona di gioco attorno al
corpo (stessa posa = stesso punto sullo schermo, a qualsiasi distanza dalla camera)."""
import pytest

from tracker.identity import IdentityResolver
from tracker.pipeline import Pipeline
from tracker.projection import (BodyZoneProjection, CameraProjection, MirrorProjection,
                                load_projection)
from tracker.protocol import build_packet, validate_packet
from tracker.structs import FrameResult, Person, Point

from .helpers import frame

CAMERA_ASPECT = 4 / 3  # i frame di prova (64×48) e la camera reale (640×480)


def body(cx: float, sy: float, half: float, hand: tuple[float, float] | None = None, pid: str = "p1") -> Person:
    """Persona davanti alla camera: la sua spalla sinistra appare a destra nell'immagine.
    `half` = metà larghezza spalle (più grande = più vicina alla camera). `hand` = polso
    destro come spostamento dalle spalle, in larghezze spalle (x verso la SUA destra)."""
    p = Person(id=pid)
    p.points["shoulder_l"] = Point(cx + half, sy)
    p.points["shoulder_r"] = Point(cx - half, sy)
    p.points["shoulder_c"] = Point(cx, sy)
    if hand is not None:
        sw = 2 * half  # in larghezze dell'immagine; in verticale vale sw × (4/3) altezze
        p.points["wrist_r"] = Point(cx - hand[0] * sw, sy + hand[1] * sw * CAMERA_ASPECT)
    return p


def zone_frame(t: float, *persons: Person) -> FrameResult:
    r = FrameResult(frame(t))
    r.persons = list(persons)
    return r


def screen_of(proj: BodyZoneProjection, person: Person, point: str) -> tuple[float, float]:
    pt = person.points[point]
    return proj.for_person(person).project(pt.x, pt.y)


def test_mirror_keeps_proportions():
    m = MirrorProjection()
    m.set_camera_size(640, 480)
    m.set_screen_aspect(16 / 9)
    assert m.project(0.5, 0.5) == pytest.approx((0.5, 0.5))
    assert m.project(0.2, 0.125) == pytest.approx((0.8, 0.0))  # specchio; sopra si taglia
    assert m.project(0.2, 0.875) == pytest.approx((0.8, 1.0))
    m.set_screen_aspect(1.0)  # schermo più stretto della camera: si taglia ai lati
    assert m.project(1.0 - 0.125, 0.3) == pytest.approx((0.0, 0.3))


def test_body_zone_reaches_whole_screen_with_natural_reach():
    z = BodyZoneProjection(width_sw=3.2, top_sw=1.1, smoothing=0.0)
    z.set_camera_size(640, 480)
    p = body(0.5, 0.45, 0.05, hand=(1.6, -1.1))  # mano destra in alto a destra (sua destra)
    z.update(zone_frame(0.0, p))
    x, y = screen_of(z, p, "wrist_r")
    assert x == pytest.approx(1.0, abs=0.02) and y == pytest.approx(0.0, abs=0.02)  # angolo in alto a destra
    sx, sy = screen_of(z, p, "shoulder_l")
    assert 0.3 < sx < 0.5  # la spalla sinistra appare a sinistra (specchio)
    assert z.zone_of("p1") is not None


def test_body_zone_same_pose_same_point_at_any_distance():
    far = BodyZoneProjection(smoothing=0.0)
    near = BodyZoneProjection(smoothing=0.0)
    for proj in (far, near):
        proj.set_camera_size(640, 480)
    p_far = body(0.5, 0.4, 0.04, hand=(1.0, -0.5))
    p_near = body(0.45, 0.5, 0.12, hand=(1.0, -0.5))  # più vicina e spostata
    far.update(zone_frame(0.0, p_far))
    near.update(zone_frame(0.0, p_near))
    assert screen_of(far, p_far, "wrist_r") == pytest.approx(screen_of(near, p_near, "wrist_r"), abs=1e-6)


def test_body_zone_follows_person_slowly():
    z = BodyZoneProjection(smoothing=1.0)
    z.set_camera_size(640, 480)
    z.update(zone_frame(0.0, body(0.5, 0.45, 0.05)))
    cx0 = z.zones["p1"].cx
    z.update(zone_frame(0.1, body(0.3, 0.45, 0.05)))  # la persona si sposta di colpo
    cx1 = z.zones["p1"].cx
    target = (1 - 0.3) * 4 / 3
    assert abs(cx1 - cx0) < abs(target - cx0) * 0.2  # dopo 0.1 s si è mossa poco
    for i in range(2, 60):
        z.update(zone_frame(i * 0.1, body(0.3, 0.45, 0.05)))
    assert z.zones["p1"].cx == pytest.approx(target, abs=0.01)  # poi la raggiunge


def test_body_zone_without_shoulders_falls_back_to_mirror():
    z = BodyZoneProjection(smoothing=0.0)
    z.set_camera_size(640, 480)
    p = Person(id="p1", effectors={"e0": Point(0.2, 0.5)})
    z.update(zone_frame(0.0, p))
    assert z.for_person(p) is z
    assert z.for_person(p).project(0.2, 0.5) == pytest.approx(MirrorProjection().project(0.2, 0.5))


def test_body_zone_forgets_people_who_left():
    z = BodyZoneProjection(smoothing=0.0, forget_after=1.0)
    z.update(zone_frame(0.0, body(0.5, 0.45, 0.05)))
    z.update(zone_frame(2.0))
    assert "p1" not in z.zones


def test_screen_aspect_changes_zone_height():
    z = BodyZoneProjection(smoothing=0.0)
    p = body(0.5, 0.45, 0.05, hand=(0.0, 1.0))  # mano sotto la spalla
    z.update(zone_frame(0.0, p))
    _, y_wide = screen_of(z, p, "wrist_r")
    z.set_screen_aspect(4 / 3)  # proiettore 4:3: zona più alta
    _, y_43 = screen_of(z, p, "wrist_r")
    assert y_43 < y_wide


def test_load_projection_modes(tmp_path):
    missing = str(tmp_path / "manca.json")
    assert isinstance(load_projection({"mode": "auto", "uncalibrated": "body_zone", "calibration_file": missing}),
                      BodyZoneProjection)
    assert isinstance(load_projection({"mode": "mirror", "calibration_file": missing}), MirrorProjection)
    assert type(load_projection({"calibration_file": missing})) is CameraProjection  # vecchio default
    with pytest.raises(FileNotFoundError):
        load_projection({"mode": "homography", "calibration_file": missing})
    with pytest.raises(ValueError):
        load_projection({"mode": "boh", "calibration_file": missing})


def test_pipeline_applies_screen_from_session_and_per_person_zones():
    class Src:
        produces = "image"

        def __init__(self):
            self.i = 0

        def read(self):
            if self.i >= 5:
                return None
            self.i += 1
            return frame(self.i / 30, self.i)

        def close(self):
            pass

    class OnePerson:
        accepts = ("image",)
        provides = ("pose", "effectors")

        def process(self, f, result):
            result.persons.append(body(0.5, 0.45, 0.05, hand=(1.6, -1.1), pid=""))

        def apply_session(self, s):
            pass

        def close(self):
            pass

    proj = BodyZoneProjection(smoothing=0.0)
    pipe = Pipeline(Src(), [OnePerson()], proj, IdentityResolver({"mode": "markerless", "max_players": 1}, proj), [])
    assert pipe.apply_session({"type": "session", "screen": [1000, 1000]}) is True
    assert proj.screen_aspect == pytest.approx(1.0)
    assert pipe.apply_session({"type": "session", "screen": [1000, 1000]}) is False  # uguale: niente
    packets = []
    pipe.run(lambda r, pkt: packets.append(pkt))
    pkt = packets[-1]
    assert validate_packet(pkt) == []
    hx, hy = pkt["players"][0]["pose"]["wrist_r"][:2]
    assert hx == pytest.approx(1.0, abs=0.03)  # la mano tesa arriva al bordo destro dello schermo
    assert proj.camera_aspect == pytest.approx(64 / 48)  # dalle dimensioni dei frame


def test_build_packet_uses_zone_of_each_person():
    z = BodyZoneProjection(smoothing=0.0)
    a = body(0.3, 0.45, 0.05, hand=(0.0, 0.0), pid="p1")
    b = body(0.7, 0.45, 0.05, hand=(0.0, 0.0), pid="p2")
    r = zone_frame(0.0, a, b)
    z.update(r)
    pkt = build_packet(r, z, 30.0)
    xa = pkt["players"][0]["pose"]["shoulder_r"][0]
    xb = pkt["players"][1]["pose"]["shoulder_r"][0]
    assert xa == pytest.approx(xb, abs=1e-3)  # ognuno nella sua zona: stessa posa, stesso punto
