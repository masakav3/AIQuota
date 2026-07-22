import AppKit
import CodexBarCore

extension StatusItemController {
    func applyAIQuotaStatusTitle(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        to button: NSStatusBarButton) -> Bool
    {
        let presentation = AIQuotaPresentation.make(
            provider: provider,
            snapshot: snapshot,
            isStale: self.store.isStale(provider: provider))
        let rendered = AIQuotaStatusTitleRenderer.render(presentation)
        let signature = [
            "ai-quota",
            provider.rawValue,
            presentation.slot1?.label ?? "SLOT1",
            presentation.slot1?.percentText ?? "--",
            presentation.slot2?.label ?? "SLOT2",
            presentation.slot2?.percentText ?? "--",
            presentation.isStale ? "stale" : "fresh",
        ].joined(separator: "|")
        let wasCached = self.lastAppliedMergedIconRenderSignature == signature
        self.lastAppliedMergedIconRenderSignature = signature

        button.image = rendered.menuBarImage
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        if button.attributedTitle.length > 0 {
            button.attributedTitle = NSAttributedString()
        }
        if button.accessibilityTitle() != rendered.accessibilityLabel {
            button.setAccessibilityTitle(rendered.accessibilityLabel)
        }
        self.statusItem.length = rendered.statusItemLength
        self.noteIconPerfRender(skipped: wasCached)
        return wasCached
    }

    func startAIQuotaRotation() {
        self.aiQuotaRotationTask?.cancel()
        self.aiQuotaRotationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = AIQuotaProduct.rotationInterval(in: self.settings.userDefaults)
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                let providers = AIQuotaProduct.orderedEnabledProviders(
                    self.store.enabledProvidersForDisplay())
                self.aiQuotaRotation.updateProviders(providers)
                guard providers.count > 1 else { continue }
                _ = self.aiQuotaRotation.advance()
                self.lastAppliedMergedIconRenderSignature = nil
                self.updateIcons()
            }
        }
    }
}
