import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct AIQuotaPresentationTests {
    @Test
    func `selects the nearest short window and weekly window`() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 36,
                windowMinutes: 6 * 60,
                resetsAt: now.addingTimeInterval(60 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 58.6,
                windowMinutes: 7 * 24 * 60,
                resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                resetDescription: nil),
            tertiary: RateWindow(
                usedPercent: 41.4,
                windowMinutes: 5 * 60,
                resetsAt: now.addingTimeInterval(60 * 60),
                resetDescription: nil),
            updatedAt: now)

        let presentation = AIQuotaPresentation.make(
            provider: .codex,
            snapshot: snapshot,
            isStale: false)

        #expect(presentation.provider == .codex)
        #expect(presentation.slot1?.label == "5H")
        #expect(presentation.slot1?.usedPercent == 41.4)
        #expect(presentation.slot2?.label == "WEEK")
        #expect(presentation.slot2?.usedPercent == 58.6)
        #expect(!presentation.isStale)
    }

    @Test
    func `fills a missing short window with day before weekly`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 70,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 20,
                windowMinutes: 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: .now)

        let presentation = AIQuotaPresentation.make(
            provider: .claude,
            snapshot: snapshot,
            isStale: false)

        #expect(presentation.slot1?.label == "DAY")
        #expect(presentation.slot1?.usedPercent == 20)
        #expect(presentation.slot2?.label == "WEEK")
        #expect(presentation.slot2?.usedPercent == 70)
    }

    @Test
    func `uses a single monthly window without inventing a second metric`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 43,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: .now)

        let presentation = AIQuotaPresentation.make(
            provider: .zai,
            snapshot: snapshot,
            isStale: false)

        #expect(presentation.slot1?.label == "MONTH")
        #expect(presentation.slot1?.usedPercent == 43)
        #expect(presentation.slot2 == nil)
        #expect(presentation.menuBarPercentText == "43%  --")
    }

    @Test
    func `uses SLOT1 when an unknown duration cannot be inferred`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Resets at an unspecified time"),
            secondary: nil,
            updatedAt: .now)

        let presentation = AIQuotaPresentation.make(
            provider: .zai,
            snapshot: snapshot,
            isStale: false)

        #expect(presentation.slot1?.label == "SLOT1")
        #expect(presentation.slot2 == nil)
    }

    @Test
    func `preserves Kimi weekly semantics when its duration is unknown`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Rate limit"),
            secondary: RateWindow(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: .now)

        let presentation = AIQuotaPresentation.make(
            provider: .kimi,
            snapshot: snapshot,
            isStale: false)

        #expect(presentation.slot1?.label == "5H")
        #expect(presentation.slot1?.usedPercent == 50)
        #expect(presentation.slot2?.label == "WEEK")
        #expect(presentation.slot2?.usedPercent == 25)
    }

    @Test
    func `preserves Kimi monthly named window semantics when duration is unknown`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "kimi-monthly",
                    title: "Monthly",
                    window: RateWindow(
                        usedPercent: 64,
                        windowMinutes: nil,
                        resetsAt: nil,
                        resetDescription: nil)),
            ],
            updatedAt: .now)

        let presentation = AIQuotaPresentation.make(
            provider: .kimi,
            snapshot: snapshot,
            isStale: false)

        #expect(presentation.slot1?.label == "WEEK")
        #expect(presentation.slot1?.usedPercent == 25)
        #expect(presentation.slot2?.label == "MONTH")
        #expect(presentation.slot2?.usedPercent == 64)
    }

    @Test
    func `MiniMax uses only finite primary text quota services`() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let minimax = MiniMaxUsageSnapshot(
            planName: "Max",
            availablePrompts: nil,
            currentPrompts: nil,
            remainingPrompts: nil,
            windowMinutes: nil,
            usedPercent: nil,
            resetsAt: nil,
            updatedAt: now,
            services: [
                MiniMaxServiceUsage(
                    serviceType: "video",
                    windowType: "Today",
                    timeRange: "",
                    usage: 91,
                    limit: 100,
                    percent: 91,
                    resetsAt: nil,
                    resetDescription: "Resets today"),
                MiniMaxServiceUsage(
                    serviceType: "general",
                    windowType: "5 hours",
                    timeRange: "",
                    usage: 21,
                    limit: 100,
                    percent: 21,
                    resetsAt: nil,
                    resetDescription: "Resets in 1 hour"),
                MiniMaxServiceUsage(
                    serviceType: "general",
                    windowType: "Weekly",
                    timeRange: "",
                    usage: 99,
                    limit: 100,
                    percent: 99,
                    isUnlimited: true,
                    resetsAt: nil,
                    resetDescription: "Unlimited"),
                MiniMaxServiceUsage(
                    serviceType: "text-generation",
                    windowType: "Weekly",
                    timeRange: "",
                    usage: 37,
                    limit: 100,
                    percent: 37,
                    resetsAt: nil,
                    resetDescription: "Resets in 6 days"),
            ])

        let presentation = AIQuotaPresentation.make(
            provider: .minimax,
            snapshot: minimax.toUsageSnapshot(),
            isStale: false)

        #expect(presentation.slot1?.label == "5H")
        #expect(presentation.slot1?.usedPercent == 21)
        #expect(presentation.slot2?.label == "WEEK")
        #expect(presentation.slot2?.usedPercent == 37)
    }

    @Test
    func `MiniMax falls back to snapshot windows when no finite text service exists`() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let minimax = MiniMaxUsageSnapshot(
            planName: "Max",
            availablePrompts: nil,
            currentPrompts: nil,
            remainingPrompts: nil,
            windowMinutes: nil,
            usedPercent: nil,
            resetsAt: nil,
            updatedAt: now,
            services: [
                MiniMaxServiceUsage(
                    serviceType: "video",
                    windowType: "Today",
                    timeRange: "",
                    usage: 88,
                    limit: 100,
                    percent: 88,
                    resetsAt: nil,
                    resetDescription: "Resets today"),
            ])

        let presentation = AIQuotaPresentation.make(
            provider: .minimax,
            snapshot: minimax.toUsageSnapshot(),
            isStale: false)

        #expect(presentation.slot1?.label == "DAY")
        #expect(presentation.slot1?.usedPercent == 88)
        #expect(presentation.slot2 == nil)
    }

    @Test
    func `ignores synthetic named windows and clamps percentage`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 140,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            extraRateWindows: [
                NamedRateWindow(
                    id: "synthetic-session",
                    title: "Synthetic session",
                    window: RateWindow(
                        usedPercent: -10,
                        windowMinutes: 5 * 60,
                        resetsAt: nil,
                        resetDescription: nil,
                        isSyntheticPlaceholder: true)),
            ],
            updatedAt: .now)

        let presentation = AIQuotaPresentation.make(
            provider: .claude,
            snapshot: snapshot,
            isStale: true)

        #expect(presentation.slot1?.label == "WEEK")
        #expect(presentation.slot1?.usedPercent == 100)
        #expect(presentation.slot2 == nil)
        #expect(presentation.isStale)
        #expect(presentation.menuBarPercentText == "100%  -- !")
    }

    @Test
    func `rotation follows enabled provider order and survives list changes`() {
        var rotation = AIQuotaRotation(providers: [.codex, .claude])

        #expect(rotation.current == .codex)
        #expect(rotation.advance() == .claude)
        #expect(rotation.advance() == .codex)

        rotation.updateProviders([.claude])
        #expect(rotation.current == .claude)
        #expect(rotation.advance() == .claude)

        rotation.updateProviders([])
        #expect(rotation.current == nil)
    }
}
