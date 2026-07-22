import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct AIQuotaProductTests {
    @Test
    func `installs first run defaults without overwriting later choices`() throws {
        let suite = "AIQuotaProductTests-defaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        AIQuotaProduct.installFirstRunDefaults(in: defaults)

        #expect(defaults.string(forKey: "appLanguage") == "zh-Hans")
        #expect(defaults.string(forKey: "refreshFrequency") == RefreshFrequency.oneMinute.rawValue)
        #expect(defaults.bool(forKey: "launchAtLogin"))
        #expect(defaults.bool(forKey: "usageBarsShowUsed"))
        #expect(defaults.bool(forKey: "mergeIcons"))
        #expect(defaults.bool(forKey: "mergedMenuLastSelectedWasOverview"))
        #expect(defaults.bool(forKey: "quotaWarningNotificationsEnabled"))
        #expect(defaults.array(forKey: "quotaWarningThresholds") as? [Int] == [20, 5])
        #expect(defaults.double(forKey: "aiQuotaRotationInterval") == 8)

        defaults.set(15.0, forKey: "aiQuotaRotationInterval")
        AIQuotaProduct.installFirstRunDefaults(in: defaults)
        #expect(defaults.double(forKey: "aiQuotaRotationInterval") == 15)
    }

    @Test
    func `product scope follows the five provider rotation order`() {
        #expect(AIQuotaProduct.providers == [.codex, .claude, .kimi, .minimax, .zai])
        for provider in AIQuotaProduct.providers {
            #expect(AIQuotaProduct.includes(provider))
        }
        #expect(!AIQuotaProduct.includes(.gemini))
        #expect(AIQuotaProduct.orderedEnabledProviders([.zai, .gemini, .codex, .minimax]) == [
            .codex,
            .minimax,
            .zai,
        ])
    }

    @Test
    func `uses GLM only as the AI Quota product name for z ai`() {
        #expect(AIQuotaProduct.displayName(for: .zai) == "GLM")
        #expect(ProviderDescriptorRegistry.descriptor(for: .zai).metadata.displayName == "z.ai")

        for provider in [UsageProvider.codex, .claude, .kimi, .minimax] {
            #expect(AIQuotaProduct.displayName(for: provider) ==
                ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName)
        }
    }

    @Test
    func `uses the GLM brand asset only inside AI Quota`() {
        #expect(AIQuotaProduct.iconResourceName(for: .zai) == "ProviderIcon-glm")
        #expect(AIQuotaProduct.iconResourceName(for: .kimi) == "ProviderIcon-kimi")
        #expect(ProviderDescriptorRegistry.descriptor(for: .zai).branding.iconResourceName == "ProviderIcon-zai")
    }

    @Test
    func `overview hides inline dashboards moved into provider submenus`() {
        #expect(!AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .codex))
        #expect(!AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .claude))
        #expect(!AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .kimi))
        #expect(AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .minimax))
        #expect(!AIQuotaProduct.showsOverviewInlineUsageDashboard(for: .zai))
    }

    @Test
    func `AI Quota about presentation shows product version and author`() {
        let presentation = AboutPanelPresentation.make(
            shortVersion: "0.1.0",
            build: "42",
            isAIQuota: true)

        #expect(AIQuotaProduct.aboutMenuTitle(localizedAbout: "About") == "About AI Quota")
        #expect(presentation.applicationName == "AI Quota")
        #expect(presentation.applicationVersion == "0.1.0 (42)")
        #expect(presentation.author == "matype")
    }

    @Test(arguments: [(0, false), (1, true), (2, true)])
    func `uses one unified status item whenever a provider is enabled`(
        providerCount: Int,
        expected: Bool)
    {
        #expect(AIQuotaProduct.shouldUseUnifiedStatusItem(providerCount: providerCount) == expected)
    }
}
