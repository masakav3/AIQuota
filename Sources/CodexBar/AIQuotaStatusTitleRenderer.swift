import AppKit
import CodexBarCore

struct AIQuotaStatusTitle {
    let menuBarImage: NSImage
    let accessibilityLabel: String
    let statusItemLength: CGFloat
}

struct AIQuotaStatusLayout {
    let imageSize: NSSize
    let iconFrame: NSRect
    let sessionCenterX: CGFloat
    let weeklyCenterX: CGFloat
    let staleCenterX: CGFloat
    let valueY: CGFloat
    let labelY: CGFloat
}

@MainActor
enum AIQuotaStatusTitleRenderer {
    private static let statusItemLength: CGFloat = 100
    static let layout = AIQuotaStatusLayout(
        imageSize: NSSize(width: 94, height: 18),
        iconFrame: NSRect(x: 0, y: 0, width: 18, height: 18),
        sessionCenterX: 40,
        weeklyCenterX: 74,
        staleCenterX: 90,
        valueY: -1,
        labelY: 10)
    static let valueFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 6.5, weight: .medium)

    static func render(_ presentation: AIQuotaPresentation) -> AIQuotaStatusTitle {
        let slot1 = presentation.slot1?.percentText ?? "--"
        let slot2 = presentation.slot2?.percentText ?? "--"
        let slot1Label = presentation.slot1?.label ?? "SLOT1"
        let slot2Label = presentation.slot2?.label ?? "SLOT2"
        let valueAlpha: CGFloat = presentation.isStale ? 0.52 : 1
        let labelAlpha: CGFloat = presentation.isStale ? 0.47 : 0.9
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: self.valueFont,
            .foregroundColor: NSColor.white.withAlphaComponent(valueAlpha),
        ]
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: self.labelFont,
            .foregroundColor: NSColor.white.withAlphaComponent(labelAlpha),
        ]
        let providerMark = self.providerMark(
            for: presentation.provider,
            isStale: presentation.isStale)
        let layout = self.layout
        let menuBarImage = NSImage(size: layout.imageSize, flipped: true) { _ in
            providerMark.draw(in: layout.iconFrame)
            self.drawCentered(
                slot1,
                centerX: layout.sessionCenterX,
                y: layout.valueY,
                attributes: valueAttributes)
            self.drawCentered(
                slot2,
                centerX: layout.weeklyCenterX,
                y: layout.valueY,
                attributes: valueAttributes)
            self.drawCentered(
                slot1Label,
                centerX: layout.sessionCenterX,
                y: layout.labelY,
                attributes: labelAttributes)
            self.drawCentered(
                slot2Label,
                centerX: layout.weeklyCenterX,
                y: layout.labelY,
                attributes: labelAttributes)
            if presentation.isStale {
                self.drawCentered(
                    "!",
                    centerX: layout.staleCenterX,
                    y: layout.valueY,
                    attributes: valueAttributes)
            }
            return true
        }
        menuBarImage.isTemplate = false

        let providerName = AIQuotaProduct.displayName(for: presentation.provider)
        let staleText = presentation.isStale ? "，数据过旧" : ""
        let accessibility = "\(providerName)，\(slot1Label) 已使用 \(slot1)，\(slot2Label) 已使用 \(slot2)\(staleText)"
        return AIQuotaStatusTitle(
            menuBarImage: menuBarImage,
            accessibilityLabel: accessibility,
            statusItemLength: self.statusItemLength)
    }

    private static func drawCentered(
        _ text: String,
        centerX: CGFloat,
        y: CGFloat,
        attributes: [NSAttributedString.Key: Any])
    {
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: centerX - size.width / 2, y: y),
            withAttributes: attributes)
    }

    private static func providerMark(for provider: UsageProvider, isStale: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let visualStyle = AIQuotaProduct.visualStyle(for: provider)
        let baseImage = visualStyle?.menuBarSystemSymbolName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: AIQuotaProduct.displayName(for: provider))
        } ?? ProviderBrandIcon.image(for: provider)
        guard let providerImage = baseImage?.copy() as? NSImage else {
            assertionFailure("Missing provider brand icon for \(provider.rawValue)")
            return NSImage(size: size)
        }
        let shouldTintWhite = providerImage.isTemplate
        providerImage.isTemplate = false

        let image = NSImage(size: size, flipped: false) { rect in
            providerImage.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: isStale ? 0.52 : 1)
            if shouldTintWhite {
                let tint = if AIQuotaProduct.isActive,
                              let color = visualStyle?.menuBarIconTint
                {
                    NSColor(deviceRed: color.red, green: color.green, blue: color.blue, alpha: 1)
                } else {
                    NSColor.white
                }
                tint.setFill()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
