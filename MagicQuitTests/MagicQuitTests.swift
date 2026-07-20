import XCTest
@testable import MagicQuit

final class IdleDurationTests: XCTestCase {
    func testStepsAreAscendingAndBounded() {
        XCTAssertEqual(IdleDuration.stepsInMinutes.first, 15)
        XCTAssertEqual(IdleDuration.stepsInMinutes.last, 2880)
        XCTAssertEqual(IdleDuration.stepsInMinutes, IdleDuration.stepsInMinutes.sorted())
        XCTAssertTrue(IdleDuration.stepsInMinutes.contains(IdleDuration.defaultMinutes))
    }

    func testNearestStep() {
        XCTAssertEqual(IdleDuration.nearestStep(toMinutes: 0), 15)
        XCTAssertEqual(IdleDuration.nearestStep(toMinutes: 90), 60)
        XCTAssertEqual(IdleDuration.nearestStep(toMinutes: 500), 480)
        XCTAssertEqual(IdleDuration.nearestStep(toMinutes: 10000), 2880)
        // 8h was the 1.x default and must map exactly
        XCTAssertEqual(IdleDuration.nearestStep(toMinutes: 8 * 60), 480)
    }

    func testStepUpAndDown() {
        XCTAssertEqual(IdleDuration.stepUp(from: 15), 30)
        XCTAssertEqual(IdleDuration.stepDown(from: 30), 15)
        XCTAssertEqual(IdleDuration.stepDown(from: 15), 15)
        XCTAssertEqual(IdleDuration.stepUp(from: 2880), 2880)
        XCTAssertEqual(IdleDuration.stepUp(from: 100), 120)
        XCTAssertEqual(IdleDuration.stepDown(from: 100), 60)
    }

    func testLabels() {
        XCTAssertEqual(IdleDuration.label(minutes: 15), "15 min")
        XCTAssertEqual(IdleDuration.label(minutes: 30), "30 min")
        XCTAssertEqual(IdleDuration.label(minutes: 60), "1 h")
        XCTAssertEqual(IdleDuration.label(minutes: 2880), "48 h")
    }

    func testShortRemaining() {
        XCTAssertEqual(IdleDuration.shortRemaining(seconds: 7200), "2 h")
        XCTAssertEqual(IdleDuration.shortRemaining(seconds: 3599), "59 min")
        XCTAssertEqual(IdleDuration.shortRemaining(seconds: 59), "59 s")
        XCTAssertEqual(IdleDuration.shortRemaining(seconds: -5), "0 s")
    }
}

final class QuitPolicyTests: XCTestCase {
    func testTrackableRegularApp() {
        XCTAssertTrue(QuitPolicy.isTrackable(bundleId: "com.apple.Safari", activationPolicy: .regular, ownBundleId: "com.MagicQuit"))
    }

    func testAccessoryAppsAreNotTracked() {
        XCTAssertFalse(QuitPolicy.isTrackable(bundleId: "com.apple.Safari", activationPolicy: .accessory, ownBundleId: "com.MagicQuit"))
        XCTAssertFalse(QuitPolicy.isTrackable(bundleId: "com.apple.Safari", activationPolicy: .prohibited, ownBundleId: "com.MagicQuit"))
    }

    func testOwnAppIsNotTracked() {
        XCTAssertFalse(QuitPolicy.isTrackable(bundleId: "com.MagicQuit", activationPolicy: .regular, ownBundleId: "com.MagicQuit"))
    }

    func testSystemAppsAreNotTracked() {
        for id in QuitPolicy.systemExcluded {
            XCTAssertFalse(QuitPolicy.isTrackable(bundleId: id, activationPolicy: .regular, ownBundleId: "com.MagicQuit"))
        }
    }

    func testNilBundleIdRegularAppIsTracked() {
        XCTAssertTrue(QuitPolicy.isTrackable(bundleId: nil, activationPolicy: .regular, ownBundleId: "com.MagicQuit"))
    }

