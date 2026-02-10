import Testing
@testable import Mirroreu

final class MockHelperConnection: HelperConnection {
    var enableResult: (Bool, String?) = (true, nil)
    var disableResult: (Bool, String?) = (true, nil)
    var runningResult = false
    var enableCallCount = 0
    var disableCallCount = 0

    func enable(reply: @escaping (Bool, String?) -> Void) {
        enableCallCount += 1
        reply(enableResult.0, enableResult.1)
    }

    func disable(reply: @escaping (Bool, String?) -> Void) {
        disableCallCount += 1
        reply(disableResult.0, disableResult.1)
    }

    func isRunning(reply: @escaping (Bool) -> Void) {
        reply(runningResult)
    }
}

@Suite("EligibilityManager")
struct EligibilityManagerTests {

    @Test func initialStateIsDisabled() {
        let mock = MockHelperConnection()
        let manager = EligibilityManager(connection: mock)

        #expect(manager.isEnabled == false)
        #expect(manager.lastError == nil)
    }

    @Test func enableSuccess() {
        let mock = MockHelperConnection()
        mock.enableResult = (true, nil)
        let manager = EligibilityManager(connection: mock)

        manager.enable()

        #expect(manager.isEnabled == true)
        #expect(manager.lastError == nil)
        #expect(mock.enableCallCount == 1)
    }

    @Test func enableFailure() {
        let mock = MockHelperConnection()
        mock.enableResult = (false, "Plist not found")
        let manager = EligibilityManager(connection: mock)

        manager.enable()

        #expect(manager.isEnabled == false)
        #expect(manager.lastError == "Plist not found")
    }

    @Test func enableFailureNilError() {
        let mock = MockHelperConnection()
        mock.enableResult = (false, nil)
        let manager = EligibilityManager(connection: mock)

        manager.enable()

        #expect(manager.isEnabled == false)
        #expect(manager.lastError == "Failed to enable")
    }

    @Test func disableSuccess() {
        let mock = MockHelperConnection()
        mock.runningResult = true
        let manager = EligibilityManager(connection: mock)

        #expect(manager.isEnabled == true)

        manager.disable()

        #expect(manager.isEnabled == false)
        #expect(manager.lastError == nil)
        #expect(mock.disableCallCount == 1)
    }

    @Test func disableFailure() {
        let mock = MockHelperConnection()
        mock.runningResult = true
        mock.disableResult = (false, "Permission denied")
        let manager = EligibilityManager(connection: mock)

        manager.disable()

        #expect(manager.lastError == "Permission denied")
    }

    @Test func cleanupWhenEnabled() {
        let mock = MockHelperConnection()
        mock.enableResult = (true, nil)
        let manager = EligibilityManager(connection: mock)

        manager.enable()
        #expect(manager.isEnabled == true)

        manager.cleanup()

        #expect(mock.disableCallCount == 1)
    }

    @Test func cleanupWhenDisabled() {
        let mock = MockHelperConnection()
        let manager = EligibilityManager(connection: mock)

        manager.cleanup()

        #expect(mock.disableCallCount == 0)
    }

    @Test func checksHelperStatusOnInit() {
        let mock = MockHelperConnection()
        mock.runningResult = true
        let manager = EligibilityManager(connection: mock)

        #expect(manager.isEnabled == true)
    }

    @Test func checksHelperStatusOnInitNotRunning() {
        let mock = MockHelperConnection()
        mock.runningResult = false
        let manager = EligibilityManager(connection: mock)

        #expect(manager.isEnabled == false)
    }

    @Test func enableClearsLastError() {
        let mock = MockHelperConnection()
        mock.enableResult = (false, "First error")
        let manager = EligibilityManager(connection: mock)

        manager.enable()
        #expect(manager.lastError == "First error")

        mock.enableResult = (true, nil)
        manager.enable()
        #expect(manager.lastError == nil)
        #expect(manager.isEnabled == true)
    }

    @Test func disableClearsLastError() {
        let mock = MockHelperConnection()
        mock.runningResult = true
        mock.disableResult = (false, "Error")
        let manager = EligibilityManager(connection: mock)

        manager.disable()
        #expect(manager.lastError == "Error")

        mock.disableResult = (true, nil)
        manager.disable()
        #expect(manager.lastError == nil)
    }

    @Test func enableSetsNeedsFullDiskAccess() {
        let mock = MockHelperConnection()
        mock.enableResult = (false, HelperErrorCode.permissionDenied)
        let manager = EligibilityManager(connection: mock)

        manager.enable()

        #expect(manager.needsFullDiskAccess == true)
        #expect(manager.isEnabled == false)
        #expect(manager.lastError == nil)
    }

    @Test func enableClearsNeedsFullDiskAccess() {
        let mock = MockHelperConnection()
        mock.enableResult = (false, HelperErrorCode.permissionDenied)
        let manager = EligibilityManager(connection: mock)

        manager.enable()
        #expect(manager.needsFullDiskAccess == true)

        mock.enableResult = (true, nil)
        manager.enable()
        #expect(manager.needsFullDiskAccess == false)
        #expect(manager.isEnabled == true)
    }
}
