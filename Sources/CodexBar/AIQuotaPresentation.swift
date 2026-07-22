import CodexBarCore
import Foundation

struct AIQuotaMetric: Equatable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    init(label: String, window: RateWindow) {
        self.label = label
        self.usedPercent = min(100, max(0, window.usedPercent))
        self.resetsAt = window.resetsAt
    }

    var percentText: String {
        "\(Int(self.usedPercent.rounded()))%"
    }
}

struct AIQuotaPresentation: Equatable {
    let provider: UsageProvider
    let slot1: AIQuotaMetric?
    let slot2: AIQuotaMetric?
    let isStale: Bool

    init(
        provider: UsageProvider,
        slot1: AIQuotaMetric?,
        slot2: AIQuotaMetric?,
        isStale: Bool)
    {
        self.provider = provider
        self.slot1 = slot1
        self.slot2 = slot2
        self.isStale = isStale
    }

    init(
        provider: UsageProvider,
        session: AIQuotaMetric?,
        weekly: AIQuotaMetric?,
        isStale: Bool)
    {
        self.init(provider: provider, slot1: session, slot2: weekly, isStale: isStale)
    }

    var session: AIQuotaMetric? {
        self.slot1
    }

    var weekly: AIQuotaMetric? {
        self.slot2
    }

    static func make(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        isStale: Bool) -> Self
    {
        let selected = self.selectedCandidates(provider: provider, snapshot: snapshot)
        let metrics = selected.enumerated().map { index, candidate in
            AIQuotaMetric(
                label: candidate.forcedLabel ?? self.label(for: candidate.window, slotIndex: index),
                window: candidate.window)
        }
        return Self(
            provider: provider,
            slot1: metrics.first,
            slot2: metrics.count > 1 ? metrics[1] : nil,
            isStale: isStale)
    }

    var menuBarPercentText: String {
        let slot1Text = self.slot1?.percentText ?? "--"
        let slot2Text = self.slot2?.percentText ?? "--"
        return "\(slot1Text)  \(slot2Text)\(self.isStale ? " !" : "")"
    }

    private struct Candidate {
        let window: RateWindow
        let forcedLabel: String?
        let sourceIndex: Int
    }

