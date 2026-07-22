import CodexBarCore
import Foundation

extension UsageStore {
    func refreshKimiCodeLocalUsage(generation: UInt64? = nil) async {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
        else {
            return
        }
        let cacheURL = applicationSupportURL
            .appendingPathComponent(AIQuotaProduct.productName, isDirectory: true)
            .appendingPathComponent("kimi-code-local-usage.json")
        let loadResult: KimiCodeLocalUsageLoadResult?
        if let override = self._test_kimiCodeLocalUsageLoaderOverride {
            loadResult = await override().map {
                KimiCodeLocalUsageLoadResult(
                    snapshot: $0,
                    sourceFingerprint: self.kimiCodeLocalUsageSourceFingerprint ?? "test")
            }
        } else {
            let previousSnapshot = self.kimiCodeLocalUsage
            let previousSourceFingerprint = self.kimiCodeLocalUsageSourceFingerprint
            loadResult = await Task.detached(priority: .utility) {
                try? KimiCodeLocalUsageCache.loadAndPersistIfChanged(
                    homeDirectoryURL: homeDirectoryURL,
                    cacheURL: cacheURL,
                    previousSnapshot: previousSnapshot,
                    previousSourceFingerprint: previousSourceFingerprint)
            }.value
        }
        guard let loadResult,
              self.isCurrentProviderRefreshGeneration(.kimi, generation: generation)
        else {
            return
        }
        self.kimiCodeLocalUsage = loadResult.snapshot
        self.kimiCodeLocalUsageSourceFingerprint = loadResult.sourceFingerprint
    }
}
