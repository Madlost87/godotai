import pytest

from tracker.identity import ASSIGNERS, ArrivalAssigner, IdentityResolver, PersonTracker, ZonesAssigner
from tracker.projection import CameraProjection

from .helpers import result_with


def resolver(assign: str = "zones", players: int = 2, mirror: bool = False) -> IdentityResolver:
    cfg = {"mode": "markerless", "assign": assign, "max_players": players, "max_distance": 0.15, "hold_time": 0.5}
    return IdentityResolver(cfg, CameraProjection(mirror=mirror))


def ids(r) -> list:
    return [p.id for p in r.persons]


def test_zones_assign_by_entry_side():
    a = ZonesAssigner(2)
    assert a.assign((0.2, 0.5), set()) == "p1"
    assert a.assign((0.8, 0.5), set()) == "p2"
    assert a.assign((0.8, 0.5), {"p2"}) == "p1"  # zona occupata → prima libera
    assert a.assign((0.8, 0.5), {"p1", "p2"}) is None  # pieno
    assert a.assign((1.5, 0.5), set()) == "p2"  # fuori schermo: zona più vicina


def test_arrival_order():
    a = ArrivalAssigner(3)
    assert a.assign((0.9, 0.5), set()) == "p1"
    assert a.assign((0.1, 0.5), {"p1"}) == "p2"


def test_registry_lists_assigners():
    assert ASSIGNERS.names() == ["arrival", "zones"]
    with pytest.raises(ValueError, match="Disponibili"):
        ASSIGNERS.get("boh")


def test_ids_stable_while_crossing():
    """Due persone si incrociano a piccoli passi: gli id non si scambiano."""
    res = resolver()
    seen = []
    for i in range(41):
        a = 0.2 + i * 0.015  # da sinistra a destra
        b = 0.8 - i * 0.015  # da destra a sinistra
        r = result_with(i / 30, a, b)
        res.resolve(r)
        seen.append(ids(r))
    assert seen[0] == ["p1", "p2"]
    assert all(s == ["p1", "p2"] for s in seen), seen


def test_hold_time_keeps_id_for_short_gaps():
    res = resolver()
    r = result_with(0.0, 0.8)
    res.resolve(r)
    assert ids(r) == ["p2"]
    res.resolve(result_with(0.2))  # sparita per 0.2 s
    r = result_with(0.4, 0.82)
    res.resolve(r)
    assert ids(r) == ["p2"]
    res.resolve(result_with(1.0))  # sparita per più di hold_time
    r = result_with(1.1, 0.2)
    res.resolve(r)
    assert ids(r) == ["p1"]  # nuova assegnazione, secondo la zona


def test_waiting_track_blocks_its_id():
    """Mentre p1 è temporaneamente sparito, un nuovo arrivato non gli ruba l'id."""
    res = resolver()
    res.resolve(result_with(0.0, 0.2))
    r = result_with(0.2, 0.25 + 0.3)  # p1 sparito, compare qualcuno lontano a sinistra-centro
    res.resolve(r)
    assert ids(r) == ["p2"]


def test_extra_people_are_not_players():
    res = resolver(players=2)
    r = result_with(0.0, 0.1, 0.5, 0.9)
    res.resolve(r)
    assert sorted(i for i in ids(r) if i) == ["p1", "p2"]
    assert ids(r).count(None) == 1
    assert [p.id for p in r.players()] == ["p1", "p2"]


def test_zones_use_screen_space_after_mirror():
    """Con la camera specchiata, chi è a sinistra nell'immagine è a destra sullo schermo."""
    res = resolver(mirror=True)
    r = result_with(0.0, 0.2)
    res.resolve(r)
    assert ids(r) == ["p2"]


def test_person_without_reference_gets_no_id():
    res = resolver()
    r = result_with(0.0, 0.3)
    r.persons[0].points.clear()
    res.resolve(r)
    assert ids(r) == [None]


def test_other_modes_not_yet_available():
    with pytest.raises(NotImplementedError):
        IdentityResolver({"mode": "mixed"}, CameraProjection())


def test_tracker_greedy_prefers_closest():
    t = PersonTracker(ArrivalAssigner(2), max_distance=0.3)
    r = result_with(0.0, 0.3, 0.5)
    t.update(r.persons, [(0.3, 0.4), (0.5, 0.4)], 0.0)
    assert ids(r) == ["p1", "p2"]
    r = result_with(0.1, 0.48, 0.32)  # elencate in ordine inverso
    t.update(r.persons, [(0.48, 0.4), (0.32, 0.4)], 0.1)
    assert ids(r) == ["p2", "p1"]