    private static func selectedCandidates(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> [Candidate]
    {
        guard let snapshot else { return [] }
        let candidates = self.candidates(provider: provider, snapshot: snapshot)
        guard !candidates.isEmpty else { return [] }

        var selectedIndexes: [Int] = []
        self.appendBestCandidate(
            to: &selectedIndexes,
            candidates: candidates,
            matching: { minutes in (60...720).contains(minutes) },
            targetMinutes: 300)
        self.appendBestCandidate(
            to: &selectedIndexes,
            candidates: candidates,
            matching: { $0 == 7 * 24 * 60 },
            targetMinutes: 7 * 24 * 60)
        self.appendBestCandidate(
            to: &selectedIndexes,
            candidates: candidates,
            matching: { minutes in (721...2160).contains(minutes) },
            targetMinutes: 24 * 60)
        self.appendBestCandidate(
            to: &selectedIndexes,
            candidates: candidates,
            matching: { minutes in ((28 * 24 * 60)...(31 * 24 * 60)).contains(minutes) },
            targetMinutes: 30 * 24 * 60)

        for index in candidates.indices where selectedIndexes.count < 2 && !selectedIndexes.contains(index) {
            selectedIndexes.append(index)
        }

        return selectedIndexes.map { candidates[$0] }.sorted { lhs, rhs in
            switch (lhs.window.windowMinutes, rhs.window.windowMinutes) {
            case let (left?, right?):
                if left != right { return left < right }
                return lhs.sourceIndex < rhs.sourceIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.sourceIndex < rhs.sourceIndex
            }
        }
    }

    private static func appendBestCandidate(
        to selectedIndexes: inout [Int],
        candidates: [Candidate],
        matching: (Int) -> Bool,
        targetMinutes: Int)
    {
        guard selectedIndexes.count < 2 else { return }
        let bestIndex = candidates.indices
            .filter { index in
                guard !selectedIndexes.contains(index),
                      let minutes = candidates[index].window.windowMinutes
                else { return false }
                return matching(minutes)
            }
            .min { lhs, rhs in
                let leftDistance = abs((candidates[lhs].window.windowMinutes ?? 0) - targetMinutes)
                let rightDistance = abs((candidates[rhs].window.windowMinutes ?? 0) - targetMinutes)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return candidates[lhs].sourceIndex < candidates[rhs].sourceIndex
            }
        if let bestIndex {
            selectedIndexes.append(bestIndex)
        }
    }

    private static func candidates(provider: UsageProvider, snapshot: UsageSnapshot) -> [Candidate] {
        if provider == .minimax,
           let minimaxUsage = snapshot.minimaxUsage
        {
            let services = minimaxUsage.orderedQuotaServices.filter {
                $0.isPrimaryTextQuotaLane && !$0.isUnlimited
            }
            if !services.isEmpty {
                return services.enumerated().map { index, service in
                    Candidate(
                        window: RateWindow(
                            usedPercent: service.percent,
                            windowMinutes: self.windowMinutes(for: service),
                            resetsAt: service.resetsAt,
                            resetDescription: service.resetDescription),
                        forcedLabel: nil,
                        sourceIndex: index)
                }
            }
        }

        let directCandidates = [snapshot.primary, snapshot.secondary, snapshot.tertiary]
            .enumerated()
            .compactMap { index, window -> Candidate? in
                guard let window, !window.isSyntheticPlaceholder else { return nil }
                return Candidate(window: window, forcedLabel: nil, sourceIndex: index)
            }
        let namedCandidates = (snapshot.extraRateWindows ?? [])
            .enumerated()
            .compactMap { index, namedWindow -> Candidate? in
                guard !namedWindow.window.isSyntheticPlaceholder else { return nil }
                return Candidate(
                    window: namedWindow.window,
                    forcedLabel: self.inferredLabel(from: "\(namedWindow.id) \(namedWindow.title)"),
                    sourceIndex: directCandidates.count + index)
            }
        let realCandidates = directCandidates + namedCandidates
        guard provider == .kimi else {
            return realCandidates
        }

        let semanticWindows = MenuBarLayoutSemanticWindowResolver.windows(
            provider: provider,
            snapshot: snapshot)
        var kimiCandidates: [Candidate] = []
        if let session = semanticWindows.session {
            kimiCandidates.append(Candidate(window: session, forcedLabel: nil, sourceIndex: 0))
        }
        if let weekly = semanticWindows.weekly {
            kimiCandidates.append(Candidate(
                window: weekly,
                forcedLabel: "WEEK",
                sourceIndex: kimiCandidates.count))
        }
        for candidate in realCandidates where !kimiCandidates.contains(where: { $0.window == candidate.window }) {
            kimiCandidates.append(Candidate(
                window: candidate.window,
                forcedLabel: candidate.forcedLabel,
                sourceIndex: kimiCandidates.count))
        }
        return kimiCandidates
    }

    private static func windowMinutes(for service: MiniMaxServiceUsage) -> Int? {
        let normalized = service.windowType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "today", "daily", "今日":
            return 24 * 60
        case "weekly", "每周":
            return 7 * 24 * 60
        case "monthly", "每月":
            return 30 * 24 * 60
        default:
            break
        }

        let components = normalized.split(whereSeparator: \.isWhitespace)
        guard components.count >= 2, let value = Int(components[0]) else { return nil }
        return switch components[1] {
        case "minute", "minutes", "min", "mins", "m", "分钟": value
        case "hour", "hours", "h", "hr", "hrs", "小时": value * 60
        case "day", "days", "d", "天": value * 24 * 60
        default: nil
        }
    }

    private static func label(for window: RateWindow, slotIndex: Int) -> String {
        if let minutes = window.windowMinutes {
            switch minutes {
            case 300:
                return "5H"
            case 1440:
                return "DAY"
            case 10080:
                return "WEEK"
            case (28 * 24 * 60)...(31 * 24 * 60):
                return "MONTH"
            default:
                if minutes.isMultiple(of: 24 * 60) {
                    return "\(minutes / (24 * 60))D"
                }
                if minutes.isMultiple(of: 60) {
                    return "\(minutes / 60)H"
                }
                return "\(minutes)M"
            }
        }

        if let inferred = self.inferredLabel(from: window.resetDescription) {
            return inferred
        }
        return "SLOT\(slotIndex + 1)"
    }

    private static func inferredLabel(from resetDescription: String?) -> String? {
        guard let resetDescription else { return nil }
        let normalized = resetDescription.lowercased()
        if normalized.contains("5-hour") || normalized.contains("5 hour") || normalized.contains("5 小时") {
            return "5H"
        }
        if normalized.contains("weekly") || normalized.contains("week") {
            return "WEEK"
        }
        if normalized.contains("monthly") || normalized.contains("month") {
            return "MONTH"
        }
        if normalized.contains("daily") || normalized.contains("today") {
            return "DAY"
        }
        return nil
    }
}

struct AIQuotaRotation: Equatable {
    private(set) var providers: [UsageProvider]
    private var index: Int

    init(providers: [UsageProvider]) {
        self.providers = providers
        self.index = 0
    }

    var current: UsageProvider? {
        guard !self.providers.isEmpty else { return nil }
        return self.providers[self.index % self.providers.count]
    }

    @discardableResult
    mutating func advance() -> UsageProvider? {
        guard !self.providers.isEmpty else { return nil }
        self.index = (self.index + 1) % self.providers.count
        return self.current
    }

    mutating func updateProviders(_ providers: [UsageProvider]) {
        let previous = self.current
        self.providers = providers
        if let previous, let previousIndex = providers.firstIndex(of: previous) {
            self.index = previousIndex
        } else {
            self.index = 0
        }
    }
}
