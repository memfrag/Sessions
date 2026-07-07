//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog
import UserNotifications

/// Posts Notification Center alerts for terminal attention events (OSC 9,
/// e.g. Claude Code hooks). Reads the setting at post time so it works
/// even when no window is open. Authorization is requested lazily on the
/// first post after the setting is enabled.
@MainActor
enum AttentionNotifier {

    nonisolated private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "AttentionNotifier")

    private static var didRequestAuthorization = false

    static func post(title: String, body: String) {
        let settings = AppEnvironment.default.appSettings
        guard settings.attentionNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        if !didRequestAuthorization {
            didRequestAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    Self.logger.error("Notification authorization failed: \(error)")
                } else if !granted {
                    Self.logger.info("Notification authorization declined")
                }
            }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = settings.attentionNotificationSoundEnabled ? .default : nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                Self.logger.error("Failed to post notification: \(error)")
            }
        }
    }
}
