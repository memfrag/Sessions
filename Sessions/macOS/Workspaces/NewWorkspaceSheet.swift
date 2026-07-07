//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Sheet for creating a new workspace: a name and a root directory.
struct NewWorkspaceSheet: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    @State private var rootURL: URL?

    @State private var isFolderPickerPresented = false

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
        model.createWorkspace(
            name: name.trimmingCharacters(in: .whitespaces),
            rootPath: rootURL.path(percentEncoded: false)
        )
        dismiss()
    }
}
