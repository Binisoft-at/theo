import Foundation

/// Small synced values that don't need a CloudKit field of their own: a JSON object of strings
/// stored in `extrasRaw` on tasks and groups. A new attribute kept here syncs right away, with no
/// CloudKit schema change and so no "Deploy Schema Changes" before the next TestFlight build.
/// Give it a typed accessor in an extension, e.g.
///
///     var colorTag: String? {
///         get { extras["colorTag"] }
///         set { extras["colorTag"] = newValue }
///     }
///
/// Not for values the app filters or sorts on in a fetch (predicates can't see inside it), or
/// for anything large.
enum Extras {
    nonisolated(unsafe) static let dateFormatter = ISO8601DateFormatter()

    static func decode(_ raw: String) -> [String: String] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }

    static func encode(_ values: [String: String]) -> String {
        guard !values.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(values) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension TaskItem {
    var extras: [String: String] {
        get { Extras.decode(extrasRaw) }
        set { extrasRaw = Extras.encode(newValue) }
    }

    /// Ongoing ("laufend"): never finished. Checking it off logs a finished copy for that day
    /// (History and the day review count it) and the task itself stays open.
    var isOngoing: Bool {
        get { extras["ongoing"] == "1" }
        set { extras["ongoing"] = newValue ? "1" : nil }
    }

    /// When an ongoing task was last checked off.
    var lastDoneAt: Date? {
        get { extras["lastDone"].flatMap { Extras.dateFormatter.date(from: $0) } }
        set { extras["lastDone"] = newValue.map { Extras.dateFormatter.string(from: $0) } }
    }

    /// On a logged copy: the ongoing task it was logged for.
    var loggedFor: UUID? {
        get { extras["loggedFor"].flatMap(UUID.init(uuidString:)) }
        set { extras["loggedFor"] = newValue?.uuidString }
    }
}
