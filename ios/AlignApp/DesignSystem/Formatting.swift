import Foundation
import AlignCore
import Sensors

/// Text formatting shared by screens and VoiceOver. Pure functions, unit-tested.
enum Format {
    /// "45 s", "12 min", "1 h", "1 h 5 min".
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total) s"
        }
        let minutes = total / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    /// Spoken form for VoiceOver: "1 hour 5 minutes".
    static func spokenDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return plural(total, "second")
        }
        let minutes = total / 60
        if minutes < 60 {
            return plural(minutes, "minute")
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? plural(hours, "hour") : "\(plural(hours, "hour")) \(plural(remainder, "minute"))"
    }

    /// Whole degrees with sign dropped: "18°".
    static func degrees(_ value: Double) -> String {
        "\(Int(abs(value).rounded()))°"
    }

    /// Signed degrees for diagnostics: "+18.2°".
    static func signedDegrees(_ value: Double) -> String {
        String(format: "%+.1f°", value)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// Visible tilt summary, e.g. "18° forward · 2° right" or "Level".
    static func tiltSummary(forward: Double, lateral: Double) -> String {
        var parts: [String] = []
        if abs(forward) >= 1 {
            parts.append("\(degrees(forward)) \(forward > 0 ? "forward" : "back")")
        }
        if abs(lateral) >= 1 {
            parts.append("\(degrees(lateral)) \(lateral > 0 ? "right" : "left")")
        }
        return parts.isEmpty ? "Level" : parts.joined(separator: " · ")
    }

    /// VoiceOver tilt description, e.g. "Head tilted 18 degrees forward and 2 degrees to the right".
    static func spokenTilt(forward: Double, lateral: Double) -> String {
        var parts: [String] = []
        let f = Int(abs(forward).rounded())
        let l = Int(abs(lateral).rounded())
        if f >= 1 {
            parts.append("\(plural(f, "degree")) \(forward > 0 ? "forward" : "back")")
        }
        if l >= 1 {
            parts.append("\(plural(l, "degree")) to the \(lateral > 0 ? "right" : "left")")
        }
        if parts.isEmpty {
            return "Head level with your neutral position"
        }
        return "Head tilted " + parts.joined(separator: " and ")
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
    }
}

extension TiltDirection {
    /// "forward", "back", "to the left", "to the right".
    var phrase: String {
        switch self {
        case .forward: return "forward"
        case .backward: return "back"
        case .left: return "to the left"
        case .right: return "to the right"
        }
    }

    var title: String {
        switch self {
        case .forward: return "Forward"
        case .backward: return "Back"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

extension PostureState {
    var title: String {
        switch self {
        case .unavailable:
            return "No sensor data"
        case .needsCalibration:
            return "Calibration needed"
        case .calibrating:
            return "Calibrating"
        case .neutral:
            return "Within your range"
        case .deviating(let direction, _):
            return "Tilting \(direction.phrase)"
        case .sustainedTilt(let direction, _):
            return "Tilted \(direction.phrase) for a while"
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable:
            return "antenna.radiowaves.left.and.right.slash"
        case .needsCalibration:
            return "scope"
        case .calibrating:
            return "hourglass"
        case .neutral:
            return "checkmark.circle.fill"
        case .deviating:
            return "arrow.down.right.circle"
        case .sustainedTilt:
            return "exclamationmark.circle.fill"
        }
    }
}

extension SensorConnectionState {
    var title: String {
        switch self {
        case .idle:
            return "Sensor off"
        case .unavailable(.motionNotSupported):
            return "Headphone motion not available"
        case .unavailable(.notAuthorized):
            return "Motion access is off"
        case .waitingForHeadphones:
            return "Waiting for AirPods"
        case .connected:
            return "AirPods connected"
        case .failed:
            return "Sensor error"
        }
    }

    var detail: String? {
        switch self {
        case .idle:
            return nil
        case .unavailable(.motionNotSupported):
            return "This iPhone or iOS version can't read headphone motion."
        case .unavailable(.notAuthorized):
            return "Allow Motion & Fitness access for Align in Settings."
        case .waitingForHeadphones:
            return "Put in both AirPods and make sure they're connected to this iPhone."
        case .connected:
            return nil
        case .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "airpodspro"
        case .unavailable:
            return "xmark.circle"
        case .waitingForHeadphones:
            return "hourglass"
        case .connected:
            return "airpodspro"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var isConnected: Bool {
        self == .connected
    }
}

extension SensorAuthorization {
    var title: String {
        switch self {
        case .notDetermined: return "Not requested yet"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        }
    }
}

extension CalibrationFailure {
    var message: String {
        switch self {
        case .tooMuchMovement:
            return "Your head moved a little too much. Rest comfortably, look straight ahead and try again."
        case .insufficientSamples:
            return "Not enough motion data arrived. Check that both AirPods are in and connected, then try again."
        case .sensorInterrupted:
            return "The AirPods connection was interrupted. Reconnect them and try again."
        }
    }
}

extension MockScenario {
    /// "gradualForwardSlouch" → "Gradual forward slouch".
    var displayName: String {
        var words = ""
        for character in rawValue {
            if character.isUppercase {
                words += " " + character.lowercased()
            } else {
                words.append(character)
            }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
