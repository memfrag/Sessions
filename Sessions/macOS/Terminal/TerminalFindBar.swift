//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Compact find bar overlaid on the terminal. SwiftTerm exposes no match
/// count, so navigation is next/previous with a "not found" indication.
struct TerminalFindBar: View {

    @Bindable var controller: TerminalSessionController

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find", text: $controller.findText)
                .textFieldStyle(.plain)
                .frame(width: 160)
                .focused($isFieldFocused)
                .onSubmit {
                    controller.findNext()
                }
            Toggle("Aa", isOn: $controller.findCaseSensitive)
                .toggleStyle(.button)
                .help("Match Case")
            Toggle(".*", isOn: $controller.findRegex)
                .toggleStyle(.button)
                .help("Regular Expression")
            Button {
                controller.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Find Previous (⇧⌘G)")
            Button {
                controller.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Find Next (⌘G)")
            Button {
                controller.hideFindBar()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Done (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    controller.findFailed ? Color.red.opacity(0.8) : Color.primary.opacity(0.15),
                    lineWidth: 1
                )
        )
        .onExitCommand {
            controller.hideFindBar()
        }
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: controller.isFindBarVisible) { _, visible in
            if visible {
                isFieldFocused = true
            }
        }
        .accessibilityLabel(controller.findFailed ? "Find: not found" : "Find")
    }
}
