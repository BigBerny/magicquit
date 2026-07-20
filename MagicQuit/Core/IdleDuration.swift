import Foundation

/// Fixed idle-duration steps offered in Settings: one control, no unit picker.
enum IdleDuration {
    static let stepsInMinutes = [15, 30, 60, 120, 240, 480, 720, 1440, 2880]
    static let defaultMinutes = 480

    static func label(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }

    /// Nearest step for an arbitrary duration; used when migrating 1.x settings.
    static func nearestStep(toMinutes minutes: Int) -> Int {
        stepsInMinutes.min { abs($0 - minutes) < abs($1 - minutes) } ?? defaultMinutes
    }

    static func stepDown(from minutes: Int) -> Int {
        stepsInMinutes.last { $0 < minutes } ?? stepsInMinutes.first ?? minutes
    }

    static func stepUp(from minutes: Int) -> Int {
        stepsInMinutes.first { $0 > minutes } ?? stepsInMinutes.last ?? minutes
    }

    /// "42 min", "3 h", "12 s" — menu countdown display.
    static func shortRemaining(seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600) h" }
        if seconds >= 60 { return "\(seconds / 60) min" }
        return "\(max(seconds, 0)) s"
    }
}
