import Foundation
import XCTest
@testable import AlignCore

final class Vector3Tests: XCTestCase {
    private let a = Vector3(x: 1, y: -2, z: 3)
    private let b = Vector3(x: -4, y: 0.5, z: 2)

    func testArithmeticOperators() {
        XCTAssertEqual(a + b, Vector3(x: -3, y: -1.5, z: 5))
        XCTAssertEqual(a - b, Vector3(x: 5, y: -2.5, z: 1))
        XCTAssertEqual(a * 2, Vector3(x: 2, y: -4, z: 6))
        XCTAssertEqual(-a, Vector3(x: -1, y: 2, z: -3))
        XCTAssertEqual(a + Vector3.zero, a)
        XCTAssertEqual(a - a, Vector3.zero)
    }

    func testLength() {
        XCTAssertEqual(Vector3(x: 3, y: 4, z: 0).length, 5, accuracy: 1e-12)
        XCTAssertEqual(Vector3(x: 1, y: 2, z: 2).length, 3, accuracy: 1e-12)
        XCTAssertEqual(Vector3.zero.length, 0)
    }

    func testDotProduct() {
        // 1*-4 + -2*0.5 + 3*2 = 1
        XCTAssertEqual(a.dot(b), 1, accuracy: 1e-12)
        XCTAssertEqual(a.dot(a), a.length * a.length, accuracy: 1e-12)
        XCTAssertEqual(Fixtures.xAxis.dot(Fixtures.yAxis), 0)
    }

    func testNormalized() {
        let n = a.normalized
        XCTAssertEqual(n.length, 1, accuracy: 1e-12)
        // Same direction: the dot product with the original equals its length.
        XCTAssertEqual(n.dot(a), a.length, accuracy: 1e-12)
        XCTAssertEqual(Vector3.zero.normalized, Vector3.zero)
    }

    func testCrossProductIsRightHanded() {
        let x = Fixtures.xAxis, y = Fixtures.yAxis, z = Fixtures.zAxis
        XCTAssertEqual(x.cross(y), z)
        XCTAssertEqual(y.cross(z), x)
        XCTAssertEqual(z.cross(x), y)
        XCTAssertEqual(y.cross(x), -z)
        XCTAssertEqual(x.cross(z), -y)
    }

    func testCrossProductProperties() {
        let c = a.cross(b)
        XCTAssertEqual(c.dot(a), 0, accuracy: 1e-12)
        XCTAssertEqual(c.dot(b), 0, accuracy: 1e-12)
        XCTAssertEqual(a.cross(a), Vector3.zero)
        XCTAssertEqual(b.cross(a), -c)
        // Lagrange identity: |a x b|^2 + (a.b)^2 = |a|^2 |b|^2
        XCTAssertEqual(c.dot(c) + a.dot(b) * a.dot(b), a.dot(a) * b.dot(b), accuracy: 1e-9)
    }
}

final class QuaternionTests: XCTestCase {
    private let x = Fixtures.xAxis
    private let y = Fixtures.yAxis
    private let z = Fixtures.zAxis

    // MARK: Identity and construction

    func testIdentity() {
        XCTAssertEqual(Quaternion.identity, Quaternion(x: 0, y: 0, z: 0, w: 1))
        XCTAssertEqual(Quaternion.identity.angle, 0, accuracy: 1e-12)
        for v in Fixtures.vectors {
            assertVectorEqual(Quaternion.identity.rotate(v), v)
        }
        for q in Fixtures.rotations {
            assertQuaternionEqual(Quaternion.identity * q, q)
            assertQuaternionEqual(q * Quaternion.identity, q)
        }
    }

    func testAxisAngleConstruction() {
        // The axis does not need to be normalized.
        let q = Quaternion(axis: Vector3(x: 0, y: 0, z: 2), angleRadians: Double.pi / 2)
        let h = (0.5).squareRoot()
        assertQuaternionEqual(q, Quaternion(x: 0, y: 0, z: h, w: h))
        XCTAssertEqual(q.norm, 1, accuracy: 1e-12)
        assertQuaternionEqual(Quaternion(axis: x, angleRadians: 0), Quaternion.identity)
        for q in Fixtures.rotations {
            XCTAssertEqual(q.norm, 1, accuracy: 1e-12)
        }
    }

