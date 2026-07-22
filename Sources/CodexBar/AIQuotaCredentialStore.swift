import CodexBarCore
import Foundation
import Security

enum AIQuotaCredentialKind: String, CaseIterable, Sendable {
    case kimiAPIKey = "kimi-api-key"
    case kimiCookie = "kimi-cookie"
    case minimaxAPIToken = "minimax-api-token"
    case minimaxCookie = "minimax-cookie"
    case glmAPIKey = "glm-api-key"

    fileprivate var promptKind: KeychainPromptContext.Kind {
        switch self {
        case .kimiAPIKey, .kimiCookie: .kimiToken
        case .minimaxAPIToken: .minimaxToken
        case .minimaxCookie: .minimaxCookie
        case .glmAPIKey: .zaiToken
        }
    }
}

protocol AIQuotaCredentialStoring: Sendable {
    func loadCredential(for kind: AIQuotaCredentialKind) throws -> String?
    func storeCredential(_ value: String?, for kind: AIQuotaCredentialKind) throws
}

enum AIQuotaCredentialStoreError: LocalizedError {
    case accessDisabled
    case keychainStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .accessDisabled:
            "Keychain access is disabled."
        case let .keychainStatus(status):
            "Keychain error: \(status)"
        case .invalidData:
            "Keychain returned invalid data."
        }
    }
}

struct KeychainAIQuotaCredentialStore: AIQuotaCredentialStoring {
    static let defaultService = "com.matype.aiquota.credentials"

    private struct CachedValue {
        let value: String?
    }

    private nonisolated(unsafe) static var cache: [String: CachedValue] = [:]
    private static let cacheLock = NSLock()

    private let service: String

    init(service: String = Self.defaultService) {
        self.service = service
    }

    func loadCredential(for kind: AIQuotaCredentialKind) throws -> String? {
        guard !KeychainAccessGate.isDisabled else { return nil }

        let cacheKey = self.cacheKey(for: kind)
        Self.cacheLock.lock()
        if let cached = Self.cache[cacheKey] {
            Self.cacheLock.unlock()
            return cached.value
        }
        Self.cacheLock.unlock()

        if case .interactionRequired = KeychainAccessPreflight.checkGenericPassword(
            service: self.service,
            account: kind.rawValue)
        {
            KeychainPromptHandler.handler?(KeychainPromptContext(
                kind: kind.promptKind,
                service: self.service,
                account: kind.rawValue))
        }

        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: kind.rawValue,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        let status = KeychainSecurity.copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            self.cache(nil, for: cacheKey)
            return nil
        }
        guard status == errSecSuccess else {
            throw AIQuotaCredentialStoreError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw AIQuotaCredentialStoreError.invalidData
        }
        let value = Self.normalized(String(data: data, encoding: .utf8))
        self.cache(value, for: cacheKey)
        return value
    }

    func storeCredential(_ value: String?, for kind: AIQuotaCredentialKind) throws {
        guard !KeychainAccessGate.isDisabled else {
            throw AIQuotaCredentialStoreError.accessDisabled
        }

        let cleaned = Self.normalized(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: kind.rawValue,
        ]
        guard let cleaned else {
            let status = KeychainSecurity.delete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AIQuotaCredentialStoreError.keychainStatus(status)
            }
            self.cache(nil, for: self.cacheKey(for: kind))
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(cleaned.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = KeychainSecurity.update(query as CFDictionary, attributes as CFDictionary)
        if updateStatus != errSecSuccess {
            guard updateStatus == errSecItemNotFound else {
                throw AIQuotaCredentialStoreError.keychainStatus(updateStatus)
            }
            var addQuery = query
            for (key, value) in attributes {
                addQuery[key] = value
            }
            let addStatus = KeychainSecurity.add(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AIQuotaCredentialStoreError.keychainStatus(addStatus)
            }
        }
        self.cache(cleaned, for: self.cacheKey(for: kind))
    }

    private static func normalized(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private func cacheKey(for kind: AIQuotaCredentialKind) -> String {
        "\(self.service):\(kind.rawValue)"
    }

    private func cache(_ value: String?, for key: String) {
        Self.cacheLock.lock()
        Self.cache[key] = CachedValue(value: value)
        Self.cacheLock.unlock()
    }
}

final class InMemoryAIQuotaCredentialStore: AIQuotaCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [AIQuotaCredentialKind: String] = [:]

    func loadCredential(for kind: AIQuotaCredentialKind) throws -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.credentials[kind]
    }

    func storeCredential(_ value: String?, for kind: AIQuotaCredentialKind) throws {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cleaned, !cleaned.isEmpty {
            self.credentials[kind] = cleaned
        } else {
            self.credentials.removeValue(forKey: kind)
        }
    }
}

