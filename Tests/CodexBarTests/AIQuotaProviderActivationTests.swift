import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct AIQuotaProviderActivationTests {
    @Test
    func `validation succeeds only when a fresh snapshot is published without an error`() {
        let previous = Date(timeIntervalSince1970: 1_720_000_000)
        let fresh = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: previous.addingTimeInterval(1))

        #expect(AIQuotaProviderActivation.validationSucceeded(
            previousUpdatedAt: previous,
            snapshot: fresh,
            error: nil))
        #expect(!AIQuotaProviderActivation.validationSucceeded(
            previousUpdatedAt: fresh.updatedAt,
            snapshot: fresh,
            error: nil))
        #expect(!AIQuotaProviderActivation.validationSucceeded(
            previousUpdatedAt: previous,
            snapshot: fresh,
            error: "Invalid API key"))
        #expect(!AIQuotaProviderActivation.validationSucceeded(
            previousUpdatedAt: previous,
            snapshot: nil,
            error: nil))

        let emptyGLM = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: "GLM Coding Plan",
            updatedAt: previous.addingTimeInterval(2))
        #expect(!AIQuotaProviderActivation.validationSucceeded(
            previousUpdatedAt: previous,
            snapshot: emptyGLM.toUsageSnapshot(),
            error: nil))
    }

    @Test
    func `validation state persists separately from manual provider enablement`() throws {
        let suiteName = "AIQuotaProviderActivationTests-validation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = testConfigStore(suiteName: suiteName)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        let metadata = ProviderDescriptorRegistry.descriptor(for: .kimi).metadata

        settings.setProviderEnabled(provider: .kimi, metadata: metadata, enabled: true)
        #expect(!settings.isProviderEnabled(provider: .kimi, metadata: metadata))

        settings.setAIQuotaProviderValidated(.kimi, validated: true)
        settings.setProviderEnabled(provider: .kimi, metadata: metadata, enabled: true)
        #expect(settings.isProviderEnabled(provider: .kimi, metadata: metadata))
        settings.setProviderEnabled(provider: .kimi, metadata: metadata, enabled: false)

        #expect(settings.isAIQuotaProviderValidated(.kimi))
        #expect(!settings.isProviderEnabled(provider: .kimi, metadata: metadata))

        settings.setAIQuotaProviderValidated(.kimi, validated: false)
        #expect(!settings.isAIQuotaProviderValidated(.kimi))
    }

    @Test
    func `overview membership is added once and removed with credential deletion`() throws {
        let suiteName = "AIQuotaProviderActivationTests-overview-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        settings.mergedOverviewSelectedProviders = [.codex, .claude]

        settings.setAIQuotaProviderOverviewMembership(.minimax, included: true)
        settings.setAIQuotaProviderOverviewMembership(.minimax, included: true)
        #expect(settings.mergedOverviewSelectedProviders == [.codex, .claude, .minimax])

        settings.setAIQuotaProviderOverviewMembership(.minimax, included: false)
        #expect(settings.mergedOverviewSelectedProviders == [.codex, .claude])
    }

    @Test
    func `product configuration pins MiniMax and GLM to their China endpoints`() throws {
        let suiteName = "AIQuotaProviderActivationTests-region-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)

        settings.prepareAIQuotaProviderConfiguration(.minimax)
        settings.prepareAIQuotaProviderConfiguration(.zai)

        #expect(settings.minimaxAPIRegion == .chinaMainland)
        #expect(settings.providerConfig(for: .minimax)?.source == .auto)
        #expect(settings.zaiAPIRegion == .bigmodelCN)
        #expect(settings.providerConfig(for: .zai)?.source == .api)
    }

    @Test
    func `changing credentials or connection sources invalidates prior validation`() throws {
        let suiteName = "AIQuotaProviderActivationTests-invalidation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)

        settings.setAIQuotaProviderValidated(.kimi, validated: true)
        try settings.setAIQuotaCredential("replacement", for: .kimiAPIKey, provider: .kimi)
        #expect(!settings.isAIQuotaProviderValidated(.kimi))

        settings.setAIQuotaProviderValidated(.kimi, validated: true)
        settings.kimiUsageDataSource = .api
        #expect(!settings.isAIQuotaProviderValidated(.kimi))

        settings.setAIQuotaProviderValidated(.minimax, validated: true)
        settings.minimaxCookieSource = .manual
        #expect(!settings.isAIQuotaProviderValidated(.minimax))
    }

    @Test
    func `deactivation clears validation enablement and overview before credential deletion`() throws {
        let suiteName = "AIQuotaProviderActivationTests-deactivate-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        let metadata = ProviderDescriptorRegistry.descriptor(for: .minimax).metadata
        settings.setAIQuotaProviderValidated(.minimax, validated: true)
        settings.setProviderEnabled(provider: .minimax, metadata: metadata, enabled: true)
        settings.setAIQuotaProviderOverviewMembership(.minimax, included: true)

        settings.deactivateAIQuotaProvider(.minimax, metadata: metadata)

        #expect(!settings.isAIQuotaProviderValidated(.minimax))
        #expect(!settings.isProviderEnabled(provider: .minimax, metadata: metadata))
        #expect(!settings.mergedOverviewSelectedProviders.contains(.minimax))
    }
}
