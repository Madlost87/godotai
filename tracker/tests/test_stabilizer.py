"""Stabilizzatore (docs/SPEC.md §10.2): i punti incerti non devono lampeggiare né saltare."""
from tracker.stabilizer import Stabilizer
from tracker.structs import FrameResult, Person, Point

from .helpers import frame

DT = 1 / 30


def step(stab: Stabilizer, i: int, **points: Point | None) -> dict[str, Point]:
    r = FrameResult(frame(i * DT, i))
    p = Person()
    p.id = "p1"
    p.points = {n: pt for n, pt in points.items() if pt is not None}
    r.persons = [p]
    stab.process(r)
    return r.persons[0].points


def test_hysteresis_keeps_flickering_point():
    """Affidabilità che oscilla tra 0,3 e 0,6: prima lampeggiava, ora resta."""
    stab = Stabilizer()
    shown = [("wrist_r" in step(stab, i, wrist_r=Point(0.5, 0.8, 0.6 if i % 2 == 0 else 0.3))) for i in range(30)]
    assert all(shown)


def test_point_appears_only_when_confident():
    stab = Stabilizer()
    assert "wrist_r" not in step(stab, 0, wrist_r=Point(0.5, 0.8, 0.4))
    assert "wrist_r" in step(stab, 1, wrist_r=Point(0.5, 0.8, 0.55))


def test_missing_point_held_then_hidden():
    stab = Stabilizer({"hold_time": 0.25})
    step(stab, 0, wrist_r=Point(0.5, 0.8, 0.9))
    held = step(stab, 1)  # il punto non arriva: resta dov'era
    assert held["wrist_r"].x == 0.5 and held["wrist_r"].conf < 0.9
    assert "wrist_r" in step(stab, 7)  # 0,23 s
    assert "wrist_r" not in step(stab, 9)  # 0,30 s: sparito
    # tornato incerto: resta nascosto (isteresi), tornato sicuro: ricompare
    assert "wrist_r" not in step(stab, 10, wrist_r=Point(0.5, 0.8, 0.4))
    assert "wrist_r" in step(stab, 11, wrist_r=Point(0.5, 0.8, 0.7))


def test_very_uncertain_point_counts_as_missing():
    stab = Stabilizer()
    step(stab, 0, wrist_r=Point(0.5, 0.8, 0.9))
    out = step(stab, 1, wrist_r=Point(0.1, 0.1, 0.1))
    assert out["wrist_r"].x == 0.5  # tenuto, non spostato sul punto inaffidabile


def test_isolated_jump_ignored_repeated_jump_accepted():
    stab = Stabilizer({"max_jump": 0.25})
    step(stab, 0, wrist_r=Point(0.5, 0.5, 0.9))
    assert step(stab, 1, wrist_r=Point(0.9, 0.1, 0.9))["wrist_r"].x == 0.5  # salto isolato
    assert step(stab, 2, wrist_r=Point(0.51, 0.5, 0.9))["wrist_r"].x == 0.51  # era un errore
    step(stab, 3, wrist_r=Point(0.9, 0.1, 0.9))
    assert step(stab, 4, wrist_r=Point(0.9, 0.12, 0.9))["wrist_r"].x == 0.9  # ripetuto: vero


def test_raw_points_kept_for_recording_and_disabled_is_passthrough():
    stab = Stabilizer()
    r = FrameResult(frame(0.0))
    p = Person()
    p.id = "p1"
    p.points = {"wrist_r": Point(0.5, 0.5, 0.3)}
    r.persons = [p]
    stab.process(r)
    assert r.raw is not None and "wrist_r" in r.raw["p1"] and "wrist_r" not in p.points
    off = Stabilizer({"enabled": False})
    r2 = FrameResult(frame(0.0))
    r2.persons = [Person(points={"wrist_r": Point(0.5, 0.5, 0.3)}, id="p1")]
    off.process(r2)
    assert "wrist_r" in r2.persons[0].points


def test_forgets_people_who_left():
    stab = Stabilizer({"forget_after": 1.0})
    step(stab, 0, wrist_r=Point(0.5, 0.5, 0.9))
    stab.process(FrameResult(frame(2.0, 60)))
    assert "p1" not in stab._people


def test_debug_view_light_advice():
    import numpy as np

    from tracker.debug_view import image_advice

    assert "luce" in image_advice(np.full((48, 64, 3), 40, np.uint8))
    assert image_advice(np.full((48, 64, 3), 140, np.uint8)) == ""
