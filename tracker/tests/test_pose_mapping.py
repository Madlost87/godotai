from types import SimpleNamespace

from tracker.detectors.pose import LANDMARK_NAMES, landmarks_to_person


def lm(x=0.5, y=0.5, vis=0.9, pres=0.9):
    return SimpleNamespace(x=x, y=y, visibility=vis, presence=pres)


def full_body(**over):
    lms = [lm() for _ in range(33)]
    lms[11] = lm(0.6, 0.3)  # spalla sinistra della persona
    lms[12] = lm(0.4, 0.3)
    lms[23] = lm(0.58, 0.6)
    lms[24] = lm(0.42, 0.6)
    for i, v in over.items():
        lms[int(i[1:])] = v
    return lms


def test_names_and_centers():
    p = landmarks_to_person(full_body())
    assert set(p.points) == set(LANDMARK_NAMES.values()) | {"shoulder_c", "hip_c"}
    assert p.points["shoulder_c"].x == 0.5 and p.points["shoulder_c"].y == 0.3
    assert abs(p.points["hip_c"].y - 0.6) < 1e-9
    assert p.reference() is p.points["shoulder_c"]


def test_upper_body_only_framing():
    """Inquadratura del solo busto: anche e gambe fuori immagine o poco visibili."""
    lms = full_body()
    for i in (23, 24, 25, 26, 27, 28, 29, 30, 31, 32):
        lms[i] = lm(0.5, 1.4, vis=0.2)
    p = landmarks_to_person(lms)
    assert "hip_l" not in p.points and "knee_r" not in p.points and "hip_c" not in p.points
    assert "shoulder_c" in p.points and "wrist_l" in p.points


def test_visibility_and_margin_filters():
    lms = full_body(i15=lm(0.5, 0.5, vis=0.3), i16=lm(1.2, 0.5), i13=lm(1.04, 0.5))
    p = landmarks_to_person(lms, min_visibility=0.5, margin=0.05)
    assert "wrist_l" not in p.points  # poco visibile
    assert "wrist_r" not in p.points  # fuori immagine
    assert "elbow_l" in p.points  # dentro il margine
    assert p.points["elbow_l"].conf == 0.9


def test_confidence_is_min_of_visibility_and_presence():
    p = landmarks_to_person(full_body(i0=lm(vis=0.95, pres=0.7)))
    assert p.points["nose"].conf == 0.7


def test_no_shoulders_fallback_reference():
    lms = full_body(i11=lm(vis=0.1), i12=lm(vis=0.1))
    p = landmarks_to_person(lms)
    assert "shoulder_c" not in p.points
    assert p.reference() is p.points["nose"]
