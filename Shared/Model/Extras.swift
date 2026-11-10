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
}
