import CodexBarCore
import Foundation

enum AIQuotaProviderActivation {
    static let configurableProviders: Set<UsageProvider> = [.kimi, .minimax, .zai]

    static func validationSucceeded(
        previousUpdatedAt: Date?,
        snapshot: UsageSnapshot?,
        error: String?) -> Bool
    {
        guard error?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let snapshot,
              snapshot.zaiUsage?.isValid != false
        else {
            return false
        }
        return snapshot.updatedAt != previousUpdatedAt
    }
}

extension SettingsStore {
    private static let aiQuotaValidatedProvidersKey = "aiQuotaValidatedProviders"

    func isAIQuotaProviderValidated(_ provider: UsageProvider) -> Bool {
        guard AIQuotaProviderActivation.configurableProviders.contains(provider) else { return true }
        return self.aiQuotaValidatedProviders.contains(provider)
    }

    func canEnableAIQuotaProvider(_ provider: UsageProvider) -> Bool {
        !self.aiQuotaProductActive || self.isAIQuotaProviderValidated(provider)
    }

    func setAIQuotaProviderValidated(_ provider: UsageProvider, validated: Bool) {
        guard AIQuotaProviderActivation.configurableProviders.contains(provider) else { return }
        var providers = self.aiQuotaValidatedProviders
        if validated {
            providers.insert(provider)
        } else {
            providers.remove(provider)
        }
        self.userDefaults.set(
            providers.map(\.rawValue).sorted(),
            forKey: Self.aiQuotaValidatedProvidersKey)
        if !validated, self.providerConfig(for: provider)?.enabled == true {
            self.updateProviderConfig(provider: provider) { entry in
                entry.enabled = false
            }
        }
    }

    func setAIQuotaProviderOverviewMembership(_ provider: UsageProvider, included: Bool) {
        var providers = self.mergedOverviewSelectedProviders
        if included {
            if !providers.contains(provider) {
                providers.append(provider)
            }
        } else {
            providers.removeAll { $0 == provider }
        }
        self.mergedOverviewSelectedProviders = providers
    }

    func deactivateAIQuotaProvider(_ provider: UsageProvider, metadata: ProviderMetadata) {
        self.setAIQuotaProviderValidated(provider, validated: false)
        self.setProviderEnabled(provider: provider, metadata: metadata, enabled: false)
        self.setAIQuotaProviderOverviewMembership(provider, included: false)
    }

    func prepareAIQuotaProviderConfiguration(_ provider: UsageProvider) {
        switch provider {
        case .minimax:
            self.updateProviderConfig(provider: provider) { entry in
                entry.source = .auto
                entry.region = MiniMaxAPIRegion.chinaMainland.rawValue
            }
        case .zai:
            self.updateProviderConfig(provider: provider) { entry in
                entry.source = .api
                entry.region = ZaiAPIRegion.bigmodelCN.rawValue
            }
        default:
            break
        }
    }

    private var aiQuotaValidatedProviders: Set<UsageProvider> {
        let raw = self.userDefaults.stringArray(forKey: Self.aiQuotaValidatedProvidersKey) ?? []
        return Set(raw.compactMap(UsageProvider.init(rawValue:)))
    }
}
