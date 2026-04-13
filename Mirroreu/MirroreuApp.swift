import Sentry
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let eligibilityManager = EligibilityManager()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard eligibilityManager.isEnabled else {
            eligibilityManager.cleanup()
            return .terminateNow
        }
        eligibilityManager.performTerminationCleanup {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct MirroreuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            StatusMenuView(manager: appDelegate.eligibilityManager)
        } label: {
            Image(systemName: "iphone")
                .symbolRenderingMode(.palette)
                .foregroundStyle(appDelegate.eligibilityManager.isEnabled ? .green : .red)
        }
    }
}
