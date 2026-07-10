//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

public struct HelpWindow: Scene {

    public static let windowID = "help"
            
    public var body: some Scene {
        Window("Sessions Help", id: Self.windowID) {
            HelpContent()
                .frame(minWidth: 560, minHeight: 460)
        }
        .commandsRemoved() // Don't show window in Windows menu
        .defaultPosition(.center)
        .defaultSize(width: 680, height: 640)
        .windowResizability(.contentMinSize)
    }
}
