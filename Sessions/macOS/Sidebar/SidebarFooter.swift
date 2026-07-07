//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

struct SidebarFooter: View {

    let onNewWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                onNewWorkspace()
            } label: {
                Label("New Workspace", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .background(.bar)
    }
}

#Preview {
    SidebarFooter {
        // New workspace action.
    }
}
