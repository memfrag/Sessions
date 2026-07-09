//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

/// Sheet for editing a workspace's name, startup command, and color.
/// The root directory is fixed at creation.
struct EditWorkspaceSheet: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(\.dismiss) private var dismiss

    let workspace: Workspace

    @State private var name: String

    @State private var startupCommand: String

    @State private var colorID: String?

    init(workspace: Workspace) {
        self.workspace = workspace
        _name = State(initialValue: workspace.name)
        _startupCommand = State(initialValue: workspace.startupCommand ?? "")
        _colorID = State(initialValue: workspace.colorID)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Workspace")
                .font(.headline)
            Form {
                TextField("Name:", text: $name)
                LabeledContent("Directory:") {
                    Text((workspace.rootPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                TextField("Startup Command:", text: $startupCommand, prompt: Text("Optional"))
                Text("Runs in each new tab of this workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Color:") {
                    WorkspaceColorPicker(colorID: $colorID)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let command = startupCommand.trimmingCharacters(in: .whitespaces)
        model.updateWorkspace(
            id: workspace.id,
            name: name.trimmingCharacters(in: .whitespaces),
            startupCommand: command.isEmpty ? nil : command,
            colorID: colorID
        )
        dismiss()
    }
}
