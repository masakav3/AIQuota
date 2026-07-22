import CodexBarCore
import Foundation

extension SettingsStore {
    var kimiUsageDataSource: ProviderSourceMode {
        get { self.configSnapshot.providerConfig(for: .kimi)?.source ?? .auto }
        set {
            let source: ProviderSourceMode? = switch newValue {
            case .auto: .auto
            case .api: .api
            case .web: .web
            case .cli, .oauth: .auto
            }
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.source = source
            }
            if self.aiQuotaProductActive {
                self.setAIQuotaProviderValidated(.kimi, validated: false)
            }
            self.logProviderModeChange(provider: .kimi, field: "usageSource", value: newValue.rawValue)
        }
    }

    var kimiAPIKey: String {
        get {
            if self.aiQuotaProductActive {
                return self.aiQuotaCredential(for: .kimiAPIKey)
            }
            return self.configSnapshot.providerConfig(for: .kimi)?.sanitizedAPIKey ?? ""
        }
        set {
            if self.aiQuotaProductActive {
                self.storeAIQuotaCredentialFromSetting(
                    newValue,
                    kind: .kimiAPIKey,
                    provider: .kimi,
                    field: "apiKey")
                return
            }
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kimi, field: "apiKey", value: newValue)
        }
    }

    var kimiManualCookieHeader: String {
        get {
            if self.aiQuotaProductActive {
                return self.aiQuotaCredential(for: .kimiCookie)
            }
            return self.configSnapshot.providerConfig(for: .kimi)?.sanitizedCookieHeader ?? ""
        }
        set {
            if self.aiQuotaProductActive {
                self.storeAIQuotaCredentialFromSetting(
                    newValue,
                    kind: .kimiCookie,
                    provider: .kimi,
                    field: "cookieHeader")
                return
            }
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kimi, field: "cookieHeader", value: newValue)
        }
    }

    var kimiCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .kimi, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .kimi) { entry in
                entry.cookieSource = newValue
            }
            if self.aiQuotaProductActive {
                self.setAIQuotaProviderValidated(.kimi, validated: false)
            }
            self.logProviderModeChange(provider: .kimi, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureKimiAuthTokenLoaded() {}
}

extension SettingsStore {
    func kimiSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot.KimiProviderSettings {
        self.ensureKimiAuthTokenLoaded()
        return self.resolvedCookieSettings(
            provider: .kimi,
            configuredSource: self.kimiCookieSource,
            configuredHeader: self.kimiManualCookieHeader,
            tokenOverride: tokenOverride)
    }
}
