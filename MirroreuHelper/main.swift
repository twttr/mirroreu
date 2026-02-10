import Foundation
import os
import Sentry

let serviceName = "com.twttr.MirroreuHelper"
let plistPath = "/private/var/db/os_eligibility/eligibility.plist"

private let logger = Logger(subsystem: serviceName, category: "service")

struct PlistEntry {
    let keyPath: [String]
    let desiredValue: NSObject
}

let entries = [
    PlistEntry(
        keyPath: ["OS_ELIGIBILITY_DOMAIN_IRON", "os_eligibility_answer_t"],
        desiredValue: NSNumber(value: 4)
    ),
    PlistEntry(
        keyPath: ["OS_ELIGIBILITY_DOMAIN_IRON", "status", "OS_ELIGIBILITY_INPUT_COUNTRY_BILLING"],
        desiredValue: NSNumber(value: 3)
    ),
    PlistEntry(
        keyPath: ["OS_ELIGIBILITY_DOMAIN_IRON", "status", "OS_ELIGIBILITY_INPUT_COUNTRY_LOCATION"],
        desiredValue: NSNumber(value: 3)
    ),
]

final class HelperService: NSObject, HelperProtocol, NSXPCListenerDelegate {

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var safetyTimer: DispatchSourceTimer?
    private var fileDescriptor: Int32 = -1
    private var originalValues: [String: NSObject] = [:]
    private var plistFormat: PropertyListSerialization.PropertyListFormat = .binary
    private let monitorQueue = DispatchQueue(label: "com.twttr.MirroreuHelper.monitor")

    private var isMonitoring: Bool {
        fileWatcher != nil || safetyTimer != nil
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.interruptionHandler = { [weak self] in
            self?.handleClientDisconnect()
        }
        connection.resume()
        return true
    }

    private func handleClientDisconnect() {
        monitorQueue.async { [self] in
            guard isMonitoring else { return }
            logger.info("Client disconnected while monitoring, reverting")
            stopMonitoring()
            if !originalValues.isEmpty {
                revertPlist()
                originalValues = [:]
            }
        }
    }

    func enable(reply: @escaping (Bool, String?) -> Void) {
        monitorQueue.async { [self] in
            if isMonitoring {
                reply(true, nil)
                return
            }

            guard canAccessPlist() else {
                reply(false, HelperErrorCode.permissionDenied)
                return
            }

            guard let plist = readPlist() else {
                reply(false, HelperErrorCode.plistReadFailed)
                return
            }

            for entry in entries {
                let key = entry.keyPath.joined(separator: ":")
                if let value = getValue(from: plist, keyPath: entry.keyPath) as? NSObject {
                    originalValues[key] = value
                }
            }

            guard patchPlist() else {
                originalValues = [:]
                reply(false, HelperErrorCode.plistWriteFailed)
                return
            }

            startMonitoring()
            logger.info("Enabled successfully")
            reply(true, nil)
        }
    }

    func disable(reply: @escaping (Bool, String?) -> Void) {
        monitorQueue.async { [self] in
            stopMonitoring()

            if !originalValues.isEmpty {
                revertPlist()
                originalValues = [:]
            }

            logger.info("Disabled successfully")
            reply(true, nil)
        }
    }

    func isRunning(reply: @escaping (Bool) -> Void) {
        monitorQueue.async { [self] in
            reply(isMonitoring)
        }
    }

    func shutdown() {
        monitorQueue.sync { [self] in
            stopMonitoring()
            if !originalValues.isEmpty {
                revertPlist()
                originalValues = [:]
            }
            logger.info("Shutdown complete")
        }
    }

    private func canAccessPlist() -> Bool {
        (try? Data(contentsOf: URL(fileURLWithPath: plistPath), options: .mappedIfSafe)) != nil
    }

    private func readPlist() -> NSMutableDictionary? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else {
            logger.error("Failed to read plist data")
            return nil
        }
        var format = plistFormat
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: .mutableContainersAndLeaves,
            format: &format
        ) as? NSMutableDictionary else {
            logger.error("Failed to deserialize plist")
            return nil
        }
        plistFormat = format
        return plist
    }

    private func writePlist(_ plist: NSDictionary) -> Bool {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: plistFormat,
            options: 0
        ) else {
            logger.error("Failed to serialize plist")
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: plistPath))
            return true
        } catch {
            logger.error("Failed to write plist: \(error.localizedDescription)")
            return false
        }
    }

    private func getValue(from dict: NSDictionary, keyPath: [String]) -> Any? {
        var current: Any = dict
        for key in keyPath {
            guard let d = current as? NSDictionary, let val = d[key] else { return nil }
            current = val
        }
        return current
    }

    private func setValue(_ value: Any, in dict: NSMutableDictionary, keyPath: [String]) {
        guard !keyPath.isEmpty else { return }
        if keyPath.count == 1 {
            dict[keyPath[0]] = value
            return
        }
        var current: NSMutableDictionary = dict
        for key in keyPath.dropLast() {
            guard let next = current[key] as? NSMutableDictionary else { return }
            current = next
        }
        if let lastKey = keyPath.last {
            current[lastKey] = value
        }
    }

    @discardableResult
    private func patchPlist() -> Bool {
        guard let plist = readPlist() else { return false }

        var needsWrite = false
        for entry in entries {
            let currentValue = getValue(from: plist, keyPath: entry.keyPath) as? NSObject
            if currentValue.map({ $0.isEqual(entry.desiredValue) }) != true {
                setValue(entry.desiredValue, in: plist, keyPath: entry.keyPath)
                needsWrite = true
            }
        }

        if needsWrite {
            logger.debug("Patching plist values")
            return writePlist(plist)
        }
        return true
    }

    private func revertPlist() {
        guard let plist = readPlist() else { return }

        for entry in entries {
            let key = entry.keyPath.joined(separator: ":")
            if let originalValue = originalValues[key] {
                setValue(originalValue, in: plist, keyPath: entry.keyPath)
            }
        }

        if writePlist(plist) {
            logger.info("Reverted plist to original values")
        }
    }

    private func startMonitoring() {
        setupFileWatcher()
        setupSafetyTimer()
    }

    private func stopMonitoring() {
        fileWatcher?.cancel()
        fileWatcher = nil
        safetyTimer?.cancel()
        safetyTimer = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func setupFileWatcher() {
        let fd = open(plistPath, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("Could not open plist for file watching")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: monitorQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                self.restartFileWatcher()
            } else {
                self.patchPlist()
            }
        }
        source.resume()
        fileWatcher = source
    }

    private func restartFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        monitorQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.patchPlist()
            self?.setupFileWatcher()
        }
    }

    private func setupSafetyTimer() {
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.patchPlist()
        }
        timer.resume()
        safetyTimer = timer
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = service
listener.resume()

signal(SIGTERM, SIG_IGN)
signal(SIGHUP, SIG_IGN)

let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigTermSource.setEventHandler {
    logger.info("Received SIGTERM")
    service.shutdown()
    exit(0)
}
sigTermSource.resume()

let sigHupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
sigHupSource.setEventHandler {
    logger.info("Received SIGHUP")
    service.shutdown()
    exit(0)
}
sigHupSource.resume()

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

logger.info("Helper daemon started")
dispatchMain()
