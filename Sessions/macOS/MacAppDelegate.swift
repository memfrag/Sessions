//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import UserNotifications

class MacAppDelegate: NSObject, NSApplicationDelegate {

    // Sparkle may show its update-permission prompt before the main window
    // appears. If that prompt is the only open window, closing it would
    // otherwise terminate the app before it has even started.
    static var shouldTerminateAppAfterLastWindowClosed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.shouldTerminateAppAfterLastWindowClosed
    }
}

// MARK: - Notification presentation

extension MacAppDelegate: UNUserNotificationCenterDelegate {

    /// macOS suppresses banners for notifications posted while the app is
    /// frontmost — which is exactly when Sessions posts attention alerts.
    /// Returning these presentation options forces the banner (and list
    /// entry) to show anyway.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Sound is played directly by AttentionNotifier, so the notification
        // presentation stays silent.
        completionHandler([.banner, .list])
    }
}

// MARK: - Terminates App When Closed Modifier

extension View {

    /// Marks this view as the main window for the purposes of
    /// `applicationShouldTerminateAfterLastWindowClosed`. Once the view has
    /// appeared at least once, the app is allowed to terminate when the last
    /// window closes.
    func terminatesAppWhenClosed() -> some View {
        onAppear {
            MacAppDelegate.shouldTerminateAppAfterLastWindowClosed = true
        }
    }
}
