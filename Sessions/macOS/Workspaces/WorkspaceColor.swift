//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Predefined workspace accent colors. Only the ID travels over the wire
/// and into persisted state; rendering is the client's business.
struct WorkspaceColor: Identifiable {

    let id: String

    let name: String

    let color: Color

    static let palette: [WorkspaceColor] = [
        WorkspaceColor(id: "red", name: "Red", color: .red),
        WorkspaceColor(id: "orange", name: "Orange", color: .orange),
        WorkspaceColor(id: "yellow", name: "Yellow", color: .yellow),
        WorkspaceColor(id: "green", name: "Green", color: .green),
        WorkspaceColor(id: "teal", name: "Teal", color: .teal),
        WorkspaceColor(id: "blue", name: "Blue", color: .blue),
        WorkspaceColor(id: "purple", name: "Purple", color: .purple),
        WorkspaceColor(id: "pink", name: "Pink", color: .pink)
    ]

    /// Resolves a stored color ID; nil for no color or an unknown ID
    /// (e.g. from a newer version).
    static func color(forID id: String?) -> Color? {
        guard let id else { return nil }
        return palette.first { $0.id == id }?.color
    }
}

/// Horizontal row of selectable color circles: the palette plus a "none"
/// slot. Plain buttons only.
struct WorkspaceColorPicker: View {

    @Binding var colorID: String?

    var body: some View {
        HStack(spacing: 8) {
            slot(id: nil, fill: AnyShapeStyle(.quaternary), help: "None")
            ForEach(WorkspaceColor.palette) { entry in
                slot(id: entry.id, fill: AnyShapeStyle(entry.color), help: entry.name)
            }
        }
    }

    private func slot(id: String?, fill: AnyShapeStyle, help: String) -> some View {
        Button {
            colorID = id
        } label: {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 16, height: 16)
                if id == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-3)
                    .opacity(colorID == id ? 1 : 0)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
