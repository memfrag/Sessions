//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

struct SidebarFooter: View {

    /// Filter text applied to the workspace list above.
    @Binding var filterText: String

    let onNewWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Button {
                    onNewWorkspace()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Workspace")
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Filter", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear Filter")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .padding(8)
        }
        .background(.bar)
    }
}

#Preview {
    SidebarFooter(filterText: .constant("")) {
        // New workspace action.
    }
}
