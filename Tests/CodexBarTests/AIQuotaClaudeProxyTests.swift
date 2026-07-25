import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct AIQuotaClaudeProxyTests {
    @Test
    func `default proxy is injected into Claude only`() throws {
        let suiteName = "AIQuotaClaudeProxyTests-default-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        let base = ["PATH": "/usr/bin:/bin"]

        let claude = ProviderRegistry.makeEnvironment(
            base: base,
            provider: .claude,
            settings: settings,
            tokenOverride: nil)
        let kimi = ProviderRegistry.makeEnvironment(
            base: base,
            provider: .kimi,
            settings: settings,
            tokenOverride: nil)

        #expect(settings.aiQuotaClaudeProxyEnabled)
        #expect(settings.aiQuotaClaudeProxyURL == "http://127.0.0.1:7897")
        #expect(claude["HTTP_PROXY"] == "http://127.0.0.1:7897")
        #expect(claude["HTTPS_PROXY"] == "http://127.0.0.1:7897")
        #expect(claude["http_proxy"] == "http://127.0.0.1:7897")
        #expect(claude["https_proxy"] == "http://127.0.0.1:7897")
        #expect(kimi["HTTP_PROXY"] == nil)
        #expect(kimi["HTTPS_PROXY"] == nil)
    }

    @Test
    func `proxy preference persists and can be disabled`() throws {
        let suiteName = "AIQuotaClaudeProxyTests-persistence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = testConfigStore(suiteName: suiteName)
        let firstLaunch = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        firstLaunch.aiQuotaClaudeProxyURL = "http://127.0.0.1:9000"
        firstLaunch.aiQuotaClaudeProxyEnabled = false

        let restarted = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            aiQuotaCredentialStore: InMemoryAIQuotaCredentialStore(),
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        let environment = ProviderRegistry.makeEnvironment(
            base: ["PATH": "/usr/bin:/bin"],
            provider: .claude,
            settings: restarted,
            tokenOverride: nil)

        #expect(!restarted.aiQuotaClaudeProxyEnabled)
        #expect(restarted.aiQuotaClaudeProxyURL == "http://127.0.0.1:9000")
        #expect(environment["HTTP_PROXY"] == nil)
        #expect(environment["HTTPS_PROXY"] == nil)
    }
}
