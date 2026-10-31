"""Builds noise-free MotionSamples for a given head pose (used by tests and evaluation).

Same model as the generator: attitude q = Yaw(heading about world Z) * Tilt(rotation vector
forward*x + lateral*y in the head frame) * Mount(pitch about x, then roll about y); gravity in
the device frame = q* (0, 0, -1) q.
"""

from __future__ import annotations

import math

from .geometry import Quat, Vec3, gravity_in_head_frame, quat_from_axis_angle, quat_from_rotation_vector, quat_mul, quat_normalized
from .model import MotionSample

RAD = math.pi / 180.0


def pose_attitude(forward_deg: float, lateral_deg: float, heading_deg: float = 0.0,
                  mount_pitch_deg: float = 0.0, mount_roll_deg: float = 0.0) -> Quat:
    tilt = quat_from_rotation_vector(Vec3(forward_deg * RAD, lateral_deg * RAD, 0.0))
    yaw = quat_from_axis_angle(Vec3(0.0, 0.0, 1.0), heading_deg * RAD)
    mount = quat_mul(
        quat_from_axis_angle(Vec3(1.0, 0.0, 0.0), mount_pitch_deg * RAD),
        quat_from_axis_angle(Vec3(0.0, 1.0, 0.0), mount_roll_deg * RAD),
    )
    return quat_normalized(quat_mul(quat_mul(yaw, tilt), mount))


def pose_sample(t: float, forward_deg: float = 0.0, lateral_deg: float = 0.0, heading_deg: float = 0.0,
                mount_pitch_deg: float = 0.0, mount_roll_deg: float = 0.0, include_gravity: bool = True) -> MotionSample:
    q = pose_attitude(forward_deg, lateral_deg, heading_deg, mount_pitch_deg, mount_roll_deg)
    g = gravity_in_head_frame(q) if include_gravity else None
    return MotionSample(timestamp=t, attitude=q, gravity=g)
