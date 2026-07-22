import CodexBarCore
import Foundation

struct AIQuotaProviderVisualStyle: Equatable {
    let progressColor: ProviderColor
    let warningMarkerColors: [ProviderColor]
    let menuBarIconTint: ProviderColor?
    let menuBarSystemSymbolName: String?
}

enum AIQuotaProduct {
    nonisolated static let isActive: Bool = {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil ||
            environment["TESTING_LIBRARY_VERSION"] != nil ||
            environment["SWIFT_TESTING"] != nil ||
            NSClassFromString("XCTestCase") != nil
        return !isRunningTests
    }()

    static let productName = "AI Quota"
    static let bundleIdentifier = "com.matype.aiquota"
    static let providers: [UsageProvider] = [.codex, .claude, .kimi, .minimax, .zai]
    static let defaultRotationInterval: TimeInterval = 8

    private static let defaultsVersionKey = "aiQuotaDefaultsVersion"
    private static let defaultsVersion = 1

    static func includes(_ provider: UsageProvider) -> Bool {
        self.providers.contains(provider)
    }

    static func orderedEnabledProviders(_ enabledProviders: [UsageProvider]) -> [UsageProvider] {
        let enabled = Set(enabledProviders)
        return self.providers.filter(enabled.contains)
    }

    static func displayName(for provider: UsageProvider) -> String {
        if provider == .zai {
            return "GLM"
        }
        return ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    static func iconResourceName(for provider: UsageProvider) -> String {
        if provider == .zai {
            return "ProviderIcon-glm"
        }
        return ProviderDescriptorRegistry.descriptor(for: provider).branding.iconResourceName
    }

    static func showsOverviewInlineUsageDashboard(for provider: UsageProvider) -> Bool {
        provider != .codex && provider != .claude && provider != .kimi && provider != .zai
    }

    static func aboutMenuTitle(localizedAbout: String) -> String {
        "\(localizedAbout) \(self.productName)"
    }

    static func visualStyle(for provider: UsageProvider) -> AIQuotaProviderVisualStyle? {
        switch provider {
        case .zai:
            AIQuotaProviderVisualStyle(
                progressColor: ProviderColor(hex: 0x111111),
                warningMarkerColors: [ProviderColor(hex: 0xFF453A), ProviderColor(hex: 0xFFFFFF)],
                menuBarIconTint: nil,
                menuBarSystemSymbolName: nil)
        case .minimax:
            AIQuotaProviderVisualStyle(
                progressColor: ProviderColor(hex: 0xEF473A),
                warningMarkerColors: [ProviderColor(hex: 0xF2B84B)],
                menuBarIconTint: nil,
                menuBarSystemSymbolName: nil)
        case .kimi:
            AIQuotaProviderVisualStyle(
                progressColor: ProviderColor(hex: 0x173B72),
                warningMarkerColors: [],
                menuBarIconTint: ProviderColor(hex: 0xD4A017),
                menuBarSystemSymbolName: "moon.fill")
        default:
            nil
        }
    }

    static func shouldUseUnifiedStatusItem(providerCount: Int) -> Bool {
        providerCount > 0
    }

    static func normalizedRotationInterval(_ value: TimeInterval) -> TimeInterval {
        min(60, max(3, value))
    }

    static func rotationInterval(in defaults: UserDefaults) -> TimeInterval {
        guard defaults.object(forKey: "aiQuotaRotationInterval") != nil else {
            return self.defaultRotationInterval
        }
        return self.normalizedRotationInterval(defaults.double(forKey: "aiQuotaRotationInterval"))
    }

    static func installFirstRunDefaults(in defaults: UserDefaults) {
        guard defaults.integer(forKey: self.defaultsVersionKey) < self.defaultsVersion else { return }

        defaults.set(AppLanguage.chineseSimplified.rawValue, forKey: "appLanguage")
        defaults.set(RefreshFrequency.oneMinute.rawValue, forKey: "refreshFrequency")
        defaults.set(true, forKey: "launchAtLogin")
        defaults.set(true, forKey: "usageBarsShowUsed")
        defaults.set(true, forKey: "mergeIcons")
        defaults.set(true, forKey: "mergedMenuLastSelectedWasOverview")
        defaults.set(self.providers.map(\.rawValue), forKey: "mergedOverviewSelectedProviders")
        defaults.set(true, forKey: "quotaWarningNotificationsEnabled")
        defaults.set(true, forKey: "sessionQuotaNotificationsEnabled")
        defaults.set([20, 5], forKey: "quotaWarningThresholds")
        defaults.set([20, 5], forKey: "quotaWarningSessionThresholds")
        defaults.set([20, 5], forKey: "quotaWarningWeeklyThresholds")
        defaults.set(true, forKey: "quotaWarningSessionEnabled")
        defaults.set(true, forKey: "quotaWarningWeeklyEnabled")
        defaults.set(self.defaultRotationInterval, forKey: "aiQuotaRotationInterval")
        defaults.set(self.defaultsVersion, forKey: self.defaultsVersionKey)
    }
}
