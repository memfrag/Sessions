//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

struct Authed<Content: View>: View {

    @Environment(AuthService.self) private var authService

    private let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }
    var body: some View {
        contentSelector
    }

    @ViewBuilder private var contentSelector: some View {
        let authState = authService.authState
        switch authState {
        case .notAuthenticated:
            // Could show a login form here, if there is no anonymous login.
            // We will show a spinner until the anonymous auth has happened.
            ProgressView()
        case .authenticatedAnonymously:
            content()
                .environment(\.authState, authState)
        case .authenticatedUser:
            content()
                .environment(\.authState, authState)
        }
    }
}
