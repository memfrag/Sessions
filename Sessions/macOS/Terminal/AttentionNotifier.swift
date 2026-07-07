//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
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

    /// The bundled attention sound, loaded once. Played directly rather
    /// than via the notification's sound: UNNotificationSound resolution
    /// and macOS's per-app sound caching proved unreliable for a custom
    /// bundled sound, so we own playback and keep the notification silent.
    private static let attentionSound: NSSound? = {
        let url = Bundle.main.bundleURL
            .appending(path: "Contents/Library/Sounds/Attention.caf")
        return NSSound(contentsOf: url, byReference: true)
    }()

    static func post(title: String, body: String) {
        let settings = AppEnvironment.default.appSettings
        guard settings.attentionNotificationsEnabled else { return }
        if settings.attentionNotificationSoundEnabled {
            attentionSound?.stop()
            attentionSound?.play()
        }
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
        // The sound is played by us (above), so the notification is silent.
        content.sound = nil
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
