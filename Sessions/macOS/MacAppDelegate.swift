//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

class MacAppDelegate: NSObject, NSApplicationDelegate {
    
    // Sparkle may show its update-permission prompt before the main window
    // appears. If that prompt is the only open window, closing it would
    // otherwise terminate the app before it has even started.
    static var shouldTerminateAppAfterLastWindowClosed = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.shouldTerminateAppAfterLastWindowClosed
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