    func testNormalized() {
        let s = Quaternion(x: 0.2, y: -0.4, z: 0.6, w: 1.6)
        XCTAssertEqual(s.normalized.norm, 1, accuracy: 1e-12)
        XCTAssertEqual(Quaternion(x: 0, y: 0, z: 0, w: 0).normalized, Quaternion.identity)
    }

    // MARK: Rotation direction (right-hand rule)

    func testRotate90DegreesAboutZMapsXToY() {
        let q = Quaternion(axis: z, angleRadians: Double.pi / 2)
        assertVectorEqual(q.rotate(x), y)
        assertVectorEqual(q.rotate(y), -x)
        assertVectorEqual(q.rotate(z), z)
    }

    func testRotate90DegreesAboutXAndY() {
        assertVectorEqual(Quaternion(axis: x, angleRadians: Double.pi / 2).rotate(y), z)
        assertVectorEqual(Quaternion(axis: y, angleRadians: Double.pi / 2).rotate(z), x)
        // Negative angle rotates the other way.
        assertVectorEqual(Quaternion(axis: z, angleRadians: -Double.pi / 2).rotate(x), -y)
    }

    func testRotationPreservesLengthAndAngles() {
        for q in Fixtures.rotations {
            for v in Fixtures.vectors {
                XCTAssertEqual(q.rotate(v).length, v.length, accuracy: 1e-12)
            }
            let u = Fixtures.vectors[3], w = Fixtures.vectors[4]
            XCTAssertEqual(q.rotate(u).dot(q.rotate(w)), u.dot(w), accuracy: 1e-12)
        }
    }

    // MARK: Hamilton product

    func testHamiltonBasisProducts() {
        let i = Quaternion(x: 1, y: 0, z: 0, w: 0)
        let j = Quaternion(x: 0, y: 1, z: 0, w: 0)
        let k = Quaternion(x: 0, y: 0, z: 1, w: 0)
        XCTAssertEqual(i * j, k)
        XCTAssertEqual(j * k, i)
        XCTAssertEqual(k * i, j)
        XCTAssertEqual(j * i, Quaternion(x: 0, y: 0, z: -1, w: 0))
        XCTAssertEqual(i * i, Quaternion(x: 0, y: 0, z: 0, w: -1))
    }

    func testCompositionAppliesRightOperandFirst() {
        let a = Quaternion(axis: z, angleRadians: Double.pi / 2)
        let b = Quaternion(axis: x, angleRadians: Double.pi / 2)
        // b leaves x unchanged, then a maps x to y.
        assertVectorEqual((a * b).rotate(x), y)
        assertVectorEqual(a.rotate(b.rotate(x)), y)
        // The opposite order differs, so this test actually pins the order.
        assertVectorEqual((b * a).rotate(x), z)
    }

    func testCompositionMatchesSequentialRotation() {
        for q1 in Fixtures.rotations {
            for q2 in Fixtures.rotations {
                for v in Fixtures.vectors {
                    assertVectorEqual((q1 * q2).rotate(v), q1.rotate(q2.rotate(v)), accuracy: 1e-9)
                }
            }
        }
    }

    // MARK: Inverse and conjugate

    func testInverseOfUnitQuaternion() {
        for q in Fixtures.rotations {
            assertQuaternionEqual(q * q.inverse, Quaternion.identity)
            assertQuaternionEqual(q.inverse * q, Quaternion.identity)
            assertQuaternionEqual(q.inverse, q.conjugate)
            for v in Fixtures.vectors {
                assertVectorEqual(q.inverse.rotate(q.rotate(v)), v)
                assertVectorEqual(q.rotate(q.inverse.rotate(v)), v)
            }
        }
    }

