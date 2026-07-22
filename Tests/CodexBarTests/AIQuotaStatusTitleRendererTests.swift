import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct AIQuotaStatusTitleRendererTests {
    @Test
    func `renders two compact dynamic metric rows at the fixed width`() {
        let presentation = AIQuotaPresentation(
            provider: .codex,
            slot1: AIQuotaMetric(
                label: "6H",
                window: RateWindow(
                    usedPercent: 41.2,
                    windowMinutes: 360,
                    resetsAt: nil,
                    resetDescription: nil)),
            slot2: AIQuotaMetric(
                label: "DAY",
                window: RateWindow(
                    usedPercent: 58.8,
                    windowMinutes: 1440,
                    resetsAt: nil,
                    resetDescription: nil)),
            isStale: false)

        let rendered = AIQuotaStatusTitleRenderer.render(presentation)

        #expect(rendered.statusItemLength == 100)
        #expect(rendered.menuBarImage.size == NSSize(width: 94, height: 18))
        #expect(!rendered.menuBarImage.isTemplate)
        #expect(AIQuotaStatusTitleRenderer.layout.sessionCenterX == 40)
        #expect(AIQuotaStatusTitleRenderer.layout.weeklyCenterX == 74)
        #expect(AIQuotaStatusTitleRenderer.layout.valueY == -1)
        #expect(AIQuotaStatusTitleRenderer.layout.labelY == 10)
        #expect(AIQuotaStatusTitleRenderer.valueFont.fontName == NSFont.monospacedSystemFont(
            ofSize: 9.5,
            weight: .regular).fontName)
        #expect(rendered.accessibilityLabel.contains("Codex"))
        #expect(rendered.accessibilityLabel.contains("6H"))
        #expect(rendered.accessibilityLabel.contains("DAY"))
        #expect(rendered.accessibilityLabel.contains("41%"))
        #expect(rendered.accessibilityLabel.contains("59%"))
    }

    @Test
    func `accessibility uses product provider name and real labels`() {
        let presentation = AIQuotaPresentation(
            provider: .zai,
            slot1: AIQuotaMetric(
                label: "DAY",
                window: RateWindow(
                    usedPercent: 27,
                    windowMinutes: 1440,
                    resetsAt: nil,
                    resetDescription: nil)),
            slot2: AIQuotaMetric(
                label: "MONTH",
                window: RateWindow(
                    usedPercent: 68,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: nil,
                    resetDescription: nil)),
            isStale: false)

        let rendered = AIQuotaStatusTitleRenderer.render(presentation)

        #expect(rendered.accessibilityLabel == "GLM，DAY 已使用 27%，MONTH 已使用 68%")
    }

    @Test
    func `shows missing values and stale marker`() {
        let presentation = AIQuotaPresentation(
            provider: .claude,
            slot1: nil,
            slot2: nil,
            isStale: true)

        let rendered = AIQuotaStatusTitleRenderer.render(presentation)

        #expect(rendered.accessibilityLabel.contains("SLOT1"))
        #expect(rendered.accessibilityLabel.contains("SLOT2"))
        #expect(rendered.accessibilityLabel.contains("数据过旧"))
    }

    @Test
    func `reserves the same width as two 100 percent values`() {
        func render(slot1: Double, slot2: Double) -> AIQuotaStatusTitle {
            AIQuotaStatusTitleRenderer.render(AIQuotaPresentation(
                provider: .codex,
                slot1: AIQuotaMetric(
                    label: "5H",
                    window: RateWindow(
                        usedPercent: slot1,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: nil)),
                slot2: AIQuotaMetric(
                    label: "WEEK",
                    window: RateWindow(
                        usedPercent: slot2,
                        windowMinutes: 10080,
                        resetsAt: nil,
                        resetDescription: nil)),
                isStale: false))
        }

        let shortValues = render(slot1: 1, slot2: 9)
        let maximumValues = render(slot1: 100, slot2: 100)

        #expect(shortValues.menuBarImage.size.width == maximumValues.menuBarImage.size.width)
        #expect(shortValues.statusItemLength == maximumValues.statusItemLength)
        #expect(shortValues.statusItemLength == 100)
    }
}
