"""Tilt estimation from head-frame gravity relative to a baseline gravity (D-005).

Derivation (also in docs/research/algorithm-evaluation.md):

Let R0 be the head->world attitude at neutral and R1 = R0 * D the current attitude, where D is
the head's rotation expressed in the head frame (a body-frame increment). With world gravity
gw = (0, 0, -1) (Core Motion's Z-vertical reference frame), gravity seen in the head frame is
g0 = R0^T gw at neutral and g = R1^T gw = D^T R0^T gw = D^T g0 now. So the rotation that takes
g0 to g is D^T = D^-1: gravity in the head frame rotates *opposite* to the head. We compute the
minimal rotation taking g0 to g as a rotation vector r (axis g0 x g, angle atan2(|g0 x g|, g0.g))
and the head rotation vector is -r. Rotation about g0 (heading/yaw) leaves g unchanged and is
therefore excluded by construction. For a pure flexion/lateral-bend D (axis perpendicular to
g0), the minimal rotation is exactly D^T, so -r equals D's rotation vector exactly.

Axis projection: forward = (-r) . a_f and lateral = (-r) . a_l, in degrees. Because r is always
perpendicular to g0, the reference uses "baseline-plane axes": each configured axis is first
projected onto the plane perpendicular to g0 and renormalized. When the configured axis is
already perpendicular to g0 (e.g. g0 = -z with axes x/y) this is identical to the plain
projection. When the earbud sits pitched or rolled in the ear (g0 not exactly -z), the true
flexion/lateral axes are horizontal at neutral, i.e. perpendicular to g0, and the plain
projection under-reads by cos(offset); the baseline-plane projection removes that error.
`orthogonalize_axes=False` gives the plain projection (used only by the evaluation).
"""

from __future__ import annotations

import math

from .geometry import (
    DEGREES_PER_RADIAN,
    Vec3,
    cross,
    dot,
    length,
    neg,
    normalized,
    scale,
    sub,
)
from .model import HeadAxisConvention, TiltEstimate

# Below this cross-product length the two gravity vectors are treated as parallel.
PARALLEL_EPSILON = 1e-12
# A configured axis closer than ~0.06 degrees to the baseline gravity cannot be projected.
AXIS_DEGENERACY_EPSILON = 1e-3


def rotation_vector(from_unit: Vec3, to_unit: Vec3) -> Vec3:
    """Minimal rotation taking unit vector `from_unit` to `to_unit`, as axis * angle (radians)."""
    c = cross(from_unit, to_unit)
    s = length(c)
    d = dot(from_unit, to_unit)
    angle = math.atan2(s, d)
    if s < PARALLEL_EPSILON:
        # Parallel (angle 0) or antiparallel (axis undefined): report no directional rotation.
        return Vec3(0.0, 0.0, 0.0)
    return scale(c, angle / s)


def baseline_plane_axis(axis: Vec3, baseline_unit: Vec3) -> Vec3:
    """Projects `axis` onto the plane perpendicular to the baseline gravity and renormalizes."""
    a = normalized(axis)
    p = sub(a, scale(baseline_unit, dot(a, baseline_unit)))
    n = length(p)
    if n < AXIS_DEGENERACY_EPSILON:
        return a
    return scale(p, 1.0 / n)


def estimate_tilt(
    timestamp: float,
    gravity_unit: Vec3,
    baseline_unit: Vec3,
    axes: HeadAxisConvention,
    orthogonalize_axes: bool = True,
) -> TiltEstimate:
    r = rotation_vector(baseline_unit, gravity_unit)
    head = neg(r)
    if orthogonalize_axes:
        forward_axis = baseline_plane_axis(axes.forward_axis, baseline_unit)
        lateral_axis = baseline_plane_axis(axes.lateral_axis, baseline_unit)
    else:
        forward_axis = normalized(axes.forward_axis)
        lateral_axis = normalized(axes.lateral_axis)
    total = math.atan2(length(cross(baseline_unit, gravity_unit)), dot(baseline_unit, gravity_unit))
    return TiltEstimate(
        timestamp=timestamp,
        forward_degrees=dot(head, forward_axis) * DEGREES_PER_RADIAN,
        lateral_degrees=dot(head, lateral_axis) * DEGREES_PER_RADIAN,
        total_degrees=total * DEGREES_PER_RADIAN,
    )