enum AIQuotaCredentialMigration {
    private enum ConfigField {
        case apiKey
        case cookieHeader
    }

    private struct Entry {
        let provider: UsageProvider
        let field: ConfigField
        let kind: AIQuotaCredentialKind
    }

    private static let entries: [Entry] = [
        Entry(provider: .kimi, field: .apiKey, kind: .kimiAPIKey),
        Entry(provider: .kimi, field: .cookieHeader, kind: .kimiCookie),
        Entry(provider: .minimax, field: .apiKey, kind: .minimaxAPIToken),
        Entry(provider: .minimax, field: .cookieHeader, kind: .minimaxCookie),
        Entry(provider: .zai, field: .apiKey, kind: .glmAPIKey),
    ]

    static func migrate(
        config: CodexBarConfig,
        credentialStore: any AIQuotaCredentialStoring,
        save: (CodexBarConfig) throws -> Void) -> CodexBarConfig
    {
        var candidate = config
        var changed = false

        for entry in self.entries {
            guard let index = candidate.providers.firstIndex(where: { $0.id == entry.provider }) else { continue }
            let rawValue: String? = switch entry.field {
            case .apiKey: candidate.providers[index].apiKey
            case .cookieHeader: candidate.providers[index].cookieHeader
            }
            guard let value = self.normalized(rawValue) else { continue }
            do {
                if try self.normalized(credentialStore.loadCredential(for: entry.kind)) == nil {
                    try credentialStore.storeCredential(value, for: entry.kind)
                }
                switch entry.field {
                case .apiKey: candidate.providers[index].apiKey = nil
                case .cookieHeader: candidate.providers[index].cookieHeader = nil
                }
                changed = true
            } catch {
                CodexBarLog.logger(LogCategories.settings).error(
                    "AI Quota credential migration secure write failed",
                    metadata: ["credential": entry.kind.rawValue])
            }
        }

        guard changed else { return config.normalized() }
        do {
            try save(candidate)
            return candidate.normalized()
        } catch {
            CodexBarLog.logger(LogCategories.configStore).error(
                "AI Quota credential migration config save failed: \(error)")
            return config.normalized()
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }
}

extension SettingsStore {
    func aiQuotaCredential(for kind: AIQuotaCredentialKind) -> String {
        do {
            return try self.aiQuotaCredentialStore.loadCredential(for: kind) ?? ""
        } catch {
            CodexBarLog.logger(LogCategories.settings).error(
                "AI Quota credential read failed",
                metadata: ["credential": kind.rawValue])
            return ""
        }
    }

    func setAIQuotaCredential(
        _ value: String,
        for kind: AIQuotaCredentialKind,
        provider: UsageProvider) throws
    {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.isEmpty ? nil : cleaned
        let previous = try self.aiQuotaCredentialStore.loadCredential(for: kind)
        try self.aiQuotaCredentialStore.storeCredential(normalized, for: kind)
        guard previous != normalized else { return }
        self.setAIQuotaProviderValidated(provider, validated: false)
        self.noteAIQuotaCredentialChanged(provider: provider)
    }

    func storeAIQuotaCredentialFromSetting(
        _ value: String,
        kind: AIQuotaCredentialKind,
        provider: UsageProvider,
        field: String)
    {
        do {
            try self.setAIQuotaCredential(value, for: kind, provider: provider)
            self.logSecretUpdate(provider: provider, field: field, value: value)
        } catch {
            CodexBarLog.logger(LogCategories.settings).error(
                "AI Quota credential write failed",
                metadata: ["credential": kind.rawValue, "provider": provider.rawValue])
        }
    }
}
