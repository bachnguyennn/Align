import Foundation

/// A 3D vector. Units depend on context (g for gravity/acceleration, rad/s for rotation rate).
public struct Vector3: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    /// Unit vector in the same direction, or `.zero` if the length is zero.
    public var normalized: Vector3 {
        let l = length
        guard l > 0 else { return .zero }
        return Vector3(x: x / l, y: y / l, z: z / l)
    }

    public func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    public static prefix func - (v: Vector3) -> Vector3 {
        Vector3(x: -v.x, y: -v.y, z: -v.z)
    }
}

/// A rotation quaternion in Hamilton convention with components ordered (x, y, z, w),
/// matching `CMQuaternion`. `q` and `-q` represent the same rotation.
public struct Quaternion: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    /// Rotation of `angleRadians` about `axis` (right-hand rule). `axis` need not be normalized.
    public init(axis: Vector3, angleRadians: Double) {
        let n = axis.normalized
        let s = sin(angleRadians / 2)
        self.init(x: n.x * s, y: n.y * s, z: n.z * s, w: cos(angleRadians / 2))
    }

    public var vector: Vector3 { Vector3(x: x, y: y, z: z) }

    public var norm: Double { (x * x + y * y + z * z + w * w).squareRoot() }

    public var normalized: Quaternion {
        let n = norm
        guard n > 0 else { return .identity }
        return Quaternion(x: x / n, y: y / n, z: z / n, w: w / n)
    }

    public var conjugate: Quaternion { Quaternion(x: -x, y: -y, z: -z, w: w) }

    /// Inverse rotation. Equal to `conjugate` for unit quaternions.
    public var inverse: Quaternion {
        let n2 = x * x + y * y + z * z + w * w
        guard n2 > 0 else { return .identity }
        return Quaternion(x: -x / n2, y: -y / n2, z: -z / n2, w: w / n2)
    }

    public func dot(_ other: Quaternion) -> Double {
        x * other.x + y * other.y + z * other.z + w * other.w
    }

    /// Rotation angle in radians, in [0, π]. Treats `q` and `-q` as the same rotation.
    public var angle: Double {
        2 * acos(min(1, abs(normalized.w)))
    }

    /// Hamilton product: applying `rhs` first, then `lhs`.
    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        Quaternion(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    /// Rotates `v` by this (unit) quaternion.
    public func rotate(_ v: Vector3) -> Vector3 {
        let p = Quaternion(x: v.x, y: v.y, z: v.z, w: 0)
        return (self * p * conjugate).vector
    }
}
