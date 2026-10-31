import Foundation
import XCTest
import AlignCore
@testable import PostureDetection

final class TiltEstimatorTests: XCTestCase {
    private let axes = HeadAxisConvention.airPodsDefault

    private func estimate(forward: Double, lateral: Double, heading: Double = 0, pitch: Double = 0, roll: Double = 0) -> TiltEstimate {
        let g0 = Pose.gravity(Pose.attitude(forward: 0, lateral: 0, heading: 0, mountPitch: pitch, mountRoll: roll))
        let g = Pose.gravity(Pose.attitude(forward: forward, lateral: lateral, heading: heading, mountPitch: pitch, mountRoll: roll))
        return TiltEstimator.estimate(timestamp: 0, gravity: g, baseline: g0, axes: axes)
    }

    /// Head rotated +20° about forwardAxis in a Z-up world; gravity in the head frame is
    /// q.conjugate.rotate((0,0,-1)). Gravity rotates by -20° about x; the head tilt reads +20°.
    func testSignDerivationForwardRotationGivesPositiveForward() {
        let q = Quaternion(axis: axes.forwardAxis, angleRadians: 20 * Pose.rad)
        let g = q.conjugate.rotate(Vector3(x: 0, y: 0, z: -1))
        let g0 = Vector3(x: 0, y: 0, z: -1)
        let r = TiltEstimator.rotationVector(from: g0, to: g)
        let expected = axes.forwardAxis * (-20 * Pose.rad)
        XCTAssertEqual(r.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(r.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(r.z, expected.z, accuracy: 1e-12)
        let t = TiltEstimator.estimate(timestamp: 0, gravity: g, baseline: g0, axes: axes)
        XCTAssertEqual(t.forwardDegrees, 20, accuracy: 1e-9)
        XCTAssertEqual(t.lateralDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(t.totalDegrees, 20, accuracy: 1e-9)
    }

    /// Pins D-011 (head frame +X right ear, +Y nose, +Z up). Requires the AlignCore change on main.
    func testAirPodsDefaultIsD011WithCrossCheckGravity() {
        XCTAssertEqual(axes.forwardAxis, Vector3(x: -1, y: 0, z: 0))
        XCTAssertEqual(axes.lateralAxis, Vector3(x: 0, y: 1, z: 0))
        let down = axes.forwardAxis.cross(axes.lateralAxis)
        XCTAssertEqual(down.z, -1, accuracy: 1e-12)
        // +20° chin-down → (0, +sin20°, −cos20°); +20° right-ear-down → (+sin20°, 0, −cos20°).
        let gForward = Pose.gravity(forward: 20)
        XCTAssertEqual(gForward.x, 0, accuracy: 1e-12)
        XCTAssertEqual(gForward.y, sin(20 * Pose.rad), accuracy: 1e-12)
        XCTAssertEqual(gForward.z, -cos(20 * Pose.rad), accuracy: 1e-12)
        let gRight = Pose.gravity(forward: 0, lateral: 20)
        XCTAssertEqual(gRight.x, sin(20 * Pose.rad), accuracy: 1e-12)
        XCTAssertEqual(gRight.y, 0, accuracy: 1e-12)
        XCTAssertEqual(gRight.z, -cos(20 * Pose.rad), accuracy: 1e-12)
    }

    func testNonDefaultAxisConventionIsHonoured() {
        let custom = HeadAxisConvention(forwardAxis: Vector3(x: 0, y: 1, z: 0), lateralAxis: Vector3(x: 1, y: 0, z: 0))
        let g0 = Pose.gravity(Pose.attitude(forward: 0, lateral: 0, axes: custom))
        let g = Pose.gravity(Pose.attitude(forward: 17, lateral: -6, axes: custom))
        let t = TiltEstimator.estimate(timestamp: 0, gravity: g, baseline: g0, axes: custom)
        XCTAssertEqual(t.forwardDegrees, 17, accuracy: 1e-9)
        XCTAssertEqual(t.lateralDegrees, -6, accuracy: 1e-9)
    }

    func testPureFlexionAndLateralBendAreRecovered() {
        let cases: [(Double, Double)] = [(20, 0), (-25, 0), (0, 18), (0, -12), (15, 10), (-10, -20)]
        for (forward, lateral) in cases {
            let t = estimate(forward: forward, lateral: lateral)
            XCTAssertEqual(t.forwardDegrees, forward, accuracy: 1e-9, "forward for \(forward),\(lateral)")
            XCTAssertEqual(t.lateralDegrees, lateral, accuracy: 1e-9, "lateral for \(forward),\(lateral)")
            XCTAssertEqual(t.totalDegrees, (forward * forward + lateral * lateral).squareRoot(), accuracy: 1e-9)
        }
    }

    func testHeadingIsExcluded() {
        for heading in [0.0, 37, 90, 180, -135] {
            let t = estimate(forward: 20, lateral: 5, heading: heading)
            XCTAssertEqual(t.forwardDegrees, 20, accuracy: 1e-9)
            XCTAssertEqual(t.lateralDegrees, 5, accuracy: 1e-9)
        }
    }

    func testMountPitchIsCompensatedByBaselinePlaneAxes() {
        let t = estimate(forward: 0, lateral: 20, pitch: 15)
        XCTAssertEqual(t.lateralDegrees, 20, accuracy: 1e-9)
        XCTAssertEqual(t.forwardDegrees, 0, accuracy: 1e-9)
    }

    func testBaselinePlaneAxis() {
        let g0 = Vector3(x: 0, y: 0, z: -1)
        let a = TiltEstimator.baselinePlaneAxis(axes.forwardAxis, baseline: g0)
        XCTAssertEqual(a, axes.forwardAxis)
        let degenerate = TiltEstimator.baselinePlaneAxis(Vector3(x: 0, y: 0, z: 1), baseline: g0)
        XCTAssertEqual(degenerate, Vector3(x: 0, y: 0, z: 1))
    }

    func testRotationVectorParallelAndTinyAngles() {
        let g = Vector3(x: 0, y: 0, z: -1)
        XCTAssertEqual(TiltEstimator.rotationVector(from: g, to: g), .zero)
        let tiny = Vector3(x: 1e-9, y: 0, z: -1).normalized
        let r = TiltEstimator.rotationVector(from: g, to: tiny)
        XCTAssertEqual(abs(r.y), 1e-9, accuracy: 1e-12)
    }

    func testGravityFromAttitudeMatchesPoseModel() {
        let q = Pose.attitude(forward: 12, lateral: -7, heading: 40)
        let g = TiltEstimator.gravity(fromAttitude: q)
        let expected = Pose.gravity(q)
        XCTAssertEqual(g.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(g.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(g.z, expected.z, accuracy: 1e-12)
    }
}
