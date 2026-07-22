import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct AIQuotaPreferencesView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void
    @AppStorage("aiQuotaRotationInterval") private var rotationInterval = AIQuotaProduct.defaultRotationInterval
    @State private var expandedProvider: UsageProvider?
    @State private var credentialDrafts: [AIQuotaCredentialKind: String] = [:]
    @State private var validationMessages: [UsageProvider: String] = [:]

    private let refreshOptions: [RefreshFrequency] = [
        .oneMinute,
        .twoMinutes,
        .fiveMinutes,
        .fifteenMinutes,
        .thirtyMinutes,
    ]

    var body: some View {
        Form {
            Section {
                ForEach(AIQuotaProduct.providers, id: \.self) { provider in
                    self.providerRow(provider)
                }
            } header: {
                Text("AI 服务")
            } footer: {
                Text("Codex 与 Claude 使用本机登录账号；Kimi、MiniMax 与 GLM 的凭据仅保存在 macOS 钥匙串中。")
            }

            Section("刷新与轮换") {
                Picker("刷新间隔", selection: self.$settings.refreshFrequency) {
                    ForEach(self.refreshOptions) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }

                LabeledContent("菜单栏轮换") {
                    HStack(spacing: 10) {
                        Slider(value: self.$rotationInterval, in: 3...30, step: 1)
                            .frame(width: 180)
                        Text("\(Int(self.rotationInterval)) 秒")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section("通知") {
                Toggle("额度提醒", isOn: self.$settings.quotaWarningNotificationsEnabled)
                Toggle("额度重置提醒", isOn: self.$settings.sessionQuotaNotificationsEnabled)

                Stepper(
                    "第一次提醒：已使用 \(self.usedThresholds[0])%",
                    value: self.usedThresholdBinding(at: 0),
                    in: 50...94,
                    step: 1)
                Stepper(
                    "第二次提醒：已使用 \(self.usedThresholds[1])%",
                    value: self.usedThresholdBinding(at: 1),
                    in: 51...99,
                    step: 1)
            }

            Section("系统") {
                Toggle("登录时启动 AI Quota", isOn: self.$settings.launchAtLogin)
                HStack {
                    Spacer()
                    Button("退出 AI Quota") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
    }

    @ViewBuilder
    private func providerRow(_ provider: UsageProvider) -> some View {
        let metadata = self.store.metadata(for: provider)
        let enabled = self.settings.isProviderEnabled(provider: provider, metadata: metadata)
        let snapshot = self.store.snapshot(for: provider)
        let presentation = AIQuotaPresentation.make(
            provider: provider,
            snapshot: snapshot,
            isStale: self.store.isStale(provider: provider))

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let icon = ProviderBrandIcon.image(for: provider) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Toggle(AIQuotaProduct.displayName(for: provider), isOn: Binding(
                    get: { enabled },
                    set: { value in
                        self.setProviderEnabled(
                            provider,
                            metadata: metadata,
                            enabled: value)
                    }))
                Spacer()
                if self.store.refreshingProviders.contains(provider) {
                    ProgressView().controlSize(.small)
                }
                if AIQuotaProviderActivation.configurableProviders.contains(provider) {
                    Button(self.expandedProvider == provider ? "收起" : "配置") {
                        self.expandedProvider = self.expandedProvider == provider ? nil : provider
                    }
                } else {
                    Button(snapshot == nil ? "登录" : "重新登录") {
                        Task { await self.runProviderLoginFlow(provider) }
                    }
                }
            }

            if enabled {
                HStack(spacing: 16) {
                    self.metricSummary(presentation.slot1)
                    self.metricSummary(presentation.slot2)
                }
            }

            if self.expandedProvider == provider,
               AIQuotaProviderActivation.configurableProviders.contains(provider)
            {
                self.providerConfiguration(provider)
            }

            if let message = self.validationMessages[provider], !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message == "验证成功，已加入菜单栏轮换。" ? .green : .orange)
                    .lineLimit(3)
            } else if let error = self.store.userFacingError(for: provider), !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
    }

    private func setProviderEnabled(
        _ provider: UsageProvider,
        metadata: ProviderMetadata,
        enabled: Bool)
    {
        guard AIQuotaProviderActivation.configurableProviders.contains(provider) else {
            self.settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: enabled)
            return
        }
        if !enabled {
            self.settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: false)
        } else if self.settings.isAIQuotaProviderValidated(provider) {
            self.settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
            self.settings.setAIQuotaProviderOverviewMembership(provider, included: true)
        } else {
            self.expandedProvider = provider
            self.validationMessages[provider] = "请先完成配置并验证，验证成功后才会启用。"
        }
    }

    private func providerConfiguration(_ provider: UsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            switch provider {
            case .kimi:
                Picker("连接方式", selection: Binding(
                    get: { self.settings.kimiUsageDataSource },
                    set: { self.settings.kimiUsageDataSource = $0 }))
                {
                    Text("自动（本机登录 / 浏览器）").tag(ProviderSourceMode.auto)
                    Text("API Key").tag(ProviderSourceMode.api)
                    Text("浏览器 Cookie").tag(ProviderSourceMode.web)
                }

                if self.settings.kimiUsageDataSource == .api {
                    self.secureCredentialField(
                        "Kimi Code API Key",
                        kind: .kimiAPIKey,
                        isStored: !self.settings.kimiAPIKey.isEmpty)
                } else if self.settings.kimiUsageDataSource == .web {
                    self.cookieSourcePicker(
                        selection: Binding(
                            get: { self.settings.kimiCookieSource },
                            set: { self.settings.kimiCookieSource = $0 }))
                    if self.settings.kimiCookieSource == .manual {
                        self.secureCredentialField(
                            "Cookie Header",
                            kind: .kimiCookie,
                            isStored: !self.settings.kimiManualCookieHeader.isEmpty)
                    }
                } else {
                    Text("自动模式优先使用已保存的 API Key，其次尝试 Kimi CLI 与浏览器登录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .minimax:
                Text("区域：MiniMax 中国大陆 Coding Plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                self.secureCredentialField(
                    "Coding Plan API Token（推荐）",
                    kind: .minimaxAPIToken,
                    isStored: !self.settings.minimaxAPIToken.isEmpty)
                self.cookieSourcePicker(
                    selection: Binding(
                        get: { self.settings.minimaxCookieSource },
                        set: { self.settings.minimaxCookieSource = $0 }))
                if self.settings.minimaxCookieSource == .manual {
                    self.secureCredentialField(
                        "Cookie Header",
                        kind: .minimaxCookie,
                        isStored: !self.settings.minimaxCookieHeader.isEmpty)
                }

            case .zai:
                Text("区域：智谱 BigModel 中国区")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                self.secureCredentialField(
                    "GLM API Key",
                    kind: .glmAPIKey,
                    isStored: !self.settings.zaiAPIToken.isEmpty)

            default:
                EmptyView()
            }

            HStack {
                Button("验证并启用") {
                    Task { await self.validateAndEnable(provider) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.store.refreshingProviders.contains(provider))

                if self.settings.isAIQuotaProviderValidated(provider) || self.hasStoredCredential(for: provider) {
                    Button("移除配置", role: .destructive) {
                        self.removeConfiguration(provider)
                    }
                    .disabled(self.store.refreshingProviders.contains(provider))
                }
            }
        }
        .padding(.leading, 28)
    }

    private func cookieSourcePicker(selection: Binding<ProviderCookieSource>) -> some View {
        Picker("Cookie 来源", selection: selection) {
            Text("自动读取浏览器").tag(ProviderCookieSource.auto)
            Text("手动输入").tag(ProviderCookieSource.manual)
            Text("不使用 Cookie").tag(ProviderCookieSource.off)
        }
    }

    private func secureCredentialField(
        _ title: String,
        kind: AIQuotaCredentialKind,
        isStored: Bool) -> some View
    {
        SecureField(
            title,
            text: self.credentialDraftBinding(kind),
            prompt: Text(isStored ? "已安全保存；输入新值以替换" : "请输入凭据"))
            .textFieldStyle(.roundedBorder)
    }

    private func credentialDraftBinding(_ kind: AIQuotaCredentialKind) -> Binding<String> {
        Binding(
            get: { self.credentialDrafts[kind] ?? "" },
            set: { self.credentialDrafts[kind] = $0 })
    }

    private func validateAndEnable(_ provider: UsageProvider) async {
        self.validationMessages[provider] = nil
        let metadata = self.store.metadata(for: provider)
        self.settings.setAIQuotaProviderValidated(provider, validated: false)
        self.settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: false)
        do {
            try self.saveDraftCredentials(for: provider)
        } catch {
            self.validationMessages[provider] = "无法保存到 macOS 钥匙串：\(error.localizedDescription)"
            return
        }

        self.settings.prepareAIQuotaProviderConfiguration(provider)

        let previousUpdatedAt = self.store.snapshot(for: provider)?.updatedAt
        await self.store.refreshProvider(provider, allowDisabled: true)
        let error = self.store.userFacingError(for: provider)
        guard AIQuotaProviderActivation.validationSucceeded(
            previousUpdatedAt: previousUpdatedAt,
            snapshot: self.store.snapshot(for: provider),
            error: error)
        else {
            self.validationMessages[provider] = error ?? "验证未返回新的额度数据，请检查凭据后重试。"
            return
        }

        self.settings.setAIQuotaProviderValidated(provider, validated: true)
        self.settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        self.settings.setAIQuotaProviderOverviewMembership(provider, included: true)
        self.validationMessages[provider] = "验证成功，已加入菜单栏轮换。"
    }

    private func saveDraftCredentials(for provider: UsageProvider) throws {
        for kind in self.credentialKinds(for: provider) {
            guard let draft = self.credentialDrafts[kind],
                  !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            try self.settings.setAIQuotaCredential(draft, for: kind, provider: provider)
            self.credentialDrafts[kind] = ""
        }
    }

    private func removeConfiguration(_ provider: UsageProvider) {
        let metadata = self.store.metadata(for: provider)
        self.settings.deactivateAIQuotaProvider(provider, metadata: metadata)
        do {
            for kind in self.credentialKinds(for: provider) {
                try self.settings.setAIQuotaCredential("", for: kind, provider: provider)
                self.credentialDrafts[kind] = ""
            }
        } catch {
            self.validationMessages[provider] = "无法从 macOS 钥匙串移除凭据：\(error.localizedDescription)"
            return
        }

        self.validationMessages[provider] = "配置已移除，已退出菜单栏轮换。"
    }

    private func credentialKinds(for provider: UsageProvider) -> [AIQuotaCredentialKind] {
        switch provider {
        case .kimi: [.kimiAPIKey, .kimiCookie]
        case .minimax: [.minimaxAPIToken, .minimaxCookie]
        case .zai: [.glmAPIKey]
        default: []
        }
    }

    private func hasStoredCredential(for provider: UsageProvider) -> Bool {
        self.credentialKinds(for: provider).contains { !self.settings.aiQuotaCredential(for: $0).isEmpty }
    }

    private func metricSummary(_ metric: AIQuotaMetric?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(metric?.label ?? "--")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(metric?.percentText ?? "--")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: metric?.usedPercent ?? 0, total: 100)
                .frame(width: 170)
        }
    }

    private var usedThresholds: [Int] {
        let values = self.settings.quotaWarningThresholds
            .map { 100 - $0 }
            .sorted()
        return [values.first ?? 80, values.dropFirst().first ?? 95]
    }

    private func usedThresholdBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: { self.usedThresholds[index] },
            set: { newValue in
                var values = self.usedThresholds
                values[index] = newValue
                values.sort()
                if values[0] == values[1] {
                    values[index == 0 ? 0 : 1] += index == 0 ? -1 : 1
                }
                self.settings.quotaWarningThresholds = values
                    .map { 100 - $0 }
                    .sorted(by: >)
            })
    }
}
