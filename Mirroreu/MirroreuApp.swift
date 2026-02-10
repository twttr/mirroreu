import SwiftUI

@main
struct MirroreuApp: App {
    @State private var eligibilityManager = EligibilityManager()

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
