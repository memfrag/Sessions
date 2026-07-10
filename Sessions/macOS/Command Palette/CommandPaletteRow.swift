//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A single command row: icon, title/subtitle, and an optional shortcut
/// hint, highlighted when it is the keyboard selection.
struct CommandPaletteRow: View {

    let command: PaletteCommand

    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
            labels
            Spacer()
            shortcut
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var icon: some View {
        Image(systemName: command.systemImage)
            .frame(width: 20)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(command.title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            if let subtitle = command.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
    }

    @ViewBuilder private var shortcut: some View {
        if let hint = command.shortcutHint {
            Text(hint)
                .font(.callout)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
    }
}
