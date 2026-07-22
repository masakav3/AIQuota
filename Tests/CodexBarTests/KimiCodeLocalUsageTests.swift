import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct KimiCodeLocalUsageTests {
    @Test
    func `reader aggregates redacted turn usage across sessions into seven local days`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let firstSession = try fixture.addSession("session-one")
        try fixture.appendIndex(sessionDirectory: firstSession)
        try fixture.writeWireRecords(
            to: firstSession,
            agent: "main",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: -1, hour: 23),
                    model: "kimi-code/k3",
                    usage: .init(inputOther: 100, output: 20, cacheRead: 30, cacheCreation: 10)),
                #"{"type":"message","time":0,"content":"must never be parsed","usage":{"output":999999}}"#,
                "not-json",
            ])
        try fixture.writeWireRecords(
            to: firstSession,
            agent: "subagent",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: 0, hour: 9),
                    model: "kimi-code/k3",
                    usage: .init(inputOther: 50, output: 5, cacheRead: 10, cacheCreation: 0)),
            ])

        let secondSession = try fixture.addSession("session-two")
        try fixture.appendIndex(sessionDirectory: secondSession)
        try fixture.writeWireRecords(
            to: secondSession,
            agent: "main",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: 0, hour: 10),
                    model: "kimi-code/k2.5",
                    usage: .init(inputOther: 10, output: 2, cacheRead: 0, cacheCreation: 0)),
                Self.usageRecord(
                    time: fixture.date(dayOffset: -7, hour: 12),
                    model: "outside-window",
                    usage: .init(inputOther: 1000, output: 1000, cacheRead: 1000, cacheCreation: 1000)),
            ])

        let snapshot = try KimiCodeLocalUsageReader.load(
            homeDirectoryURL: fixture.root,
            now: fixture.now,
            calendar: fixture.calendar)

        #expect(snapshot.daily.count == 7)
        #expect(snapshot.daily.map(\.day) == [
            "2026-07-16", "2026-07-17", "2026-07-18", "2026-07-19",
            "2026-07-20", "2026-07-21", "2026-07-22",
        ])
        #expect(snapshot.daily[5].requests == 1)
        #expect(snapshot.daily[5].totalTokens == 160)
        #expect(snapshot.daily[6].requests == 2)
        #expect(snapshot.daily[6].inputOtherTokens == 60)
        #expect(snapshot.daily[6].outputTokens == 7)
        #expect(snapshot.daily[6].cacheReadTokens == 10)
        #expect(snapshot.daily[6].totalTokens == 77)
        #expect(snapshot.last7Days.requests == 3)
        #expect(snapshot.last7Days.totalTokens == 237)
        #expect(snapshot.topModel == "kimi-code/k3")
    }

    @Test
    func `reader deduplicates repeated session index rows and ignores invalid usage values`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let session = try fixture.addSession("repeated-session")
        try fixture.appendIndex(sessionDirectory: session)
        try fixture.appendIndex(sessionDirectory: session)
        try fixture.writeWireRecords(
            to: session,
            agent: "main",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: 0, hour: 8),
                    model: "kimi-code/k3",
                    usage: .init(inputOther: 25, output: 5, cacheRead: 0, cacheCreation: 0)),
                Self.usageRecord(
                    time: fixture.date(dayOffset: 0, hour: 9),
                    model: "invalid",
                    usage: .init(inputOther: -1, output: 5, cacheRead: 0, cacheCreation: 0)),
            ])

        let snapshot = try KimiCodeLocalUsageReader.load(
            homeDirectoryURL: fixture.root,
            now: fixture.now,
            calendar: fixture.calendar)

        #expect(snapshot.currentDay.requests == 1)
        #expect(snapshot.currentDay.totalTokens == 30)
        #expect(snapshot.topModel == "kimi-code/k3")
    }

    @Test
    func `Kimi dashboard exposes local activity without presenting it as quota`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let session = try fixture.addSession("dashboard-session")
        try fixture.appendIndex(sessionDirectory: session)
        try fixture.writeWireRecords(
            to: session,
            agent: "main",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: 0, hour: 8),
                    model: "kimi-code/k3",
                    usage: .init(inputOther: 1000, output: 200, cacheRead: 300, cacheCreation: 100)),
            ])
        let snapshot = try KimiCodeLocalUsageReader.load(
            homeDirectoryURL: fixture.root,
            now: fixture.now,
            calendar: fixture.calendar)

        let dashboard = UsageMenuCardView.Model.kimiCodeLocalUsageDashboard(snapshot)

        #expect(dashboard.accessibilityLabel.contains("local"))
        #expect(dashboard.points.count == 7)
        #expect(dashboard.kpis.map(\.title) == ["Today", "7d tokens", "Requests", "Output"])
        #expect(dashboard.kpis.first?.value == "1.6K")
        #expect(dashboard.detailLines.contains("Top model: k3"))
        #expect(dashboard.detailLines.contains { $0.contains("quota") && $0.contains("not") })
    }

    @Test
    func `aggregate cache preserves history without storing session paths or content`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let session = try fixture.addSession("private-session-name")
        try fixture.appendIndex(sessionDirectory: session)
        try fixture.writeWireRecords(
            to: session,
            agent: "main",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: -1, hour: 8),
                    model: "kimi-code/k3",
                    usage: .init(inputOther: 100, output: 20, cacheRead: 30, cacheCreation: 10)),
            ])
        let cacheURL = fixture.root.appendingPathComponent("cache/kimi-usage.json")

        let first = try KimiCodeLocalUsageCache.loadAndPersist(
            homeDirectoryURL: fixture.root,
            cacheURL: cacheURL,
            now: fixture.now,
            calendar: fixture.calendar)
        try FileManager.default.removeItem(at: session)
        let second = try KimiCodeLocalUsageCache.loadAndPersist(
            homeDirectoryURL: fixture.root,
            cacheURL: cacheURL,
            now: fixture.now,
            calendar: fixture.calendar)

        #expect(first.last7Days.totalTokens == 160)
        #expect(second.last7Days.totalTokens == 160)
        let persisted = try String(contentsOf: cacheURL, encoding: .utf8)
        #expect(!persisted.contains("private-session-name"))
        #expect(!persisted.contains("content"))
    }

    @Test @MainActor
    func `Kimi local activity still publishes when remote quota refresh fails`() async {
        let settings = testSettingsStore(
            suiteName: "KimiCodeLocalUsageTests-refresh-\(UUID().uuidString)",
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.setProviderEnabled(
            provider: .kimi,
            metadata: ProviderDescriptorRegistry.descriptor(for: .kimi).metadata,
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let expected = Self.localUsageSnapshot()
        store._test_kimiCodeLocalUsageLoaderOverride = { expected }
        store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(FixtureError.remoteCredentialExpired), attempts: [])
        }

        await store.refreshProvider(.kimi)

        #expect(store.kimiCodeLocalUsage == expected)
        #expect(store.snapshot(for: .kimi) == nil)
    }

    @Test
    func `unchanged Kimi files reuse the in-memory aggregate fingerprint`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let session = try fixture.addSession("fingerprint-session")
        try fixture.appendIndex(sessionDirectory: session)
        try fixture.writeWireRecords(
            to: session,
            agent: "main",
            lines: [
                Self.usageRecord(
                    time: fixture.date(dayOffset: 0, hour: 8),
                    model: "kimi-code/k3",
                    usage: .init(inputOther: 10, output: 2, cacheRead: 0, cacheCreation: 0)),
            ])
        let cacheURL = fixture.root.appendingPathComponent("cache/kimi-usage.json")
        let first = try KimiCodeLocalUsageCache.loadAndPersistIfChanged(
            homeDirectoryURL: fixture.root,
            cacheURL: cacheURL,
            previousSnapshot: nil,
            previousSourceFingerprint: nil,
            now: fixture.now,
            calendar: fixture.calendar)
        let later = fixture.now.addingTimeInterval(60)

        let second = try KimiCodeLocalUsageCache.loadAndPersistIfChanged(
            homeDirectoryURL: fixture.root,
            cacheURL: cacheURL,
            previousSnapshot: first.snapshot,
            previousSourceFingerprint: first.sourceFingerprint,
            now: later,
            calendar: fixture.calendar)

        #expect(second.sourceFingerprint == first.sourceFingerprint)
        #expect(second.snapshot.updatedAt == first.snapshot.updatedAt)
        #expect(second.snapshot.last7Days.totalTokens == 12)
    }
}

