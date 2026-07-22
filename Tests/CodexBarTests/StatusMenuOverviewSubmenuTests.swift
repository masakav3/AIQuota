import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func `GLM overview row opens hourly token chart instead of MCP model list`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date()
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        let usage = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: ZaiLimitEntry(
                type: .timeLimit,
                unit: .minutes,
                number: 1,
                usage: 100,
                currentValue: 50,
                remaining: 50,
                percentage: 50,
                usageDetails: [ZaiUsageDetail(modelCode: "glm-4.5", usage: 512)],
                nextResetTime: now.addingTimeInterval(3600)),
            planName: "Pro",
            modelUsage: ZaiModelUsageData(
                xTime: [hourFormatter.string(from: now)],
                modelDataList: [ZaiModelDataItem(modelName: "glm-4.5", tokensUsage: [512])]),
            updatedAt: now)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .zai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let model = try #require(controller.menuCardModel(for: .zai))
        #expect(model.inlineUsageDashboard?.kpis.map(\.title) == [
            "24h tokens",
            "Latest hour",
            "Peak hour",
            "Models",
        ])
        #expect(!AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .zai))
        let submenu = try #require(controller.makeOverviewRowSubmenu(provider: .zai, model: model, width: 320))

        #expect(submenu.items.first?.representedObject as? String == StatusItemController.zaiHourlyUsageChartID)
        #expect(submenu.items.contains { $0.title == "MCP details" } == false)
    }

    @Test
    func `MiniMax overview row exposes billing detail chart submenu`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.showOptionalCreditsAndExtraUsage = true

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let billing = MiniMaxBillingSummary(
            todayTokens: 1234,
            last30DaysTokens: 5678,
            todayCash: 1.5,
            last30DaysCash: 4.25,
            daily: [MiniMaxBillingDay(day: "2023-11-14", tokens: 1234, cash: 1.5)],
            topMethods: [],
            topModels: [MiniMaxBillingBreakdown(name: "MiniMax-M1", tokens: 1234, cash: 1.5)],
            updatedAt: now)
        let usage = MiniMaxUsageSnapshot(
            planName: "Max",
            availablePrompts: 8,
            currentPrompts: 2,
            remainingPrompts: 8,
            windowMinutes: 300,
            usedPercent: 20,
            resetsAt: now.addingTimeInterval(3600),
            updatedAt: now,
            billingSummary: billing)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .minimax)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let model = try #require(controller.menuCardModel(for: .minimax))
        let submenu = try #require(controller.makeOverviewRowSubmenu(provider: .minimax, model: model, width: 320))

        #expect(submenu.items.first?.representedObject as? String == StatusItemController.miniMaxUsageChartID)
    }

    @Test
    func `Kimi overview row exposes local activity only in its detail submenu`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store._setKimiCodeLocalUsageForTesting(Self.kimiCodeLocalUsageSnapshot())
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let model = try #require(controller.menuCardModel(for: .kimi))
        #expect(model.inlineUsageDashboard != nil)
        #expect(!AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .kimi))
        let submenu = try #require(controller.makeOverviewRowSubmenu(provider: .kimi, model: model, width: 320))

        #expect(submenu.items.first?.representedObject as? String == StatusItemController.kimiCodeUsageChartID)
    }

    @Test
    func `overview rows expose provider detail submenus`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .openai
        settings.mergedMenuLastSelectedWasOverview = true
        settings.costUsageEnabled = true
        settings.costSummaryDisplayStyle = .both

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .openai || provider == .codex
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = OpenAIAPIUsageSnapshot(
            daily: [
                OpenAIAPIUsageSnapshot.DailyBucket(
                    day: "2023-11-14",
                    startTime: now,
                    endTime: now.addingTimeInterval(86400),
                    costUSD: 9,
                    requests: 12,
                    inputTokens: 100,
                    cachedInputTokens: 0,
                    outputTokens: 50,
                    totalTokens: 150,
                    lineItems: [],
                    models: []),
            ],
            updatedAt: now)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .openai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let openAIRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-openai"
        })
        #expect(openAIRow.submenu?.items.contains {
            ($0.representedObject as? String) == StatusItemController.costHistoryChartID
        } == true)
    }

    @Test
    func `overview row shows plan usage not cost history for opencodego`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .opencodego
        settings.mergedMenuLastSelectedWasOverview = true
        settings.costUsageEnabled = true
        // Deliberately NOT `.costSubmenu`/`.both`: opencodego has real rate-limit bars (unlike
        // mistral), so its Overview row must fall through to Plan Usage here rather than
        // unconditionally preferring cost history the way mistral's Overview row does.
        settings.costSummaryDisplayStyle = .inlineSummary

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .opencodego || provider == .codex
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let opencodegoSnapshot = OpenCodeGoUsageSnapshot(
            hasMonthlyUsage: true,
            rollingUsagePercent: 12,
            weeklyUsagePercent: 57,
            monthlyUsagePercent: 34,
            rollingResetInSec: 3600,
            weeklyResetInSec: 86400,
            monthlyResetInSec: 864_000,
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2025-12-23",
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    requestCount: 5,
                    costUSD: 1.23,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ],
            updatedAt: Date())
        store._setSnapshotForTesting(opencodegoSnapshot.toUsageSnapshot(), provider: .opencodego)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let opencodegoRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-opencodego"
        })
        #expect(opencodegoRow.submenu?.items.contains {
            ($0.representedObject as? String) == StatusItemController.usageHistoryChartID
        } == true)
        #expect(opencodegoRow.submenu?.items.contains {
            ($0.representedObject as? String) == StatusItemController.costHistoryChartID
        } == false)
    }

    @Test
    func `overview row submenu action does not switch provider detail`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .zai || provider == .claude
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: ZaiLimitEntry(
                type: .timeLimit,
                unit: .minutes,
                number: 1,
                usage: 100,
                currentValue: 50,
                remaining: 50,
                percentage: 50,
                usageDetails: [ZaiUsageDetail(modelCode: "glm-4.5", usage: 512)],
                nextResetTime: now.addingTimeInterval(3600)),
            planName: "Pro",
            modelUsage: ZaiModelUsageData(
                xTime: ["2023-11-14 12:00"],
                modelDataList: [ZaiModelDataItem(modelName: "glm-4.5", tokensUsage: [512])]),
            updatedAt: now)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .zai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let zaiRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-zai"
        })
        #expect(zaiRow.submenu != nil)

        let action = try #require(zaiRow.action)
        let target = try #require(zaiRow.target as? StatusItemController)
        _ = target.perform(action, with: zaiRow)

        #expect(settings.mergedMenuLastSelectedWasOverview)
        #expect(settings.selectedMenuProvider == .claude)
        #expect(menu.items.contains {
            ($0.representedObject as? String) == "overviewRow-zai"
        })
    }

    @Test
    func `selecting overview row defers provider detail rebuild`() async throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .codex || provider == .cursor
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let cursorRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-cursor"
        })
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        let action = try #require(cursorRow.action)
        let target = try #require(cursorRow.target as? StatusItemController)
        _ = target.perform(action, with: cursorRow)

        #expect(settings.mergedMenuLastSelectedWasOverview == false)
        #expect(settings.selectedMenuProvider == .cursor)
        #expect(rebuildCount == 0)
        #expect(menu.items.contains {
            ($0.representedObject as? String)?.hasPrefix("overviewRow-") == true
        })

        for _ in 0..<100 where rebuildCount == 0 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }

        let representedIDs = menu.items.compactMap { $0.representedObject as? String }
        let switcherButtons = (menu.items.first?.view as? ProviderSwitcherView)?.subviews
            .compactMap { $0 as? NSButton } ?? []
        #expect(rebuildCount == 1)
        #expect(representedIDs.contains("menuCard"))
        #expect(representedIDs.contains(where: { $0.hasPrefix("overviewRow-") }) == false)
        #expect(switcherButtons.first(where: { $0.state == .on })?.tag == 2)
    }

    @Test
    func `overview row action close renders selected provider on next open`() async throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .codex || provider == .cursor
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let cursorRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-cursor"
        })
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        let action = try #require(cursorRow.action)
        let target = try #require(cursorRow.target as? StatusItemController)
        _ = target.perform(action, with: cursorRow)
        controller.menuDidClose(menu)

        await Task.yield()
        await Task.yield()
        #expect(rebuildCount == 0)
        #expect(settings.selectedMenuProvider == .cursor)

        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let representedIDs = menu.items.compactMap { $0.representedObject as? String }
        let switcherButtons = (menu.items.first?.view as? ProviderSwitcherView)?.subviews
            .compactMap { $0 as? NSButton } ?? []
        #expect(representedIDs.contains("menuCard"))
        #expect(representedIDs.contains(where: { $0.hasPrefix("overviewRow-") }) == false)
        #expect(switcherButtons.first(where: { $0.state == .on })?.tag == 2)
    }
}

extension StatusMenuTests {
    fileprivate static func kimiCodeLocalUsageSnapshot() -> KimiCodeLocalUsageSnapshot {
        KimiCodeLocalUsageSnapshot(
            daily: [
                .init(
                    day: "2026-07-22",
                    requests: 2,
                    inputOtherTokens: 100,
                    outputTokens: 20,
                    cacheReadTokens: 30,
                    cacheCreationTokens: 10,
                    modelRequests: ["kimi-code/k3": 2]),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
