import Foundation

/// Small synced values that don't need a CloudKit field of their own: a JSON object of strings
/// stored in `extrasRaw` on tasks and groups. A new attribute kept here syncs right away, with no
/// CloudKit schema change and so no "Deploy Schema Changes" before the next TestFlight build.
/// Give it a typed accessor in an extension, e.g.
///
///     var colorTag: String? {
///         get { extras["colorTag"] }
///         set { setExtra("colorTag", newValue) }
///     }
///
/// Not for values the app filters or sorts on in a fetch (predicates can't see inside it), or
/// for anything large. All values share one CloudKit field, so setters write only when their
/// value changes: a needless write could overwrite another device's change to a different key.
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

    /// `raw` with one key set (nil removes it), or nil when the key already has that value.
    static func updating(_ raw: String, key: String, to value: String?) -> String? {
        var values = decode(raw)
        guard values[key] != value else { return nil }
        values[key] = value
        return encode(values)
    }

    static func date(_ text: String?) -> Date? {
        text.flatMap { dateFormatter.date(from: $0) }
    }

    static func text(_ date: Date?) -> String? {
        date.map { dateFormatter.string(from: $0) }
    }
}

extension TaskItem {
    var extras: [String: String] {
        get { Extras.decode(extrasRaw) }
        set { extrasRaw = Extras.encode(newValue) }
    }

    /// Sets one value, writing `extrasRaw` only when it changes.
    func setExtra(_ key: String, _ value: String?) {
        if let raw = Extras.updating(extrasRaw, key: key, to: value) { extrasRaw = raw }
    }

    /// Ongoing ("laufend"): never finished. Checking it off logs a finished copy for that day
    /// (History and the day review count it) and the task itself stays open.
    var isOngoing: Bool {
        get { extras["ongoing"] == "1" }
        set { setExtra("ongoing", newValue ? "1" : nil) }
    }

    /// When an ongoing task was last checked off.
    var lastDoneAt: Date? {
        get { Extras.date(extras["lastDone"]) }
        set { setExtra("lastDone", Extras.text(newValue)) }
    }

    /// On a logged copy: the ongoing task it was logged for.
    var loggedFor: UUID? {
        get { extras["loggedFor"].flatMap(UUID.init(uuidString:)) }
        set { setExtra("loggedFor", newValue?.uuidString) }
    }

    /// The day its current run of plans began: set when it's first planned, kept while it's
    /// carried or moved to another day, cleared when it comes off the plan or is done. The
    /// "carried over" count is the days since then.
    var plannedSince: Date? {
        get { Extras.date(extras["plannedSince"]) }
        set { setExtra("plannedSince", Extras.text(newValue)) }
    }

    /// On a subtask: the parent whose check-off closed it, so reopening the parent reopens it.
    var doneWith: UUID? {
        get { extras["doneWith"].flatMap(UUID.init(uuidString:)) }
        set { setExtra("doneWith", newValue?.uuidString) }
    }

    /// On a finished repeating task: the next occurrence its check-off filed, taken back when
    /// it's reopened before anyone changed that copy.
    var nextCopyID: UUID? {
        get { extras["nextCopy"].flatMap(UUID.init(uuidString:)) }
        set { setExtra("nextCopy", newValue?.uuidString) }
    }

    /// On an ongoing task's log: the deadline the repeat moved on from, restored when the log
    /// is taken back.
    var prevDue: Date? {
        get { Extras.date(extras["prevDue"]) }
        set { setExtra("prevDue", Extras.text(newValue)) }
    }

    /// Monthly and yearly repeats: the day of the month they started on (31 stays 31 after a
    /// shorter month).
    var repeatAnchorDay: Int? {
        get { extras["repeatDay"].flatMap { Int($0) } }
        set { setExtra("repeatDay", newValue.map { String($0) }) }
    }

    /// The group it was in before that group was deleted with "Keep Tasks", so Undo or Restore
    /// can file it back there.
    var formerGroup: UUID? {
        get { extras["formerGroup"].flatMap(UUID.init(uuidString:)) }
        set { setExtra("formerGroup", newValue?.uuidString) }
    }
}

extension TaskGroup {
    /// Sets one value, writing `extrasRaw` only when it changes.
    func setExtra(_ key: String, _ value: String?) {
        if let raw = Extras.updating(extrasRaw, key: key, to: value) { extrasRaw = raw }
    }

    /// The group it sat in before that group was deleted (it moved up a level then), so Undo or
    /// Restore can nest it again.
    var formerParent: UUID? {
        get { extras["formerParent"].flatMap(UUID.init(uuidString:)) }
        set { setExtra("formerParent", newValue?.uuidString) }
    }
}
