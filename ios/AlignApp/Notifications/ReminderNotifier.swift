import Foundation
import Observation
import UIKit
import UserNotifications
import AlignCore

enum NotificationPermission: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

/// Calm, non-medical reminder copy.
enum ReminderCopy {
    static let title = "Posture reset"
    static let notificationIdentifier = "com.bachnguyennn.align.posture-reminder"

    static func body(for direction: TiltDirection) -> String {
        switch direction {
        case .forward:
            return "Time for a posture reset — lift your head and relax your shoulders."
        case .backward:
            return "Time for a posture reset — bring your head back to level and relax your shoulders."
        case .left, .right:
            return "Time for a posture reset — bring your head back to center and relax your shoulders."
        }
    }
}

/// Delivers posture reminders as local notifications plus a light haptic in the foreground.
@MainActor
@Observable
final class ReminderNotifier {
    private(set) var permission: NotificationPermission = .unknown

    private let presentationDelegate = NotificationPresentationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = presentationDelegate
    }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = ReminderNotifier.map(settings.authorizationStatus)
    }

    /// Asks for alert + sound permission (onboarding / permissions screen).
    func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshPermission()
    }

    /// Posts one reminder now, respecting the user's toggles.
    func deliver(_ reminder: ReminderDecision, settings: AppSettings) {
        guard settings.remindersEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = ReminderCopy.title
        content.body = ReminderCopy.body(for: reminder.direction)
        content.sound = settings.soundEnabled ? UNNotificationSound.default : nil
        content.threadIdentifier = "posture-reminders"

        // A fixed identifier replaces the previous reminder instead of stacking them up.
        // A nil trigger delivers immediately.
        let request = UNNotificationRequest(identifier: ReminderCopy.notificationIdentifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.notifications.error("Scheduling reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if settings.hapticsEnabled, UIApplication.shared.applicationState == .active {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    nonisolated static func map(_ status: UNAuthorizationStatus) -> NotificationPermission {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}

/// Shows reminders as banners while Align is in the foreground. Reads the sound toggle straight
/// from UserDefaults so it does not depend on main-actor state.
final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let settings = AppSettings.load(from: .standard)
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if settings.soundEnabled {
            options.insert(.sound)
        }
        completionHandler(options)
    }
}
