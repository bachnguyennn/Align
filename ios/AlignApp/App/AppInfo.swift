import Foundation

/// App and hardware identifiers for About and the diagnostic recording metadata.
enum AppInfo {
    /// "0.1.0 (1)": CFBundleShortVersionString (CFBundleVersion).
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Hardware model identifier such as "iPhone16,1" (never the user-assigned device name).
    /// In the simulator, the identifier of the simulated model.
    static var deviceModelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        let machine = withUnsafeBytes(of: info.machine) { buffer -> String in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }
}
