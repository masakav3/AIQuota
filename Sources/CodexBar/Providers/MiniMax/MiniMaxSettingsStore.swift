import CodexBarCore
import Foundation

extension SettingsStore {
    var minimaxAPIRegion: MiniMaxAPIRegion {
        get {
            let raw = self.configSnapshot.providerConfig(for: .minimax)?.region
            return MiniMaxAPIRegion(rawValue: raw ?? "") ?? .global
        }
        set {
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.region = newValue.rawValue
            }
        }
    }

    var minimaxCookieHeader: String {
        get {
            if self.aiQuotaProductActive {
                return self.aiQuotaCredential(for: .minimaxCookie)
            }
            return self.configSnapshot.providerConfig(for: .minimax)?.sanitizedCookieHeader ?? ""
        }
        set {
            if self.aiQuotaProductActive {
                self.storeAIQuotaCredentialFromSetting(
                    newValue,
                    kind: .minimaxCookie,
                    provider: .minimax,
                    field: "cookieHeader")
                return
            }
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .minimax, field: "cookieHeader", value: newValue)
        }
    }

    var minimaxAPIToken: String {
        get {
            if self.aiQuotaProductActive {
                return self.aiQuotaCredential(for: .minimaxAPIToken)
            }
            return self.configSnapshot.providerConfig(for: .minimax)?.sanitizedAPIKey ?? ""
        }
        set {
            if self.aiQuotaProductActive {
                self.storeAIQuotaCredentialFromSetting(
                    newValue,
                    kind: .minimaxAPIToken,
                    provider: .minimax,
                    field: "apiKey")
                return
            }
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .minimax, field: "apiKey", value: newValue)
        }
    }

    var minimaxCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .minimax, fallback: .auto) }
        set {
            guard newValue != self.minimaxCookieSource else { return }
            self.updateProviderConfig(provider: .minimax) { entry in
                entry.cookieSource = newValue
            }
            if self.aiQuotaProductActive {
                self.setAIQuotaProviderValidated(.minimax, validated: false)
            }
            self.logProviderModeChange(provider: .minimax, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureMiniMaxCookieLoaded() {}

    func ensureMiniMaxAPITokenLoaded() {}

    func minimaxAuthMode(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> MiniMaxAuthMode
    {
        let apiToken = MiniMaxAPISettingsReader.apiToken(environment: environment) ?? self.minimaxAPIToken
        let cookieHeader = MiniMaxSettingsReader.cookieHeader(environment: environment) ?? self.minimaxCookieHeader
        return MiniMaxAuthMode.resolve(apiToken: apiToken, cookieHeader: cookieHeader)
    }
}

extension SettingsStore {
    func minimaxSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    .MiniMaxProviderSettings {
        let cookieSettings: ProviderSettingsSnapshot.CookieProviderSettings = self.resolvedCookieSettings(
            provider: .minimax,
            configuredSource: self.minimaxCookieSource,
            configuredHeader: self.minimaxCookieHeader,
            tokenOverride: tokenOverride)
        return ProviderSettingsSnapshot.MiniMaxProviderSettings(
            cookieSource: cookieSettings.cookieSource,
            manualCookieHeader: cookieSettings.manualCookieHeader,
            apiRegion: self.minimaxAPIRegion)
    }
}
