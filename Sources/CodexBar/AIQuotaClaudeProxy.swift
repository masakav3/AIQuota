import Foundation

enum AIQuotaClaudeProxy {
    static let defaultURL = "http://127.0.0.1:7897"
    private static let enabledKey = "aiQuotaClaudeProxyEnabled"
    private static let urlKey = "aiQuotaClaudeProxyURL"

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: self.enabledKey) as? Bool ?? true
    }

    static func url(in defaults: UserDefaults) -> String {
        defaults.string(forKey: self.urlKey) ?? self.defaultURL
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: self.enabledKey)
    }

    static func setURL(_ url: String, in defaults: UserDefaults) {
        defaults.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: self.urlKey)
    }

    static func applying(to base: [String: String], enabled: Bool, url: String) -> [String: String] {
        let proxyURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !proxyURL.isEmpty else { return base }

        var environment = base
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"] {
            environment[key] = proxyURL
        }
        return environment
    }
}

extension SettingsStore {
    var aiQuotaClaudeProxyEnabled: Bool {
        get {
            _ = self.backgroundWorkSettingsRevision
            return AIQuotaClaudeProxy.isEnabled(in: self.userDefaults)
        }
        set {
            AIQuotaClaudeProxy.setEnabled(newValue, in: self.userDefaults)
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var aiQuotaClaudeProxyURL: String {
        get {
            _ = self.backgroundWorkSettingsRevision
            return AIQuotaClaudeProxy.url(in: self.userDefaults)
        }
        set {
            AIQuotaClaudeProxy.setURL(newValue, in: self.userDefaults)
            self.noteBackgroundWorkSettingsChanged()
        }
    }
}
