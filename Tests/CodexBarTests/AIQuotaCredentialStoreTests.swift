import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct AIQuotaCredentialStoreTests {
    @Test
    func `in-memory credential store supports normalized CRUD`() throws {
        let store = InMemoryAIQuotaCredentialStore()

        #expect(try store.loadCredential(for: .kimiAPIKey) == nil)

        try store.storeCredential("  kimi-secret  ", for: .kimiAPIKey)
        #expect(try store.loadCredential(for: .kimiAPIKey) == "kimi-secret")

        try store.storeCredential("   ", for: .kimiAPIKey)
        #expect(try store.loadCredential(for: .kimiAPIKey) == nil)
    }

    @Test
    func `keychain store reports a disabled write instead of pretending it succeeded`() {
        let store = KeychainAIQuotaCredentialStore(service: "com.matype.aiquota.tests.\(UUID().uuidString)")
        var didThrow = false

        do {
            try store.storeCredential("must-not-be-dropped", for: .glmAPIKey)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test
    func `AI Quota settings persist credentials only in secure store and bump provider revisions`() throws {
        let fixture = try Self.makeSettingsFixture(suite: "secure-settings")
        let kimiRevision = fixture.settings.providerConfigRevision(for: .kimi)
        let minimaxRevision = fixture.settings.providerConfigRevision(for: .minimax)
        let glmRevision = fixture.settings.providerConfigRevision(for: .zai)

        fixture.settings.kimiAPIKey = "kimi-key"
        fixture.settings.kimiManualCookieHeader = "kimi-cookie"
        fixture.settings.minimaxAPIToken = "minimax-key"
        fixture.settings.minimaxCookieHeader = "minimax-cookie"
        fixture.settings.zaiAPIToken = "glm-key"

        #expect(try fixture.credentials.loadCredential(for: .kimiAPIKey) == "kimi-key")
        #expect(try fixture.credentials.loadCredential(for: .kimiCookie) == "kimi-cookie")
        #expect(try fixture.credentials.loadCredential(for: .minimaxAPIToken) == "minimax-key")
        #expect(try fixture.credentials.loadCredential(for: .minimaxCookie) == "minimax-cookie")
        #expect(try fixture.credentials.loadCredential(for: .glmAPIKey) == "glm-key")
        #expect(fixture.settings.providerConfigRevision(for: .kimi) == kimiRevision + 2)
        #expect(fixture.settings.providerConfigRevision(for: .minimax) == minimaxRevision + 2)
        #expect(fixture.settings.providerConfigRevision(for: .zai) == glmRevision + 1)

        let persisted = try #require(try fixture.configStore.load())
        #expect(persisted.providerConfig(for: .kimi)?.apiKey == nil)
        #expect(persisted.providerConfig(for: .kimi)?.cookieHeader == nil)
        #expect(persisted.providerConfig(for: .minimax)?.apiKey == nil)
        #expect(persisted.providerConfig(for: .minimax)?.cookieHeader == nil)
        #expect(persisted.providerConfig(for: .zai)?.apiKey == nil)

        let encoded = try String(contentsOf: fixture.configStore.fileURL, encoding: .utf8)
        for secret in ["kimi-key", "kimi-cookie", "minimax-key", "minimax-cookie", "glm-key"] {
            #expect(!encoded.contains(secret))
        }
    }

    @Test
    func `AI Quota environment uses secure API credentials over process values`() throws {
        let fixture = try Self.makeSettingsFixture(suite: "environment")
        fixture.settings.kimiAPIKey = "saved-kimi"
        fixture.settings.minimaxAPIToken = "saved-minimax"
        fixture.settings.zaiAPIToken = "saved-glm"

        let kimi = ProviderRegistry.makeEnvironment(
            base: [KimiSettingsReader.apiKeyEnvironmentKeys[0]: "process-kimi"],
            provider: .kimi,
            settings: fixture.settings,
            tokenOverride: nil)
        let minimax = ProviderRegistry.makeEnvironment(
            base: [MiniMaxAPISettingsReader.codingPlanAPITokenKey: "process-minimax"],
            provider: .minimax,
            settings: fixture.settings,
            tokenOverride: nil)
        let glm = ProviderRegistry.makeEnvironment(
            base: [ZaiSettingsReader.apiTokenKey: "process-glm"],
            provider: .zai,
            settings: fixture.settings,
            tokenOverride: nil)

        #expect(kimi[KimiSettingsReader.apiKeyEnvironmentKeys[0]] == "saved-kimi")
        #expect(minimax[MiniMaxAPISettingsReader.codingPlanAPITokenKey] == "saved-minimax")
        #expect(glm[ZaiSettingsReader.apiTokenKey] == "saved-glm")
    }

    @Test
    func `plaintext credentials migrate to secure store and are cleared from persisted config`() throws {
        let initial = CodexBarConfig(providers: [
            ProviderConfig(id: .kimi, apiKey: "kimi-key", cookieHeader: "kimi-cookie"),
            ProviderConfig(id: .minimax, apiKey: "minimax-key", cookieHeader: "minimax-cookie"),
            ProviderConfig(id: .zai, apiKey: "glm-key"),
        ])
        let fixture = try Self.makeSettingsFixture(suite: "migration-success", config: initial)

        #expect(fixture.settings.kimiAPIKey == "kimi-key")
        #expect(fixture.settings.kimiManualCookieHeader == "kimi-cookie")
        #expect(fixture.settings.minimaxAPIToken == "minimax-key")
        #expect(fixture.settings.minimaxCookieHeader == "minimax-cookie")
        #expect(fixture.settings.zaiAPIToken == "glm-key")

        let persisted = try #require(try fixture.configStore.load())
        #expect(persisted.providerConfig(for: .kimi)?.apiKey == nil)
        #expect(persisted.providerConfig(for: .kimi)?.cookieHeader == nil)
        #expect(persisted.providerConfig(for: .minimax)?.apiKey == nil)
        #expect(persisted.providerConfig(for: .minimax)?.cookieHeader == nil)
        #expect(persisted.providerConfig(for: .zai)?.apiKey == nil)
    }

    @Test
    func `migration retains a plaintext field when its secure write fails`() throws {
        let store = SelectivelyFailingAIQuotaCredentialStore(failing: [.minimaxCookie])
        let configStore = testConfigStore(suiteName: "AIQuotaCredentialStoreTests-migration-keychain-failure")
        let initial = CodexBarConfig(providers: [
            ProviderConfig(id: .kimi, apiKey: "kimi-key"),
            ProviderConfig(id: .minimax, cookieHeader: "minimax-cookie"),
        ])
        try configStore.save(initial)

        let migrated = AIQuotaCredentialMigration.migrate(
            config: initial,
            credentialStore: store,
            save: configStore.save)

        #expect(migrated.providerConfig(for: .kimi)?.apiKey == nil)
        #expect(migrated.providerConfig(for: .minimax)?.cookieHeader == "minimax-cookie")
        let persisted = try #require(try configStore.load())
        #expect(persisted.providerConfig(for: .kimi)?.apiKey == nil)
        #expect(persisted.providerConfig(for: .minimax)?.cookieHeader == "minimax-cookie")
    }

    @Test
    func `migration retains plaintext config when saving the cleared copy fails`() throws {
        let store = InMemoryAIQuotaCredentialStore()
        let initial = CodexBarConfig(providers: [
            ProviderConfig(id: .zai, apiKey: "glm-key"),
        ])

        let migrated = AIQuotaCredentialMigration.migrate(
            config: initial,
            credentialStore: store,
            save: { _ in throw TestFailure.saveFailed })

        #expect(migrated.providerConfig(for: .zai)?.apiKey == "glm-key")
        #expect(try store.loadCredential(for: .glmAPIKey) == "glm-key")
    }

    @Test
    func `retrying migration never overwrites a newer secure credential with stale plaintext`() throws {
        let store = InMemoryAIQuotaCredentialStore()
        let initial = CodexBarConfig(providers: [
            ProviderConfig(id: .zai, apiKey: "stale-glm-key"),
        ])

        let retained = AIQuotaCredentialMigration.migrate(
            config: initial,
            credentialStore: store,
            save: { _ in throw TestFailure.saveFailed })
        try store.storeCredential("new-glm-key", for: .glmAPIKey)

        var saved: CodexBarConfig?
        let migrated = AIQuotaCredentialMigration.migrate(
            config: retained,
            credentialStore: store,
            save: { saved = $0 })

        #expect(try store.loadCredential(for: .glmAPIKey) == "new-glm-key")
        #expect(migrated.providerConfig(for: .zai)?.apiKey == nil)
        #expect(saved?.providerConfig(for: .zai)?.apiKey == nil)
    }

    private static func makeSettingsFixture(
        suite: String,
        config: CodexBarConfig? = nil) throws
        -> (settings: SettingsStore, credentials: InMemoryAIQuotaCredentialStore, configStore: CodexBarConfigStore)
    {
        let suiteName = "AIQuotaCredentialStoreTests-\(suite)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let configStore = testConfigStore(suiteName: suiteName)
        try configStore.save(config ?? CodexBarConfig.makeDefault())
        let credentials = InMemoryAIQuotaCredentialStore()
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            aiQuotaCredentialStore: credentials,
            aiQuotaProductActive: true,
            performInitialProviderDetection: false)
        return (settings, credentials, configStore)
    }
}

private enum TestFailure: Error {
    case secureWriteFailed
    case saveFailed
}

private final class SelectivelyFailingAIQuotaCredentialStore: AIQuotaCredentialStoring, @unchecked Sendable {
    private let backing = InMemoryAIQuotaCredentialStore()
    private let failing: Set<AIQuotaCredentialKind>

    init(failing: Set<AIQuotaCredentialKind>) {
        self.failing = failing
    }

    func loadCredential(for kind: AIQuotaCredentialKind) throws -> String? {
        try self.backing.loadCredential(for: kind)
    }

    func storeCredential(_ value: String?, for kind: AIQuotaCredentialKind) throws {
        if self.failing.contains(kind) {
            throw TestFailure.secureWriteFailed
        }
        try self.backing.storeCredential(value, for: kind)
    }
}
