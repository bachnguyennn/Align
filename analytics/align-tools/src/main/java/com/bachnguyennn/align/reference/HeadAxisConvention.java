package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Vec3;

/**
 * Mirrors AlignCore {@code HeadAxisConvention.airPodsDefault} after D-011. Assumed head frame:
 * +X toward the right ear, +Y toward the nose, +Z up (UNVERIFIED on hardware, task S-05). A
 * positive (right-hand rule) rotation about {@code forwardAxis} = chin toward chest; about
 * {@code lateralAxis} = right ear toward right shoulder. forward x lateral = (0, 0, -1) (down).
 */
public record HeadAxisConvention(Vec3 forwardAxis, Vec3 lateralAxis) {

    public static final HeadAxisConvention DEFAULT =
            new HeadAxisConvention(new Vec3(-1.0, 0.0, 0.0), new Vec3(0.0, 1.0, 0.0));
}
