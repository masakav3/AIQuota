# AI Quota

AI Quota is a macOS menu-bar app for keeping AI coding quotas visible without opening each provider's dashboard.

It focuses on five providers:

- Codex
- Claude
- Kimi
- MiniMax
- GLM (z.ai)

The compact menu-bar item rotates through providers and shows the current short-window and weekly usage percentages. Opening the menu reveals quota windows, reset times, account state, and provider-specific usage details.

## Highlights

- Native macOS menu-bar interface
- Short-window and weekly quota percentages at a glance
- Fixed-width rotating status item for a stable menu-bar layout
- Provider-specific icons and usage colors
- Detailed secondary menus for local token activity and hourly usage
- Automatic refresh, launch at login, and quota warning notifications
- Local reuse of supported CLI, OAuth, browser, and API-key credentials

## Requirements

- macOS 14 or later
- Xcode with Swift 6.2 or later for source builds

## Build

```bash
Scripts/package_ai_quota.sh
open "AI Quota.app"
```

The packaging script creates a universal macOS application and a ZIP archive under `dist/`.

## Provider setup

Configuration details are available for [Codex](docs/codex.md), [Claude](docs/claude.md), [Kimi](docs/kimi.md), [MiniMax](docs/minimax.md), and [GLM/z.ai](docs/zai.md).

## Privacy

AI Quota reads supported provider credentials and local activity from their existing local sources. Credentials stay on the Mac and are used only to request data from the corresponding provider. Build products, local configuration, and credentials are not committed to this repository.

## Project status

AI Quota is an early public preview. Provider APIs and authentication flows can change, so some integrations may occasionally require signing in again.

## Credits

AI Quota is a focused customization of [CodexBar](https://github.com/steipete/CodexBar), imported from the v0.45.2 codebase. Thanks to Peter Steinberger and the CodexBar contributors for the provider integrations and application foundation.

The original MIT copyright and license are preserved in [LICENSE](LICENSE).

## Author

matype

## License

MIT. See [LICENSE](LICENSE).
