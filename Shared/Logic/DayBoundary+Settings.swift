import Foundation
import TheoCore

extension DayBoundary {
    /// The boundary chosen in Settings ("New day starts at"), 4:00 by default.
    static var current: DayBoundary {
        DayBoundary(startHour: storedStartHour)
    }

    static var storedStartHour: Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Prefs.dayStartHour) == nil { return 4 }
        return defaults.integer(forKey: Prefs.dayStartHour)
    }
}
