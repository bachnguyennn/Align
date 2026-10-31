import Foundation
import XCTest
@testable import AlignCore

/// Component-wise approximate equality for vectors.
func assertVectorEqual(
    _ actual: Vector3,
    _ expected: Vector3,
    accuracy: Double = 1e-12,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "x: \(actual) vs \(expected) \(message)", file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "y: \(actual) vs \(expected) \(message)", file: file, line: line)
    XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, "z: \(actual) vs \(expected) \(message)", file: file, line: line)
}

/// Component-wise approximate equality for quaternions (does NOT treat q and -q as equal).
func assertQuaternionEqual(
    _ actual: Quaternion,
    _ expected: Quaternion,
    accuracy: Double = 1e-12,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "x: \(actual) vs \(expected) \(message)", file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "y: \(actual) vs \(expected) \(message)", file: file, line: line)
    XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, "z: \(actual) vs \(expected) \(message)", file: file, line: line)
    XCTAssertEqual(actual.w, expected.w, accuracy: accuracy, "w: \(actual) vs \(expected) \(message)", file: file, line: line)
}

func negated(_ q: Quaternion) -> Quaternion {
    Quaternion(x: -q.x, y: -q.y, z: -q.z, w: -q.w)
}

enum Fixtures {
    static let xAxis = Vector3(x: 1, y: 0, z: 0)
    static let yAxis = Vector3(x: 0, y: 1, z: 0)
    static let zAxis = Vector3(x: 0, y: 0, z: 1)

    static let vectors: [Vector3] = [
        xAxis,
        yAxis,
        zAxis,
        Vector3(x: 1, y: -2, z: 3),
        Vector3(x: -0.3, y: 0.8, z: -0.5),
        Vector3(x: 0, y: -0.25, z: -0.96875),
    ]

    /// Assorted rotations, including a half turn and an angle above π.
    static let rotations: [Quaternion] = [
        Quaternion(axis: Vector3(x: 1, y: 2, z: 3), angleRadians: 0.7),
        Quaternion(axis: Vector3(x: -0.3, y: 0.1, z: 0.9), angleRadians: 2.5),
        Quaternion(axis: yAxis, angleRadians: -1.2),
        Quaternion(axis: zAxis, angleRadians: Double.pi),
        Quaternion(axis: Vector3(x: 1, y: 1, z: 0), angleRadians: 3 * Double.pi / 2),
    ]
}
