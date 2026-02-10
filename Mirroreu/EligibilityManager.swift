import Foundation
import AppKit
import ServiceManagement
import os

protocol HelperConnection {
    func enable(reply: @escaping (Bool, String?) -> Void)
    func disable(reply: @escaping (Bool, String?) -> Void)
    func isRunning(reply: @escaping (Bool) -> Void)
    func checkAccess(reply: @escaping (Bool) -> Void)
}

@Observable
final class EligibilityManager {

    var isEnabled = false
    var lastError: String?
    var needsFullDiskAccess = false
    var daemonReady = false

    var onFullDiskAccessNeeded: () -> Void = {}

    private let helperServiceName = "com.twttr.MirroreuHelper"
    private let plistName = "com.twttr.MirroreuHelper.plist"
    private var connection: HelperConnection?
    private let logger = Logger(subsystem: "com.twttr.Mirroreu", category: "eligibility")
    private var statusTimer: Timer?
    private var helperResponded = false

    convenience init() {
        self.init(connection: nil)
        onFullDiskAccessNeeded = {
            DispatchQueue.main.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"]
                try? process.run()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanup()
        }
        startStatusPolling()
    }

    init(connection: HelperConnection?) {
        self.connection = connection
        self.helperResponded = connection != nil
        refreshDaemonStatus()
        if connection != nil {
            checkHelperStatus()
        }
    }

    func registerAndOpenLoginItems() {
        let service = SMAppService.daemon(plistName: plistName)
        do {
            try service.register()
        } catch let error as NSError where error.domain == "SMAppServiceErrorDomain" && error.code == 1 {
        } catch {
            lastError = String(localized: "Failed to register daemon: \(error.localizedDescription)")
            logger.error("Failed to register daemon: \(error.localizedDescription)")
        }
        SMAppService.openSystemSettingsLoginItems()
        refreshDaemonStatus()
    }

    func refreshDaemonStatus() {
        let service = SMAppService.daemon(plistName: plistName)
        daemonReady = service.status == .enabled

        if daemonReady && !helperResponded {
            connection = nil
            checkHelperStatus()
        }

        if daemonReady && helperResponded {
            statusTimer?.invalidate()
            statusTimer = nil
        }
    }

    func enable() {
        lastError = nil
        needsFullDiskAccess = false
        getHelper()?.enable { [weak self] success, error in
            if success {
                self?.isEnabled = true
            } else if error == HelperErrorCode.permissionDenied {
                self?.needsFullDiskAccess = true
                self?.onFullDiskAccessNeeded()
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
            } else {
                self?.lastError = error ?? String(localized: "Failed to disable")
                self?.logger.error("Disable failed: \(error ?? "unknown")")
            }
        }
    }

    func cleanup() {
        statusTimer?.invalidate()
        if isEnabled {
            disable()
        }
    }

    private func startStatusPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDaemonStatus()
        }
    }

    private func checkHelperStatus() {
        getHelper()?.isRunning { [weak self] running in
            self?.helperResponded = true
            self?.isEnabled = running
            self?.checkHelperAccess()
        }
    }

    private func checkHelperAccess() {
        getHelper()?.checkAccess { [weak self] hasAccess in
            if !hasAccess {
                self?.needsFullDiskAccess = true
                self?.onFullDiskAccessNeeded()
            }
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

        let proxy = xpcConnection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            DispatchQueue.main.async {
                self?.connection = nil
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

    func checkAccess(reply: @escaping (Bool) -> Void) {
        (proxy as? HelperProtocol)?.checkAccess { hasAccess in
            DispatchQueue.main.async { reply(hasAccess) }
        }
    }
}
