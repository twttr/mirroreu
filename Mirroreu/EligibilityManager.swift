import Foundation
import AppKit
import ServiceManagement
import os

protocol HelperConnection {
    func enable(reply: @escaping (Bool, String?) -> Void)
    func disable(reply: @escaping (Bool, String?) -> Void)
    func isRunning(reply: @escaping (Bool) -> Void)
}

@Observable
final class EligibilityManager {

    enum DaemonStatus {
        case unknown
        case notRegistered
        case requiresApproval
        case enabled
        case notFound
    }

    var isEnabled = false
    var lastError: String?
    var needsFullDiskAccess = false
    var daemonStatus: DaemonStatus = .unknown

    private let helperServiceName = "com.twttr.MirroreuHelper"
    private let plistName = "com.twttr.MirroreuHelper.plist"
    private var connection: HelperConnection?
    private let logger = Logger(subsystem: "com.twttr.Mirroreu", category: "eligibility")

    convenience init() {
        self.init(connection: nil)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanup()
        }
    }

    init(connection: HelperConnection?) {
        self.connection = connection
        refreshDaemonStatus()
        checkHelperStatus()
    }

    func registerDaemon() {
        let service = SMAppService.daemon(plistName: plistName)
        do {
            try service.register()
        } catch let error as NSError where error.domain == "SMAppServiceErrorDomain" && error.code == 1 {
        } catch {
            lastError = String(localized: "Failed to register daemon: \(error.localizedDescription)")
            logger.error("Failed to register daemon: \(error.localizedDescription)")
        }
        refreshDaemonStatus()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshDaemonStatus() {
        let service = SMAppService.daemon(plistName: plistName)
        let status = service.status

        switch status {
        case .notRegistered:
            daemonStatus = .notRegistered
        case .enabled:
            daemonStatus = .enabled
        case .requiresApproval:
            daemonStatus = .requiresApproval
        case .notFound:
            daemonStatus = .notFound
        @unknown default:
            daemonStatus = .unknown
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func enable() {
        lastError = nil
        needsFullDiskAccess = false
        getHelper()?.enable { [weak self] success, error in
            if success {
                self?.isEnabled = true
                self?.logger.info("Enabled successfully")
            } else if error == HelperErrorCode.permissionDenied {
                self?.needsFullDiskAccess = true
                self?.logger.warning("Enable failed: Full Disk Access required")
            } else {
                self?.lastError = error ?? String(localized: "Failed to enable")
                self?.logger.error("Enable failed: \(error ?? "unknown")")
            }
        }
    }

    func disable() {
        lastError = nil
        getHelper()?.disable { [weak self] success, error in
            if success {
                self?.isEnabled = false
                self?.logger.info("Disabled successfully")
            } else {
                self?.lastError = error ?? String(localized: "Failed to disable")
                self?.logger.error("Disable failed: \(error ?? "unknown")")
            }
        }
    }

    func cleanup() {
        if isEnabled {
            disable()
        }
    }

    private func checkHelperStatus() {
        getHelper()?.isRunning { [weak self] running in
            self?.isEnabled = running
            self?.logger.info("Initial status: \(running ? "enabled" : "disabled")")
        }
    }

    private func getHelper() -> HelperConnection? {
        if let connection {
            return connection
        }
        let xpcConnection = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
        xpcConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        xpcConnection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.connection = nil
            }
        }
        xpcConnection.resume()

        let proxy = xpcConnection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            DispatchQueue.main.async {
                self?.lastError = error.localizedDescription
            }
        })

        let wrapper = XPCHelperWrapper(proxy: proxy)
        connection = wrapper
        return wrapper
    }
}

final class XPCHelperWrapper: HelperConnection {
    private let proxy: Any

    init(proxy: Any) {
        self.proxy = proxy
    }

    func enable(reply: @escaping (Bool, String?) -> Void) {
        (proxy as? HelperProtocol)?.enable { success, error in
            DispatchQueue.main.async { reply(success, error) }
        }
    }

    func disable(reply: @escaping (Bool, String?) -> Void) {
        (proxy as? HelperProtocol)?.disable { success, error in
            DispatchQueue.main.async { reply(success, error) }
        }
    }

    func isRunning(reply: @escaping (Bool) -> Void) {
        (proxy as? HelperProtocol)?.isRunning { running in
            DispatchQueue.main.async { reply(running) }
        }
    }
}
