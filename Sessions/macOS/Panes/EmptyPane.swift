//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

struct EmptyPane: View {
    var body: some View {
        Pane {
            VStack {
                Text("No workspace selected")
            }
        }
    }
}

#Preview {
    EmptyPane()
}
