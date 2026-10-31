import math

import pytest

from align_reference.geometry import (
    Vec3,
    angle_between_degrees,
    gravity_in_head_frame,
    normalized,
    quat_from_axis_angle,
    quat_rotate,
)
from align_reference.model import HeadAxisConvention
from align_reference.pose import pose_attitude
from align_reference.tilt import baseline_plane_axis, estimate_tilt, rotation_vector

AXES = HeadAxisConvention()
RAD = math.pi / 180


def tilt_for(forward, lateral, heading=0.0, pitch=0.0, roll=0.0, orthogonalize=True):
    g0 = gravity_in_head_frame(pose_attitude(0, 0, 0, pitch, roll))
    g = gravity_in_head_frame(pose_attitude(forward, lateral, heading, pitch, roll))
    return estimate_tilt(0.0, g, g0, AXES, orthogonalize)


def test_quaternion_rotate_matches_right_hand_rule():
    q = quat_from_axis_angle(Vec3(0, 0, 1), math.pi / 2)
    v = quat_rotate(q, Vec3(1, 0, 0))
    assert v.x == pytest.approx(0, abs=1e-12) and v.y == pytest.approx(1) and v.z == pytest.approx(0, abs=1e-12)


def test_sign_derivation_forward_rotation_gives_positive_forward():
    # The derivation check requested in the brief: rotate the head +20 deg about forwardAxis
    # (Z-up world), gravity in head frame = q.conjugate.rotate((0,0,-1)).
    q = quat_from_axis_angle(AXES.forward_axis, 20 * RAD)
    g = gravity_in_head_frame(q)
    g0 = Vec3(0.0, 0.0, -1.0)
    # Gravity in the head frame rotates the *opposite* way: by -20 deg about x.
    r = rotation_vector(g0, g)
    assert r.x == pytest.approx(-20 * RAD, abs=1e-12)
    t = estimate_tilt(0.0, g, g0, AXES)
    assert t.forward_degrees == pytest.approx(20.0, abs=1e-9)
    assert t.lateral_degrees == pytest.approx(0.0, abs=1e-9)
    assert t.total_degrees == pytest.approx(20.0, abs=1e-9)


@pytest.mark.parametrize("forward,lateral", [(20, 0), (-25, 0), (0, 18), (0, -12), (15, 10), (-10, -20)])
def test_pure_flexion_and_lateral_bend_are_recovered_exactly(forward, lateral):
    t = tilt_for(forward, lateral)
    assert t.forward_degrees == pytest.approx(forward, abs=1e-9)
    assert t.lateral_degrees == pytest.approx(lateral, abs=1e-9)
    assert t.total_degrees == pytest.approx(math.hypot(forward, lateral), abs=1e-9)


@pytest.mark.parametrize("heading", [0, 37, 90, 180, -135])
def test_heading_is_excluded(heading):
    t = tilt_for(20, 5, heading=heading)
    assert t.forward_degrees == pytest.approx(20, abs=1e-9)
    assert t.lateral_degrees == pytest.approx(5, abs=1e-9)


def test_mount_pitch_is_exact_with_baseline_plane_axes_but_not_plain_projection():
    ortho = tilt_for(0, 20, pitch=15, orthogonalize=True)
    plain = tilt_for(0, 20, pitch=15, orthogonalize=False)
    assert ortho.lateral_degrees == pytest.approx(20, abs=1e-9)
    assert plain.lateral_degrees == pytest.approx(20 * math.cos(15 * RAD), abs=1e-9)


def test_axes_already_perpendicular_to_baseline_are_unchanged():
    g0 = Vec3(0, 0, -1)
    a = baseline_plane_axis(Vec3(1, 0, 0), g0)
    assert a == pytest.approx(Vec3(1, 0, 0))


def test_degenerate_axis_falls_back_to_configured_axis():
    g0 = Vec3(0, 0, -1)
    assert baseline_plane_axis(Vec3(0, 0, 1), g0) == pytest.approx(Vec3(0, 0, 1))


def test_rotation_vector_parallel_and_tiny_angles():
    g = Vec3(0, 0, -1)
    assert rotation_vector(g, g) == Vec3(0, 0, 0)
    tiny = normalized(Vec3(1e-9, 0, -1))
    r = rotation_vector(g, tiny)
    assert abs(r.y) == pytest.approx(1e-9, rel=1e-3)


def test_angle_between_small_angle_is_stable():
    a = Vec3(0, 0, -1)
    b = normalized(Vec3(math.tan(0.001 * RAD), 0, -1))
    assert angle_between_degrees(a, b) == pytest.approx(0.001, rel=1e-6)
