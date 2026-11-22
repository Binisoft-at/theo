import Foundation

/// Writes Theo's exchange files (format v1, `ExchangeFormat.swift`) into `appFolder` = `<group>/Theo`:
/// one complete file per day and `source.json`. Foundation only, so it's tested on Linux with a
/// temporary folder.
public enum ThaliaExchangeWriter {
    /// `facts`: every fact of the last `BinisoftExchange.keepDays` days from Theo's own synced store,
    /// by day ("2026-11-22"). Writes only the days whose facts changed (a day that had a file and has
    /// nothing now gets `"facts":[]`, a day that never had anything gets no file) and removes day
    /// files older than `keepDays`. Returns whether anything changed.
    @discardableResult
    public static func sync(_ facts: [String: [ExchangeFact]], source: String, appFolder: URL, today: String,
                            now: Date = Date(), timeZone: TimeZone = .current) throws -> Bool {
        let manager = FileManager.default
        var changed = false
        for offset in 0...BinisoftExchange.keepDays {
            guard let day = BinisoftExchange.day(today, adding: -offset) else { continue }
            let url = BinisoftExchange.dayFileURL(appFolder: appFolder, day: day)
            let sorted = TheoExchange.ordered(facts[day] ?? [])
            let old = try? Data(contentsOf: url)
            // Never a file for a day without anything.
            if old == nil && sorted.isEmpty { continue }
            // Unchanged: the file (and its generatedAt) stays as it is.
            if let old, case .success(let read) = ExchangeReader.dayFile(old),
               let same = try? ExchangeDayFile(source: source, day: day, generatedAt: read.file.generatedAt,
                                               facts: sorted).encoded(),
               same == old { continue }
            let file = ExchangeDayFile(source: source, day: day, generatedAt: ExchangeDate.string(now, timeZone: timeZone),
                                       facts: sorted)
            try BinisoftExchange.write(file.encoded(), to: url)
            changed = true
        }
        let days = BinisoftExchange.daysFolder(appFolder: appFolder)
        let names = (try? manager.contentsOfDirectory(atPath: days.path)) ?? []
        for name in BinisoftExchange.expiredDayFiles(names, today: today) {
            try? manager.removeItem(at: days.appendingPathComponent(name))
            changed = true
        }
        return changed
    }

    /// Writes `source.json` right away when its refs, app name or version changed, otherwise at most
    /// once a day (the heartbeat Thalia shows as "last seen"). Returns whether it was written.
    @discardableResult
    public static func writeSource(refs: [ExchangeRef], appVersion: String?, source: String, app: String,
                                   appFolder: URL, now: Date = Date(), timeZone: TimeZone = .current) throws -> Bool {
        let url = sourceURL(appFolder: appFolder)
        if let old = try? Data(contentsOf: url), case .success(let info) = ExchangeReader.source(old),
           info.source == source, info.app == app, info.appVersion == appVersion, info.refs == refs,
           let written = info.generatedDate,
           ExchangeDate.day(written, timeZone: timeZone) == ExchangeDate.day(now, timeZone: timeZone) {
            return false
        }
        let info = ExchangeSourceInfo(source: source, app: app, appVersion: appVersion,
                                      generatedAt: ExchangeDate.string(now, timeZone: timeZone), refs: refs)
        try BinisoftExchange.write(BinisoftExchange.encode(info), to: url)
        return true
    }

    /// `<app folder>/exchange/source.json`
    public static func sourceURL(appFolder: URL) -> URL {
        BinisoftExchange.exchangeFolder(appFolder: appFolder).appendingPathComponent(BinisoftExchange.sourceFileName)
    }

    /// Thalia's `catalog.json` next to Theo's folder (`<group>/Thalia/exchange/catalog.json`); nil while
    /// Thalia hasn't written one on this device or it can't be read.
    public static func catalog(appFolder: URL) -> ExchangeCatalog? {
        let thalia = appFolder.deletingLastPathComponent().appendingPathComponent("Thalia", isDirectory: true)
        let url = BinisoftExchange.exchangeFolder(appFolder: thalia).appendingPathComponent(BinisoftExchange.catalogFileName)
        guard let data = try? Data(contentsOf: url), case .success(let catalog) = ExchangeReader.catalog(data) else { return nil }
        return catalog
    }
}
