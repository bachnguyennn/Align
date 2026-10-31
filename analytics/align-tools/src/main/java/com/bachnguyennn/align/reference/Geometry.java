package com.bachnguyennn.align.reference;

/**
 * Minimal vector/quaternion math mirroring AlignCore {@code Vector3} and {@code Quaternion}.
 *
 * <p>Quaternions are Hamilton, ordered (x, y, z, w) like {@code CMQuaternion}.
 */
public final class Geometry {

    /** A 3-vector (AlignCore {@code Vector3}). */
    public record Vec3(double x, double y, double z) {}

    /** A Hamilton quaternion (x, y, z, w) like {@code CMQuaternion}. */
    public record Quat(double x, double y, double z, double w) {}

    public static final Vec3 ZERO = new Vec3(0.0, 0.0, 0.0);
    public static final Quat IDENTITY = new Quat(0.0, 0.0, 0.0, 1.0);
    public static final double DEGREES_PER_RADIAN = 180.0 / Math.PI;

    /** World gravity direction for Core Motion's xArbitraryZVertical reference frame (Z up). */
    public static final Vec3 WORLD_GRAVITY = new Vec3(0.0, 0.0, -1.0);

    private Geometry() {}

    public static double dot(Vec3 a, Vec3 b) {
        return a.x() * b.x() + a.y() * b.y() + a.z() * b.z();
    }

    public static Vec3 cross(Vec3 a, Vec3 b) {
        return new Vec3(
                a.y() * b.z() - a.z() * b.y(),
                a.z() * b.x() - a.x() * b.z(),
                a.x() * b.y() - a.y() * b.x());
    }

    public static double length(Vec3 a) {
        return StrictMath.sqrt(a.x() * a.x() + a.y() * a.y() + a.z() * a.z());
    }

    /** Unit vector, or {@link #ZERO} if the length is zero (same as {@code Vector3.normalized}). */
    public static Vec3 normalized(Vec3 a) {
        double n = length(a);
        if (!(n > 0)) {
            return ZERO;
        }
        return new Vec3(a.x() / n, a.y() / n, a.z() / n);
    }

    public static Vec3 add(Vec3 a, Vec3 b) {
        return new Vec3(a.x() + b.x(), a.y() + b.y(), a.z() + b.z());
    }

    public static Vec3 sub(Vec3 a, Vec3 b) {
        return new Vec3(a.x() - b.x(), a.y() - b.y(), a.z() - b.z());
    }

    public static Vec3 scale(Vec3 a, double s) {
        return new Vec3(a.x() * s, a.y() * s, a.z() * s);
    }

    public static Vec3 neg(Vec3 a) {
        return new Vec3(-a.x(), -a.y(), -a.z());
    }

    /** Angle between two vectors in degrees, numerically stable for small angles. */
    public static double angleBetweenDegrees(Vec3 a, Vec3 b) {
        return StrictMath.atan2(length(cross(a, b)), dot(a, b)) * DEGREES_PER_RADIAN;
    }

    public static Quat quatFromAxisAngle(Vec3 axis, double angleRadians) {
        Vec3 n = normalized(axis);
        double s = StrictMath.sin(angleRadians / 2.0);
        return new Quat(n.x() * s, n.y() * s, n.z() * s, StrictMath.cos(angleRadians / 2.0));
    }

    public static Quat quatFromRotationVector(Vec3 v) {
        double angle = length(v);
        if (angle == 0.0) {
            return IDENTITY;
        }
        return quatFromAxisAngle(v, angle);
    }

    /** Hamilton product: applying {@code rhs} first, then {@code lhs}. */
    public static Quat quatMul(Quat lhs, Quat rhs) {
        return new Quat(
                lhs.w() * rhs.x() + lhs.x() * rhs.w() + lhs.y() * rhs.z() - lhs.z() * rhs.y(),
                lhs.w() * rhs.y() - lhs.x() * rhs.z() + lhs.y() * rhs.w() + lhs.z() * rhs.x(),
                lhs.w() * rhs.z() + lhs.x() * rhs.y() - lhs.y() * rhs.x() + lhs.z() * rhs.w(),
                lhs.w() * rhs.w() - lhs.x() * rhs.x() - lhs.y() * rhs.y() - lhs.z() * rhs.z());
    }

    public static Quat quatConj(Quat q) {
        return new Quat(-q.x(), -q.y(), -q.z(), q.w());
    }

    public static Quat quatNormalized(Quat q) {
        double n = StrictMath.sqrt(q.x() * q.x() + q.y() * q.y() + q.z() * q.z() + q.w() * q.w());
        if (!(n > 0)) {
            return IDENTITY;
        }
        return new Quat(q.x() / n, q.y() / n, q.z() / n, q.w() / n);
    }

    public static Vec3 quatRotate(Quat q, Vec3 v) {
        Quat p = new Quat(v.x(), v.y(), v.z(), 0.0);
        Quat r = quatMul(quatMul(q, p), quatConj(q));
        return new Vec3(r.x(), r.y(), r.z());
    }

    /** Gravity (unit, in g) seen in the head frame for a head-to-world attitude quaternion. */
    public static Vec3 gravityInHeadFrame(Quat attitude) {
        return quatRotate(quatConj(quatNormalized(attitude)), WORLD_GRAVITY);
    }
}
