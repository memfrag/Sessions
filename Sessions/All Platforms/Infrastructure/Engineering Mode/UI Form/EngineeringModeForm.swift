//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import OSLog
import SettingsUI
import UserDefaultsUI

struct EngineeringModeForm: View {

    enum Destination {
        case userDefaultsBrowser
    }

    #if os(macOS)
    @Environment(WorkspacesModel.self) private var workspacesModel: WorkspacesModel?
    #endif

    var body: some View {
        Form(content: {

            // MARK: - Info

            Section {
                LabelSetting(
                    "Version",
                    systemIcon: "info.circle.fill",
                    info: "\(AppVersion().description)"
                )
            }

            // MARK: - Session Server

#if os(macOS)
            if let model = workspacesModel {
                Section("Session Server") {
                    LabelSetting(
                        "Status",
                        systemIcon: "server.rack",
                        info: String(describing: model.serverManager.status)
                    )
                    ButtonSetting(
                        "Restart Server",
                        systemIcon: "arrow.clockwise.circle.fill"
                    ) {
                        Task {
                            await model.serverManager.client.requestServerRestart()
                        }
                    }
                    ButtonSetting(
                        "Re-register Launch Agent",
                        systemIcon: "gearshape.2.fill"
                    ) {
                        model.serverManager.reregisterAgent()
                    }
                    ButtonSetting(
                        "Stop Server (stays down)",
                        systemIcon: "stop.circle.fill"
                    ) {
                        Task {
                            await model.serverManager.client.requestServerShutdown()
                        }
                    }
                }
            }
#endif

            // MARK: - User Defaults Browser

            Section("User Defaults") {
                PushSetting(
                    "Browse User Defaults",
                    systemIcon: "switch.2",
                    value: Destination.userDefaultsBrowser
                )
            }

            // MARK: - App Paths

#if targetEnvironment(simulator)
            Section("App Paths") {
                ButtonSetting(
                    "Copy App Bundle Path",
                    systemIcon: "folder.fill"
                ) {
                    let path = Bundle.main.bundleURL.path
                    Logger.engineeringMode.trace("👷‍♀️ \(path)")
                    UIPasteboard.general.string = path
                }

                ButtonSetting(
                    "Copy App Container Path",
                    systemIcon: "folder.fill"
                ) {
                    let path = NSHomeDirectory()
                    Logger.engineeringMode.trace("👷‍♀️ \(path)")
                    UIPasteboard.general.string = path
                }
            }
#endif
        })
        .navigationDestination(for: Destination.self) { value in
            switch value {
            case .userDefaultsBrowser:
                UserDefaultsBrowser(hidePrefixes: ["io.apparata."])
            }
        }
    }
}

// MARK: Preview

#Preview {
    EngineeringModeForm()
}
