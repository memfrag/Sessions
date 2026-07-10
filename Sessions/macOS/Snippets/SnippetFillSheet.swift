//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Prompts for each `{{placeholder}}` value in a snippet, then pastes the
/// substituted text via `onPaste`. Hosted independently by the snippets
/// window and the main window (command-palette path).
struct SnippetFillSheet: View {

    @Environment(\.dismiss) private var dismiss

    let snippet: Snippet

    let onPaste: (String) -> Void

    @State private var values: [String: String] = [:]

    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fill in “\(snippet.title.isEmpty ? "Snippet" : snippet.title)”")
                .font(.headline)
            Form {
                ForEach(snippet.placeholders) { placeholder in
                    TextField(placeholder.name, text: binding(for: placeholder.name))
                        .focused($focusedField, equals: placeholder.name)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Paste") {
                    paste()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            // Pre-fill each field with its default, then focus the first.
            for placeholder in snippet.placeholders where values[placeholder.name] == nil {
                values[placeholder.name] = placeholder.defaultValue ?? ""
            }
            focusedField = snippet.placeholders.first?.name
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding {
            values[name] ?? ""
        } set: { newValue in
            values[name] = newValue
        }
    }

    private func paste() {
        onPaste(Snippet.fill(snippet.content, with: values))
        dismiss()
    }
}
