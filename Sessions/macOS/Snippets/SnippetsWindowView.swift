//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Master/detail snippet manager: a searchable list on the left, an editor
/// on the right. Double-click or Return pastes a snippet into the active
/// terminal (prompting for placeholder values first when needed).
struct SnippetsWindowView: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(AppSettings.self) private var settings

    @Environment(\.openWindow) private var openWindow

    @State private var selection: Snippet.ID?

    @State private var filterText = ""

    /// Window-local fill sheet for placeholder snippets activated here.
    @State private var snippetToFill: Snippet?

    private var isFiltering: Bool {
        !filterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredSnippets: [Snippet] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return settings.snippets }
        return settings.snippets.filter { snippet in
            FuzzyMatch.matches(query: trimmed, in: snippet.title)
                || FuzzyMatch.matches(query: trimmed, in: snippet.content)
        }
    }

    var body: some View {
        NavigationSplitView {
            snippetList
        } detail: {
            detail
        }
        .searchable(text: $filterText, placement: .sidebar, prompt: "Filter Snippets")
        .sheet(item: $snippetToFill) { snippet in
            SnippetFillSheet(snippet: snippet) { text in
                model.pasteFilled(text)
                raiseTerminalWindow()
            }
        }
    }

    // MARK: List

    private var snippetList: some View {
        List(selection: $selection) {
            ForEach(filteredSnippets) { snippet in
                snippetRow(snippet)
                    .tag(snippet.id)
            }
            .onMove { source, destination in
                // Row indices refer to the filtered list; reordering a
                // filtered subset is ill-defined, so disable it then.
                guard !isFiltering else { return }
                moveSnippets(from: source, to: destination)
            }
        }
        .frame(minWidth: 200, idealWidth: 240)
        .onKeyPress(.return) {
            activateSelection()
            return .handled
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            listFooter
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title)
                .lineLimit(1)
                .foregroundStyle(snippet.title.isEmpty ? .secondary : .primary)
            if !snippet.content.isEmpty {
                Text(snippet.content)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // A tap gesture over List row content swallows the List's own
        // click-selection, so drive selection and activation explicitly:
        // single click selects, double click pastes.
        .gesture(
            TapGesture(count: 2).onEnded {
                selection = snippet.id
                activate(snippet)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                selection = snippet.id
            }
        )
        .contextMenu {
            Button("Paste into Terminal") {
                activate(snippet)
            }
            .disabled(model.selectedTerminalController == nil)
            Button("Delete", role: .destructive) {
                delete(snippet)
            }
        }
    }

    private var listFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    addSnippet()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Snippet")
                Spacer()
            }
            .padding(8)
        }
        .background(.bar)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let index = selectedIndex {
            @Bindable var settings = settings
            SnippetEditor(
                snippet: $settings.snippets[index],
                canPaste: model.selectedTerminalController != nil,
                onPaste: { activate(settings.snippets[index]) }
            )
        } else {
            ContentUnavailableView(
                "No Snippet Selected",
                systemImage: "text.append",
                description: Text("Select a snippet to edit, or add one with +.")
            )
        }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return settings.snippets.firstIndex { $0.id == selection }
    }

    // MARK: Actions

    private func activateSelection() {
        guard let selection,
              let snippet = settings.snippets.first(where: { $0.id == selection }) else { return }
        activate(snippet)
    }

    /// Pastes the snippet, prompting for placeholder values first when the
    /// snippet has any (window-local sheet).
    private func activate(_ snippet: Snippet) {
        if snippet.placeholderNames.isEmpty {
            model.useSnippet(snippet)
            raiseTerminalWindow()
        } else {
            snippetToFill = snippet
        }
    }

    private func addSnippet() {
        let snippet = Snippet(title: "New Snippet")
        settings.snippets.append(snippet)
        selection = snippet.id
    }

    private func delete(_ snippet: Snippet) {
        settings.snippets.removeAll { $0.id == snippet.id }
        if selection == snippet.id {
            selection = nil
        }
    }

    private func moveSnippets(from source: IndexSet, to destination: Int) {
        settings.snippets.move(fromOffsets: source, toOffset: destination)
    }

    private func raiseTerminalWindow() {
        openWindow(id: MainWindow.windowID)
    }
}

/// Editor pane for a single snippet.
private struct SnippetEditor: View {

    @Binding var snippet: Snippet

    let canPaste: Bool

    let onPaste: () -> Void

    var body: some View {
        Form {
            Section("Snippet") {
                TextField("Title", text: $snippet.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PlaceholderHighlightingEditor(text: $snippet.content)
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
                if !snippet.placeholderNames.isEmpty {
                    Text("Placeholders: \(snippet.placeholderNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Paste into Terminal") {
                    onPaste()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canPaste)
            }
        }
        .formStyle(.grouped)
    }
}
