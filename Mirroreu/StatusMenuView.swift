import SwiftUI

struct StatusMenuView: View {
    let manager: EligibilityManager

    var body: some View {
        switch manager.daemonStatus {
        case .notRegistered:
            Button("Install Helper") {
                manager.registerDaemon()
            }
        case .requiresApproval:
            Text("Helper needs approval")
            Button("Open System Settings") {
                manager.openSystemSettings()
            }
            Button("Refresh Status") {
                manager.refreshDaemonStatus()
            }
        case .enabled:
            if manager.isEnabled {
                Text("Status: Enabled")
            } else {
                Text("Status: Disabled")
            }

            Divider()

            if manager.isEnabled {
                Button("Disable iPhone Mirroring") {
                    manager.disable()
                }
            } else {
                Button("Enable iPhone Mirroring") {
                    manager.enable()
                }
            }
        case .notFound:
            Text("Helper not found")
            Button("Install Helper") {
                manager.registerDaemon()
            }
            Button("Refresh Status") {
                manager.refreshDaemonStatus()
            }
        case .unknown:
            Text("Checking helper status...")
        }

        if manager.needsFullDiskAccess {
            Divider()
            Text("Helper needs Full Disk Access")
                .foregroundStyle(.orange)
            Button("Open Privacy Settings") {
                manager.openFullDiskAccessSettings()
            }
            Button("Retry") {
                manager.enable()
            }
        }

        if let error = manager.lastError {
            Divider()
            Text("Error: \(error)")
                .foregroundStyle(.red)
        }

        Divider()

        Button("Quit") {
            manager.cleanup()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
