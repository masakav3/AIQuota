import Foundation

struct KimiCodeLocalUsageSnapshot: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable {
        let day: String
        var requests: Int
        var inputOtherTokens: Int64
        var outputTokens: Int64
        var cacheReadTokens: Int64
        var cacheCreationTokens: Int64
        var modelRequests: [String: Int]

        var totalTokens: Int64 {
            [self.inputOtherTokens, self.outputTokens, self.cacheReadTokens, self.cacheCreationTokens]
                .reduce(0, KimiCodeLocalUsageSnapshot.saturatingAdd)
        }
    }

    struct Totals: Equatable, Sendable {
        var requests = 0
        var inputOtherTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var cacheReadTokens: Int64 = 0
        var cacheCreationTokens: Int64 = 0

        var totalTokens: Int64 {
            [self.inputOtherTokens, self.outputTokens, self.cacheReadTokens, self.cacheCreationTokens]
                .reduce(0, KimiCodeLocalUsageSnapshot.saturatingAdd)
        }
    }

    let daily: [Day]
    let updatedAt: Date

    var currentDay: Day {
        self.daily.last ?? Day(
            day: "",
            requests: 0,
            inputOtherTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            modelRequests: [:])
    }

    var last7Days: Totals {
        self.daily.reduce(into: Totals()) { result, day in
            result.requests = Self.saturatingAdd(result.requests, day.requests)
            result.inputOtherTokens = Self.saturatingAdd(result.inputOtherTokens, day.inputOtherTokens)
            result.outputTokens = Self.saturatingAdd(result.outputTokens, day.outputTokens)
            result.cacheReadTokens = Self.saturatingAdd(result.cacheReadTokens, day.cacheReadTokens)
            result.cacheCreationTokens = Self.saturatingAdd(result.cacheCreationTokens, day.cacheCreationTokens)
        }
    }

    var topModel: String? {
        let counts = self.daily.reduce(into: [String: Int]()) { result, day in
            for (model, count) in day.modelRequests {
                result[model] = Self.saturatingAdd(result[model, default: 0], count)
            }
        }
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }

    var hasActivity: Bool {
        self.last7Days.requests > 0
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

enum KimiCodeLocalUsageReader {
    private struct SessionIndexRecord: Decodable {
        let sessionDir: String
    }

    private struct WireRecord: Decodable {
        struct Usage: Decodable {
            let inputOther: Int64
            let output: Int64
            let inputCacheRead: Int64
            let inputCacheCreation: Int64
        }

        let type: String
        let time: Int64
        let model: String
        let usageScope: String
        let usage: Usage
    }

    static func load(
        homeDirectoryURL: URL,
        now: Date = Date(),
        calendar: Calendar = .current) throws -> KimiCodeLocalUsageSnapshot
    {
        let kimiRoot = homeDirectoryURL
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .standardizedFileURL
        let indexURL = kimiRoot.appendingPathComponent("session_index.jsonl")
        let days = self.emptyDays(now: now, calendar: calendar)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return KimiCodeLocalUsageSnapshot(daily: days, updatedAt: now)
        }

        let decoder = JSONDecoder()
        let sessionDirectories = try self.sessionDirectories(
            indexURL: indexURL,
            kimiRoot: kimiRoot,
            decoder: decoder)
        let dayFormatter = self.dayFormatter(calendar: calendar)
        let windowStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        var dailyByKey = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })

        for sessionDirectory in sessionDirectories {
            for wireURL in self.wireFiles(in: sessionDirectory, modifiedSince: windowStart) {
                guard let data = try? Data(contentsOf: wireURL) else { continue }
                for line in data.split(separator: 0x0A) {
                    guard let record = try? decoder.decode(WireRecord.self, from: Data(line)),
                          record.type == "usage.record",
                          record.usageScope == "turn",
                          self.isValid(record.usage)
                    else {
                        continue
                    }
                    let date = Date(timeIntervalSince1970: TimeInterval(record.time) / 1000)
                    guard date >= windowStart, date < windowEnd else { continue }
                    let dayKey = dayFormatter.string(from: date)
                    guard var day = dailyByKey[dayKey] else { continue }
                    day.requests = self.saturatingAdd(day.requests, 1)
                    day.inputOtherTokens = self.saturatingAdd(day.inputOtherTokens, record.usage.inputOther)
                    day.outputTokens = self.saturatingAdd(day.outputTokens, record.usage.output)
                    day.cacheReadTokens = self.saturatingAdd(day.cacheReadTokens, record.usage.inputCacheRead)
                    day.cacheCreationTokens = self.saturatingAdd(
                        day.cacheCreationTokens,
                        record.usage.inputCacheCreation)
                    day.modelRequests[record.model] = self.saturatingAdd(
                        day.modelRequests[record.model, default: 0],
                        1)
                    dailyByKey[dayKey] = day
                }
            }
        }

        return KimiCodeLocalUsageSnapshot(
            daily: days.compactMap { dailyByKey[$0.day] },
            updatedAt: now)
    }

    static func sourceFingerprint(
        homeDirectoryURL: URL,
        now: Date = Date(),
        calendar: Calendar = .current) throws -> String
    {
        let kimiRoot = homeDirectoryURL
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .standardizedFileURL
        let indexURL = kimiRoot.appendingPathComponent("session_index.jsonl")
        let dayKey = self.dayFormatter(calendar: calendar).string(from: now)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return "\(dayKey)|missing-index"
        }
        let decoder = JSONDecoder()
        let sessionDirectories = try self.sessionDirectories(
            indexURL: indexURL,
            kimiRoot: kimiRoot,
            decoder: decoder)
        let windowStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
        let wireURLs = sessionDirectories
            .flatMap { self.wireFiles(in: $0, modifiedSince: windowStart) }
            .sorted { $0.path < $1.path }
        return ([dayKey, self.fileFingerprint(indexURL)] + wireURLs.map(self.fileFingerprint))
            .joined(separator: "|")
    }

    private static func sessionDirectories(
        indexURL: URL,
        kimiRoot: URL,
        decoder: JSONDecoder) throws -> [URL]
    {
        let data = try Data(contentsOf: indexURL)
        var unique: [String: URL] = [:]
        for line in data.split(separator: 0x0A) {
            guard let record = try? decoder.decode(SessionIndexRecord.self, from: Data(line)) else { continue }
            let candidate = record.sessionDir.hasPrefix("/")
                ? URL(fileURLWithPath: record.sessionDir, isDirectory: true)
                : kimiRoot.appendingPathComponent(record.sessionDir, isDirectory: true)
            let resolved = candidate.standardizedFileURL
            guard resolved.path == kimiRoot.path || resolved.path.hasPrefix(kimiRoot.path + "/") else { continue }
            unique[resolved.path] = resolved
        }
        return unique.values.sorted { $0.path < $1.path }
    }

    private static func wireFiles(in sessionDirectory: URL, modifiedSince: Date) -> [URL] {
        let agentsDirectory = sessionDirectory.appendingPathComponent("agents", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: agentsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent == "wire.jsonl",
                  let values = try? url.resourceValues(forKeys: [
                      .isRegularFileKey,
                      .contentModificationDateKey,
                  ]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= modifiedSince
            else {
                return nil
            }
            return url
        }.sorted { $0.path < $1.path }
    }

    private static func fileFingerprint(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? -1
        let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate.bitPattern ?? 0
        return "\(url.path):\(size):\(modified)"
    }

    private static func emptyDays(now: Date, calendar: Calendar) -> [KimiCodeLocalUsageSnapshot.Day] {
        let formatter = self.dayFormatter(calendar: calendar)
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return KimiCodeLocalUsageSnapshot.Day(
                day: formatter.string(from: date),
                requests: 0,
                inputOtherTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                modelRequests: [:])
        }
    }

    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func isValid(_ usage: WireRecord.Usage) -> Bool {
        usage.inputOther >= 0 &&
            usage.output >= 0 &&
            usage.inputCacheRead >= 0 &&
            usage.inputCacheCreation >= 0
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

struct KimiCodeLocalUsageLoadResult: Sendable {
    let snapshot: KimiCodeLocalUsageSnapshot
    let sourceFingerprint: String
}

enum KimiCodeLocalUsageCache {
    static func loadAndPersist(
        homeDirectoryURL: URL,
        cacheURL: URL,
        now: Date = Date(),
        calendar: Calendar = .current) throws -> KimiCodeLocalUsageSnapshot
    {
        try self.loadAndPersistIfChanged(
            homeDirectoryURL: homeDirectoryURL,
            cacheURL: cacheURL,
            previousSnapshot: nil,
            previousSourceFingerprint: nil,
            now: now,
            calendar: calendar).snapshot
    }

    static func loadAndPersistIfChanged(
        homeDirectoryURL: URL,
        cacheURL: URL,
        previousSnapshot: KimiCodeLocalUsageSnapshot?,
        previousSourceFingerprint: String?,
        now: Date = Date(),
        calendar: Calendar = .current) throws -> KimiCodeLocalUsageLoadResult
    {
        let sourceFingerprint = try KimiCodeLocalUsageReader.sourceFingerprint(
            homeDirectoryURL: homeDirectoryURL,
            now: now,
            calendar: calendar)
        if sourceFingerprint == previousSourceFingerprint,
           let previousSnapshot
        {
            return KimiCodeLocalUsageLoadResult(
                snapshot: previousSnapshot,
                sourceFingerprint: sourceFingerprint)
        }
        let live = try KimiCodeLocalUsageReader.load(
            homeDirectoryURL: homeDirectoryURL,
            now: now,
            calendar: calendar)
        let cached = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode(KimiCodeLocalUsageSnapshot.self, from: $0) }
        let merged = self.merge(live: live, cached: cached, now: now)
        if let data = try? JSONEncoder().encode(merged) {
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
        return KimiCodeLocalUsageLoadResult(
            snapshot: merged,
            sourceFingerprint: sourceFingerprint)
    }

    private static func merge(
        live: KimiCodeLocalUsageSnapshot,
        cached: KimiCodeLocalUsageSnapshot?,
        now: Date) -> KimiCodeLocalUsageSnapshot
    {
        guard let cached else { return live }
        let cachedByDay = Dictionary(uniqueKeysWithValues: cached.daily.map { ($0.day, $0) })
        let daily = live.daily.map { liveDay in
            guard let cachedDay = cachedByDay[liveDay.day] else { return liveDay }
            var models = liveDay.modelRequests
            for (model, count) in cachedDay.modelRequests {
                models[model] = max(models[model, default: 0], count)
            }
            return KimiCodeLocalUsageSnapshot.Day(
                day: liveDay.day,
                requests: max(liveDay.requests, cachedDay.requests),
                inputOtherTokens: max(liveDay.inputOtherTokens, cachedDay.inputOtherTokens),
                outputTokens: max(liveDay.outputTokens, cachedDay.outputTokens),
                cacheReadTokens: max(liveDay.cacheReadTokens, cachedDay.cacheReadTokens),
                cacheCreationTokens: max(liveDay.cacheCreationTokens, cachedDay.cacheCreationTokens),
                modelRequests: models)
        }
        return KimiCodeLocalUsageSnapshot(daily: daily, updatedAt: now)
    }
}