extension KimiCodeLocalUsageTests {
    fileprivate struct Fixture {
        let root: URL
        let now: Date
        let calendar: Calendar

        private var kimiRoot: URL {
            self.root.appendingPathComponent(".kimi-code", isDirectory: true)
        }

        func date(dayOffset: Int, hour: Int) -> Date {
            let day = self.calendar.date(byAdding: .day, value: dayOffset, to: self.now)!
            return self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }

        func addSession(_ name: String) throws -> URL {
            let directory = self.kimiRoot
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        func appendIndex(sessionDirectory: URL) throws {
            let index = self.kimiRoot.appendingPathComponent("session_index.jsonl")
            let line = try #require(String(
                data: JSONSerialization.data(withJSONObject: ["sessionDir": sessionDirectory.path]),
                encoding: .utf8)) + "\n"
            if FileManager.default.fileExists(atPath: index.path) {
                let handle = try FileHandle(forWritingTo: index)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try FileManager.default.createDirectory(
                    at: index.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try Data(line.utf8).write(to: index)
            }
        }

        func writeWireRecords(to session: URL, agent: String, lines: [String]) throws {
            let directory = session
                .appendingPathComponent("agents", isDirectory: true)
                .appendingPathComponent(agent, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let contents = lines.joined(separator: "\n") + "\n"
            try Data(contents.utf8).write(to: directory.appendingPathComponent("wire.jsonl"))
        }
    }

    fileprivate static func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KimiCodeLocalUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 22,
            hour: 12)))
        return Fixture(root: root, now: now, calendar: calendar)
    }

    fileprivate struct UsageValues {
        let inputOther: Int
        let output: Int
        let cacheRead: Int
        let cacheCreation: Int
    }

    fileprivate static func usageRecord(time: Date, model: String, usage: UsageValues) -> String {
        let object: [String: Any] = [
            "type": "usage.record",
            "time": Int(time.timeIntervalSince1970 * 1000),
            "model": model,
            "usageScope": "turn",
            "usage": [
                "inputOther": usage.inputOther,
                "output": usage.output,
                "inputCacheRead": usage.cacheRead,
                "inputCacheCreation": usage.cacheCreation,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }

    fileprivate static func localUsageSnapshot() -> KimiCodeLocalUsageSnapshot {
        KimiCodeLocalUsageSnapshot(
            daily: [
                .init(
                    day: "2026-07-22",
                    requests: 1,
                    inputOtherTokens: 10,
                    outputTokens: 2,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0,
                    modelRequests: ["kimi-code/k3": 1]),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    fileprivate enum FixtureError: Error {
        case remoteCredentialExpired
    }
}
