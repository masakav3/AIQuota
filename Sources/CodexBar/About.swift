import AppKit

struct AboutPanelPresentation: Equatable {
    let applicationName: String
    let applicationVersion: String
    let author: String

    static func make(shortVersion: String?, build: String?, isAIQuota: Bool) -> Self {
        let version = shortVersion.flatMap { $0.isEmpty ? nil : $0 } ?? "–"
        let normalizedBuild = build.flatMap { $0.isEmpty ? nil : $0 }
        let versionString = normalizedBuild.map { "\(version) (\($0))" } ?? version
        return Self(
            applicationName: isAIQuota ? AIQuotaProduct.productName : "CodexBar",
            applicationVersion: versionString,
            author: isAIQuota ? "matype" : "Peter Steinberger")
    }
}

@MainActor
func showAbout() {
    NSApp.activate(ignoringOtherApps: true)

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let presentation = AboutPanelPresentation.make(
        shortVersion: version,
        build: build,
        isAIQuota: AIQuotaProduct.isActive)
    let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "CodexBuildTimestamp") as? String
    let gitCommit = Bundle.main.object(forInfoDictionaryKey: "CodexGitCommit") as? String

    let separator = NSAttributedString(string: " · ", attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
    ])

    func makeLink(_ title: String, urlString: String) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .link: URL(string: urlString) as Any,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
    }

    let credits: NSAttributedString
    if AIQuotaProduct.isActive {
        credits = NSAttributedString(string: "Author: \(presentation.author)")
    } else {
        let codexBarCredits = NSMutableAttributedString(string: "Peter Steinberger — MIT License\n")
        codexBarCredits.append(makeLink("GitHub", urlString: "https://github.com/steipete/CodexBar"))
        codexBarCredits.append(separator)
        codexBarCredits.append(makeLink("Website", urlString: "https://codexbar.app"))
        codexBarCredits.append(separator)
        codexBarCredits.append(makeLink("Twitter", urlString: "https://twitter.com/steipete"))
        codexBarCredits.append(separator)
        codexBarCredits.append(makeLink("Email", urlString: "mailto:peter@steipete.me"))
        if let buildTimestamp, let formatted = formattedBuildTimestamp(buildTimestamp) {
            var builtLine = "Built \(formatted)"
            if let gitCommit, !gitCommit.isEmpty, gitCommit != "unknown" {
                builtLine += " (\(gitCommit)"
                #if DEBUG
                builtLine += " DEBUG BUILD"
                #endif
                builtLine += ")"
            }
            codexBarCredits.append(NSAttributedString(string: "\n\(builtLine)", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        credits = codexBarCredits
    }

    let options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: presentation.applicationName,
        .applicationVersion: presentation.applicationVersion,
        .version: presentation.applicationVersion,
        .credits: credits,
        .applicationIcon: (NSApplication.shared.applicationIconImage ?? NSImage()) as Any,
    ]

    NSApp.orderFrontStandardAboutPanel(options: options)

    // Remove the focus ring around the app icon in the standard About panel for a cleaner look.
    if let aboutPanel = NSApp.windows.first(where: { $0.className.contains("About") }) {
        removeFocusRings(in: aboutPanel.contentView)
    }
}

private func formattedBuildTimestamp(_ timestamp: String) -> String? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime]
    guard let date = parser.date(from: timestamp) else { return timestamp }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = .current
    return formatter.string(from: date)
}

@MainActor
private func removeFocusRings(in view: NSView?) {
    guard let view else { return }
    if let imageView = view as? NSImageView {
        imageView.focusRingType = .none
    }
    for subview in view.subviews {
        removeFocusRings(in: subview)
    }
}
