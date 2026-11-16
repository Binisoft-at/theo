import Foundation

/// Completing an `@group` or `#tag` while it's typed in the composer: which word is being typed,
/// which groups or tags fit it, and the text a pick puts in its place.
public enum TokenCompletion {
    /// The `@group` or `#tag` word at the end of the text.
    public struct Token: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case group
            case tag
        }

        public let kind: Kind
        /// What's typed after the `@` or `#` ("Wo" for "@Wo", "Work/Ad" for "@Work/Ad"); can be empty.
        public let prefix: String
        /// The whole word, `@` or `#` included.
        public let range: Range<String.Index>

        public init(kind: Kind, prefix: String, range: Range<String.Index>) {
            self.kind = kind
            self.prefix = prefix
            self.range = range
        }
    }

    /// A group that fits what's typed.
    public struct GroupSuggestion: Equatable, Sendable {
        public let id: UUID
        /// Names from the outermost group in, its own last (["Work", "Admin"]).
        public let path: [String]
        /// What replaces the typed word: "@Admin", "@Work/Admin", "@TheoLaunch".
        public let insertion: String

        public init(id: UUID, path: [String], insertion: String) {
            self.id = id
            self.path = path
            self.insertion = insertion
        }
    }

    /// A tag that fits what's typed.
    public struct TagSuggestion: Equatable, Sendable {
        public let tag: String
        /// How many open tasks have it.
        public let count: Int

        public init(tag: String, count: Int) {
            self.tag = tag
            self.count = count
        }

        /// What replaces the typed word: "#invoices".
        public var insertion: String { "#" + tag }
    }

    // MARK: - The word being typed

    /// The last word, while the text still ends inside it (no space typed after it yet) and it
    /// starts with `@` or `#`. A `#` inside a word ("C#", "mail@home") doesn't count, and
    /// neither does a word in the description (after " // "), which isn't read for groups or tags.
    public static func activeToken(in text: String) -> Token? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        if text.range(of: " // ") != nil { return nil }
        let start = text.lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        let word = text[start...]
        guard let sigil = word.first else { return nil }
        let kind: Token.Kind
        switch sigil {
        case "@": kind = .group
        case "#": kind = .tag
        default: return nil
        }
        let prefix = String(word.dropFirst())
        // "@@x" or "#a#b" isn't a group or tag.
        guard !prefix.contains("@"), !prefix.contains("#") else { return nil }
        return Token(kind: kind, prefix: prefix, range: start..<text.endIndex)
    }

    /// The text with the word being typed swapped for `insertion` and a space after it, ready for
    /// the next word. Unchanged when no `@` or `#` word is being typed.
    public static func complete(_ text: String, with insertion: String) -> String {
        guard let token = activeToken(in: text) else { return text }
        var result = text
        result.replaceSubrange(token.range, with: insertion + " ")
        return result
    }

    /// Whether the word being typed already is `insertion` (case and accents aside): "@home" for
    /// "@Home". Return then adds the task instead of completing it.
    public static func isTyped(_ insertion: String, in text: String) -> Bool {
        guard let token = activeToken(in: text) else { return false }
        return fold(String(text[token.range])) == fold(insertion)
    }

    // MARK: - Ranking

    /// Which candidates fit what's typed, best first, as positions in `candidates`. A candidate is
    /// a name or a path ("Work/Admin", "Work › Admin"). Case, accents and spaces don't matter.
    /// Equal to the whole or its last part first, then starting a part or a word, then containing
    /// it; shorter first within each, otherwise in the order given. Nothing typed: all of them,
    /// in the order given.
    public static func ranked(_ candidates: [String], query: String) -> [Int] {
        rankedPaths(candidates.map { pathParts($0) }, query: query)
    }

    /// `ranked` for candidates already split into path parts.
    static func rankedPaths(_ paths: [[String]], query: String) -> [Int] {
        let key = queryParts(query).joined(separator: "/")
        guard !key.isEmpty else {
            // Only slashes (or nothing) typed: everything. Only marks no name has: nothing.
            return query.allSatisfy { $0 == "/" } ? Array(paths.indices) : []
        }
        var scored: [(index: Int, tier: Int, length: Int)] = []
        for (index, path) in paths.enumerated() {
            let parts = path.map { squash($0) }
            let joined = parts.joined(separator: "/")
            guard let fit = tier(path: path, parts: parts, joined: joined, key: key) else { continue }
            scored.append((index: index, tier: fit, length: joined.count))
        }
        scored.sort { lhs, rhs in (lhs.tier, lhs.length, lhs.index) < (rhs.tier, rhs.length, rhs.index) }
        return scored.map { $0.index }
    }

    /// 0 = equal, 1 = starts a part or a word, 2 = contains it, nil = doesn't fit.
    private static func tier(path: [String], parts: [String], joined: String, key: String) -> Int? {
        let isPath = key.contains("/")
        if joined == key { return 0 }
        if !isPath, parts.last == key { return 0 }
        if joined.hasPrefix(key) || joined.contains("/" + key) { return 1 }
        if !isPath, words(of: path).contains(where: { word in word.hasPrefix(key) }) { return 1 }
        if joined.contains(key) { return 2 }
        return nil
    }

    /// "Work/Ad" → ["work", "ad"]; "Work/" → ["work", ""] (what's inside Work).
    static func queryParts(_ query: String) -> [String] {
        var parts = query.split(separator: "/", omittingEmptySubsequences: false).map { squash(String($0)) }
        while parts.count > 1, parts.first == "" {
            parts.removeFirst()
        }
        return parts
    }

    /// "Work › Admin" or "Work/Admin" → ["Work", "Admin"].
    static func pathParts(_ text: String) -> [String] {
        text.split(whereSeparator: { character in character == "/" || character == "›" })
            .map { part in part.trimmingCharacters(in: .whitespaces) }
    }

    /// The words of every part: "Theo Launch" → ["theo", "launch"]; "home-office" → ["home", "office"].
    private static func words(of path: [String]) -> [String] {
        var result: [String] = []
        for part in path {
            let pieces = fold(part).split(whereSeparator: { character in !(character.isLetter || character.isNumber) })
            result += pieces.map { piece in String(piece) }
        }
        return result
    }

    /// Lower case, no accents: "Büro" → "buro".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// `fold`, letters and digits only: "Theo Launch" → "theolaunch".
    static func squash(_ text: String) -> String {
        fold(text).filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Groups

    /// Up to `limit` groups that fit what's typed after the `@` (see `ranked`). Pass them in page
    /// order (each subgroup after its parent): with nothing typed yet that's the order shown.
    /// Pass the same list the parser gets, so a pick files where it says.
    public static func groups(matching query: String, in groups: [QuickParser.GroupRef], limit: Int = 6) -> [GroupSuggestion] {
        let paths = QuickParser.GroupRef.paths(groups)
        let order = rankedPaths(groups.map { paths[$0.id] ?? [$0.name] }, query: query)
        var result: [GroupSuggestion] = []
        for index in order where result.count < limit {
            let group = groups[index]
            guard let word = insertion(for: group.id, in: groups, paths: paths) else { continue }
            result.append(GroupSuggestion(id: group.id, path: paths[group.id] ?? [group.name], insertion: word))
        }
        return result
    }

    /// The `@` word that files into the group: its plain name when no other group has that name
    /// (or it's at the top level), else as much of its path as tells it apart ("@Work/Admin").
    /// Spaces are left out ("@TheoLaunch"). nil when no word finds it (a name without letters).
    public static func insertion(for id: UUID, in groups: [QuickParser.GroupRef]) -> String? {
        insertion(for: id, in: groups, paths: QuickParser.GroupRef.paths(groups))
    }

    static func insertion(for id: UUID, in groups: [QuickParser.GroupRef], paths: [UUID: [String]]) -> String? {
        guard let path = paths[id], !path.isEmpty else { return nil }
        let keys = path.map { squash($0) }
        let others: [[String]] = groups.filter { $0.id != id }.map { other in
            (paths[other.id] ?? [other.name]).map { squash($0) }
        }
        for count in 1...path.count {
            let tail = Array(keys.suffix(count))
            let clash = others.contains { other in other.count >= count && Array(other.suffix(count)) == tail }
            guard !clash || count == path.count else { continue }
            let names = path.suffix(count).map { oneWord($0) }
            let text = names.joined(separator: "/")
            // Only offer what the parser reads back as this very group.
            if QuickParser.matchGroup(text.lowercased(), in: groups)?.id == id { return "@" + text }
        }
        return nil
    }

    /// A name as one word: no spaces, slashes, `@` or `#` ("Theo Launch" → "TheoLaunch").
    static func oneWord(_ name: String) -> String {
        name.filter { !$0.isWhitespace && $0 != "/" && $0 != "@" && $0 != "#" }
    }

    // MARK: - Tags

    /// How many tasks have each tag (a tag twice on one task counts once).
    public static func tagCounts(_ tagLists: [[String]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for tags in tagLists {
            for tag in Set(tags) where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    /// Up to `limit` tags that fit what's typed after the `#` (see `ranked`); with nothing typed
    /// yet the most used first, then A–Z.
    public static func tags(matching query: String, counts: [String: Int], limit: Int = 6) -> [TagSuggestion] {
        let sorted = counts.filter { !$0.key.isEmpty }.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        let names = sorted.map { $0.key }
        return ranked(names, query: query).prefix(limit).map { index in
            TagSuggestion(tag: names[index], count: sorted[index].value)
        }
    }
}
