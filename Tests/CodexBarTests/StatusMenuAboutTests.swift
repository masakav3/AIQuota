import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func `about menu action opens the application about panel`() {
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let selector = controller.selector(for: .about).0

        #expect(NSStringFromSelector(selector) == "showAboutPanel")
    }
}