    func testRemainingAndDue() {
        let now = Date()
        let lastActive = now.addingTimeInterval(-3600)
        XCTAssertEqual(QuitPolicy.remainingSeconds(lastActive: lastActive, now: now, idleMinutes: 120), 3600)
        XCTAssertFalse(QuitPolicy.idleQuitDue(lastActive: lastActive, now: now, idleMinutes: 120))
        XCTAssertTrue(QuitPolicy.idleQuitDue(lastActive: lastActive, now: now, idleMinutes: 60))
        XCTAssertTrue(QuitPolicy.idleQuitDue(lastActive: lastActive, now: now, idleMinutes: 30))
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "MagicQuitTests.AppSettings"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.idleMinutes, IdleDuration.defaultMinutes)
        XCTAssertFalse(settings.showQuitButton)
        XCTAssertFalse(settings.quitOnLastWindowClosed)
        XCTAssertTrue(settings.idleQuitExcluded.isEmpty)
        XCTAssertEqual(settings.windowQuitExcluded, AppSettings.defaultWindowQuitExcluded)
    }

    func testLegacyHoursMigration() {
        defaults.set(8, forKey: "hoursUntilClose")
        XCTAssertEqual(AppSettings(defaults: defaults).idleMinutes, 480)

        defaults.set(72, forKey: "hoursUntilClose")
        defaults.removeObject(forKey: "idleMinutes")
        XCTAssertEqual(AppSettings(defaults: defaults).idleMinutes, 2880)
    }

    func testExistingIdleMinutesWinsOverLegacyHours() {
        defaults.set(60, forKey: "idleMinutes")
        defaults.set(8, forKey: "hoursUntilClose")
        XCTAssertEqual(AppSettings(defaults: defaults).idleMinutes, 60)
    }

    func testLegacyToggleMigration() throws {
        let legacy = ["Safari": false, "Mail": true]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "com.MagicQuit.toggleStatus")

        let settings = AppSettings(defaults: defaults)
        settings.migrateLegacyToggleIfNeeded(appName: "Safari", bundleId: "com.apple.Safari")
        XCTAssertTrue(settings.idleQuitExcluded.contains("com.apple.Safari"))

        // Enabled legacy entries do not create exclusions
        settings.migrateLegacyToggleIfNeeded(appName: "Mail", bundleId: "com.apple.mail")
        XCTAssertFalse(settings.idleQuitExcluded.contains("com.apple.mail"))

        // Fully consumed legacy storage is removed
        XCTAssertNil(defaults.data(forKey: "com.MagicQuit.toggleStatus"))

        // Consuming again is a no-op
        settings.idleQuitExcluded.remove("com.apple.Safari")
        settings.migrateLegacyToggleIfNeeded(appName: "Safari", bundleId: "com.apple.Safari")
        XCTAssertFalse(settings.idleQuitExcluded.contains("com.apple.Safari"))
    }

    func testExclusionPersistenceRoundtrip() {
        let settings = AppSettings(defaults: defaults)
        settings.idleQuitExcluded.insert("com.apple.Safari")
        settings.windowQuitExcluded.insert("com.example.tool")
        settings.idleMinutes = 120
        settings.quitOnLastWindowClosed = true

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.idleQuitExcluded.contains("com.apple.Safari"))
        XCTAssertTrue(reloaded.windowQuitExcluded.contains("com.example.tool"))
        XCTAssertEqual(reloaded.idleMinutes, 120)
        XCTAssertTrue(reloaded.quitOnLastWindowClosed)
    }

    func testEmptiedWindowExclusionsStayEmpty() {
        let settings = AppSettings(defaults: defaults)
        for id in AppSettings.defaultWindowQuitExcluded {
            settings.windowQuitExcluded.remove(id)
        }
        XCTAssertTrue(AppSettings(defaults: defaults).windowQuitExcluded.isEmpty)
    }
}
