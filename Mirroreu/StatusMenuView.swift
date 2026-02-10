import SwiftUI

struct StatusMenuView: View {
    let manager: EligibilityManager

    var body: some View {
        if manager.daemonReady {
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
        } else {
            Button("Enable Mirroreu in Login Items") {
                manager.registerAndOpenLoginItems()
            }
        }

        if manager.needsFullDiskAccess {
            Divider()
            Text("Enable Mirroreu in Full Disk Access")
                .foregroundStyle(.orange)
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
