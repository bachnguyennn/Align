"""Head-pose model shared by the fixture generator, tests and evaluation.

Attitude q = Yaw(heading about world Z) * Tilt(rotation vector forward*forwardAxis +
lateral*lateralAxis, head frame) * Mount(pitch about forwardAxis, then roll about lateralAxis);
gravity in the device frame = q* (0, 0, -1) q. Axes always come from a HeadAxisConvention (by
default the AlignCore default, D-011), never hard-coded, so that "+20 deg forward" here means
TiltEstimate.forwardDegrees = +20 under the same convention.
"""

from __future__ import annotations

import math
from typing import Optional

from .geometry import (
    Quat,
    Vec3,
    add,
    gravity_in_head_frame,
    quat_from_axis_angle,
    quat_from_rotation_vector,
    quat_mul,
    quat_normalized,
    scale,
)
from .model import HeadAxisConvention, MotionSample

RAD = math.pi / 180.0
WORLD_UP = Vec3(0.0, 0.0, 1.0)


def pose_attitude(forward_deg: float, lateral_deg: float, heading_deg: float = 0.0,
                  mount_pitch_deg: float = 0.0, mount_roll_deg: float = 0.0,
                  axes: Optional[HeadAxisConvention] = None) -> Quat:
    a = axes if axes is not None else HeadAxisConvention()
    rv = add(scale(a.forward_axis, forward_deg * RAD), scale(a.lateral_axis, lateral_deg * RAD))
    tilt = quat_from_rotation_vector(rv)
    yaw = quat_from_axis_angle(WORLD_UP, heading_deg * RAD)
    mount = quat_mul(
        quat_from_axis_angle(a.forward_axis, mount_pitch_deg * RAD),
        quat_from_axis_angle(a.lateral_axis, mount_roll_deg * RAD),
    )
    return quat_normalized(quat_mul(quat_mul(yaw, tilt), mount))


def pose_sample(t: float, forward_deg: float = 0.0, lateral_deg: float = 0.0, heading_deg: float = 0.0,
                mount_pitch_deg: float = 0.0, mount_roll_deg: float = 0.0, include_gravity: bool = True,
                axes: Optional[HeadAxisConvention] = None) -> MotionSample:
    q = pose_attitude(forward_deg, lateral_deg, heading_deg, mount_pitch_deg, mount_roll_deg, axes)
    g = gravity_in_head_frame(q) if include_gravity else None
    return MotionSample(timestamp=t, attitude=q, gravity=g)
