import Sentry
import SwiftUI

@main
struct MirroreuApp: App {
    @State private var eligibilityManager = EligibilityManager()

    init() {
        if let dsn = Bundle.main.infoDictionary?["SentryDSN"] as? String,
           !dsn.isEmpty,
           !dsn.hasPrefix("$(") {
            SentrySDK.start { options in
                options.dsn = dsn
                #if DEBUG
                options.enabled = false
                #endif
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(manager: eligibilityManager)
        } label: {
            Image(systemName: "iphone")
                .symbolRenderingMode(.palette)
                .foregroundStyle(eligibilityManager.isEnabled ? .green : .red)
        }
    }
}