    func testInverseOfNonUnitQuaternion() {
        let s = Quaternion(x: 0.2, y: -0.4, z: 0.6, w: 1.6)
        assertQuaternionEqual(s * s.inverse, Quaternion.identity)
        assertQuaternionEqual(s.inverse * s, Quaternion.identity)
        XCTAssertEqual(Quaternion(x: 0, y: 0, z: 0, w: 0).inverse, Quaternion.identity)
    }

    // MARK: Angle and sign ambiguity

    func testAngleOfAxisAngleRotation() {
        let angles: [Double] = [0, Double.pi / 6, Double.pi / 2, 2 * Double.pi / 3, Double.pi]
        for angle in angles {
            let q = Quaternion(axis: Vector3(x: 1, y: -1, z: 0.5), angleRadians: angle)
            XCTAssertEqual(q.angle, angle, accuracy: 1e-9, "angle \(angle)")
            XCTAssertEqual(negated(q).angle, angle, accuracy: 1e-9, "-q, angle \(angle)")
        }
    }

    func testAngleReportsShorterRotation() {
        XCTAssertEqual(Quaternion(axis: z, angleRadians: 3 * Double.pi / 2).angle, Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(Quaternion(axis: z, angleRadians: -Double.pi / 3).angle, Double.pi / 3, accuracy: 1e-9)
    }

    func testAngleNormalizesFirst() {
        let q = Quaternion(axis: x, angleRadians: 1.0)
        let scaled = Quaternion(x: q.x * 3, y: q.y * 3, z: q.z * 3, w: q.w * 3)
        XCTAssertEqual(scaled.angle, 1.0, accuracy: 1e-9)
    }

    func testAngleIsAlwaysInZeroToPi() {
        for step in -40...40 {
            let angle = Double(step) * 0.25
            let q = Quaternion(axis: Vector3(x: 0.2, y: -0.7, z: 0.4), angleRadians: angle)
            XCTAssertGreaterThanOrEqual(q.angle, 0, "angle \(angle)")
            XCTAssertLessThanOrEqual(q.angle, Double.pi, "angle \(angle)")
            XCTAssertGreaterThanOrEqual(negated(q).angle, 0, "-q, angle \(angle)")
            XCTAssertLessThanOrEqual(negated(q).angle, Double.pi, "-q, angle \(angle)")
        }
    }

    func testNegatedQuaternionIsSameRotation() {
        for q in Fixtures.rotations {
            let n = negated(q)
            for v in Fixtures.vectors {
                assertVectorEqual(n.rotate(v), q.rotate(v))
            }
            XCTAssertEqual(n.angle, q.angle, accuracy: 1e-12)
        }
    }

    // MARK: Properties the tilt estimator (D-005) relies on

    func testAxisAngleFromCrossProductMapsSourceOntoTarget() {
        let g0 = Vector3(x: 0.1, y: -0.2, z: -0.97).normalized
        let g1 = Vector3(x: 0.3, y: 0.25, z: -0.9).normalized
        let rotation = Quaternion(axis: g0.cross(g1), angleRadians: acos(g0.dot(g1)))
        assertVectorEqual(rotation.rotate(g0), g1, accuracy: 1e-12)
    }

    func testGravityInHeadFrameRotatesOppositeToHead() {
        // Head rotates +theta about x; gravity expressed in the head frame is the world gravity
        // rotated by the inverse, i.e. -theta about x (see architecture.md, "Tilt estimation").
        let theta = 0.4
        let neutralGravity = Vector3(x: 0, y: 0, z: -1)
        let head = Quaternion(axis: x, angleRadians: theta)
        let tiltedGravity = head.inverse.rotate(neutralGravity)
        let axis = neutralGravity.cross(tiltedGravity).normalized
        let angle = acos(max(-1, min(1, neutralGravity.dot(tiltedGravity))))
        assertVectorEqual(axis, -x, accuracy: 1e-12)
        XCTAssertEqual(angle, theta, accuracy: 1e-9)
    }
}
