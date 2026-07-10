//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Sheet for creating a new workspace: a name and a root directory.
struct NewWorkspaceSheet: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(\.dismiss) private var dismiss

    @State private var name: String

    @State private var rootURL: URL?

    @State private var startupCommand = ""

    @State private var colorID: String?

    @State private var isFolderPickerPresented = false

    /// - Parameter initialFolder: pre-selects this directory and seeds the
    ///   name from its last path component (used for folder drops).
    init(initialFolder: URL? = nil) {
        _rootURL = State(initialValue: initialFolder)
        _name = State(initialValue: initialFolder?.lastPathComponent ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && rootURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workspace")
                .font(.headline)
            Form {
                TextField("Name:", text: $name)
                LabeledContent("Directory:") {
                    HStack {
                        Text(rootURL?.path(percentEncoded: false) ?? "No directory selected")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(rootURL == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") {
                            isFolderPickerPresented = true
                        }
                    }
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
                Button("Create") {
                    createWorkspace()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
        .fileImporter(
            isPresented: $isFolderPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                rootURL = url
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = url.lastPathComponent
                }
            }
        }
    }

    private func createWorkspace() {
        guard let rootURL else { return }
        let command = startupCommand.trimmingCharacters(in: .whitespaces)
        model.createWorkspace(
            name: name.trimmingCharacters(in: .whitespaces),
            rootPath: rootURL.path(percentEncoded: false),
            startupCommand: command.isEmpty ? nil : command,
            colorID: colorID
        )
        dismiss()
    }
}
