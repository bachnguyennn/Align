"""Minimal vector/quaternion math mirroring AlignCore `Vector3` and `Quaternion`.

Quaternions are Hamilton, ordered (x, y, z, w) like `CMQuaternion`.
"""

from __future__ import annotations

import math
from typing import NamedTuple


class Vec3(NamedTuple):
    x: float
    y: float
    z: float


class Quat(NamedTuple):
    x: float
    y: float
    z: float
    w: float


ZERO = Vec3(0.0, 0.0, 0.0)
IDENTITY = Quat(0.0, 0.0, 0.0, 1.0)
DEGREES_PER_RADIAN = 180.0 / math.pi


def dot(a: Vec3, b: Vec3) -> float:
    return a.x * b.x + a.y * b.y + a.z * b.z


def cross(a: Vec3, b: Vec3) -> Vec3:
    return Vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    )


def length(a: Vec3) -> float:
    return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)


def normalized(a: Vec3) -> Vec3:
    """Unit vector, or ZERO if the length is zero (same as `Vector3.normalized`)."""
    n = length(a)
    if not n > 0:
        return ZERO
    return Vec3(a.x / n, a.y / n, a.z / n)


def add(a: Vec3, b: Vec3) -> Vec3:
    return Vec3(a.x + b.x, a.y + b.y, a.z + b.z)


def sub(a: Vec3, b: Vec3) -> Vec3:
    return Vec3(a.x - b.x, a.y - b.y, a.z - b.z)


def scale(a: Vec3, s: float) -> Vec3:
    return Vec3(a.x * s, a.y * s, a.z * s)


def neg(a: Vec3) -> Vec3:
    return Vec3(-a.x, -a.y, -a.z)


def angle_between_degrees(a: Vec3, b: Vec3) -> float:
    """Angle between two vectors in degrees, numerically stable for small angles."""
    return math.atan2(length(cross(a, b)), dot(a, b)) * DEGREES_PER_RADIAN


def quat_from_axis_angle(axis: Vec3, angle_radians: float) -> Quat:
    n = normalized(axis)
    s = math.sin(angle_radians / 2.0)
    return Quat(n.x * s, n.y * s, n.z * s, math.cos(angle_radians / 2.0))


def quat_from_rotation_vector(v: Vec3) -> Quat:
    angle = length(v)
    if angle == 0.0:
        return IDENTITY
    return quat_from_axis_angle(v, angle)


def quat_mul(lhs: Quat, rhs: Quat) -> Quat:
    """Hamilton product: applying `rhs` first, then `lhs`."""
    return Quat(
        lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
        lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
        lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
        lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z,
    )


def quat_conj(q: Quat) -> Quat:
    return Quat(-q.x, -q.y, -q.z, q.w)


def quat_normalized(q: Quat) -> Quat:
    n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if not n > 0:
        return IDENTITY
    return Quat(q.x / n, q.y / n, q.z / n, q.w / n)


def quat_rotate(q: Quat, v: Vec3) -> Vec3:
    p = Quat(v.x, v.y, v.z, 0.0)
    r = quat_mul(quat_mul(q, p), quat_conj(q))
    return Vec3(r.x, r.y, r.z)


# World gravity direction for Core Motion's xArbitraryZVertical reference frame (Z up).
WORLD_GRAVITY = Vec3(0.0, 0.0, -1.0)


def gravity_in_head_frame(attitude: Quat) -> Vec3:
    """Gravity (unit, in g) seen in the head frame for a head->world attitude quaternion."""
    return quat_rotate(quat_conj(quat_normalized(attitude)), WORLD_GRAVITY)
