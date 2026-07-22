import AppKit
import CodexBarCore
import SwiftUI

private struct MiniMaxUsageChartMenuView: View {
    let dashboard: InlineUsageDashboardModel
    let width: CGFloat

    var body: some View {
        InlineUsageDashboardContent(model: self.dashboard)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: self.width, alignment: .leading)
    }
}

extension StatusItemController {
    static let miniMaxUsageChartID = "miniMaxUsageChart"

    @discardableResult
    func appendMiniMaxUsageChartItem(
        to submenu: NSMenu,
        provider: UsageProvider,
        width: CGFloat) -> Bool
    {
        guard provider == .minimax,
              let dashboard = self.menuCardModel(for: provider)?.inlineUsageDashboard
        else { return false }

        if !self.menuCardRenderingEnabledForController {
            let item = NSMenuItem()
            item.isEnabled = false
            item.representedObject = Self.miniMaxUsageChartID
            item.toolTip = provider.rawValue
            submenu.addItem(item)
            return true
        }

        let view = MiniMaxUsageChartMenuView(dashboard: dashboard, width: width)
        let hosting = MenuHostingView(rootView: view)
        hosting.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: self.hostedSubviewFittingHeight(for: hosting, width: width)))

        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = false
        item.representedObject = Self.miniMaxUsageChartID
        item.toolTip = provider.rawValue
        submenu.addItem(item)
        return true
    }
}
