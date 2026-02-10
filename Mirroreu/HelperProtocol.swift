import Foundation

@objc protocol HelperProtocol {
    func enable(reply: @escaping (Bool, String?) -> Void)
    func disable(reply: @escaping (Bool, String?) -> Void)
    func isRunning(reply: @escaping (Bool) -> Void)
    func checkAccess(reply: @escaping (Bool) -> Void)
}

enum HelperErrorCode {
    static let permissionDenied = "PERMISSION_DENIED"
    static let plistReadFailed = "PLIST_READ_FAILED"
    static let plistWriteFailed = "PLIST_WRITE_FAILED"
}
