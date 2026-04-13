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
@MainActor
final class EligibilityManager {

    var isEnabled = false
    var lastError: String?
    var needsFullDiskAccess = false
    var daemonReady = false

    var onFullDiskAccessNeeded: () -> Void = {}

    private let helperServiceName = "com.twttr.MirroreuHelper"
    private let plistName = "com.twttr.MirroreuHelper.plist"
    private var connection: HelperConnection?
    private var xpcConnection: NSXPCConnection?
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
        statusTimer = nil
        xpcConnection?.invalidate()
        xpcConnection = nil
        connection = nil
    }

    func performTerminationCleanup(completion: @escaping () -> Void) {
        statusTimer?.invalidate()
        statusTimer = nil
        guard isEnabled else {
            xpcConnection?.invalidate()
            xpcConnection = nil
            connection = nil
            completion()
            return
        }
        var completed = false
        let finish: () -> Void = { [weak self] in
            guard !completed else { return }
            completed = true
            self?.isEnabled = false
            self?.xpcConnection?.invalidate()
            self?.xpcConnection = nil
            self?.connection = nil
            completion()
        }
        getHelper()?.disable { _, _ in
            DispatchQueue.main.async { finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { finish() }
    }

    private func startStatusPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.refreshDaemonStatus()
            }
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
        let xpc = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
        xpc.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        xpc.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.connection = nil
                self?.xpcConnection = nil
            }
        }
        xpc.resume()

        let proxy = xpc.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            DispatchQueue.main.async {
                self?.xpcConnection?.invalidate()
                self?.xpcConnection = nil
                self?.connection = nil
            }
        })

        self.xpcConnection = xpc
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
