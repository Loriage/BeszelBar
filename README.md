# BeszelBar

**Your Beszel servers at a glance from the menu bar.**

BeszelBar keeps your [Beszel](https://github.com/henrygd/beszel) infrastructure in view without opening a browser. Connect to your hubs and get a clear, glanceable dashboard for system health, resource usage, containers, and alerts right from the macOS menu bar.

## Installation

### Homebrew

```bash
brew install --cask loriage/tap/beszelbar
```

### Download

Download the latest release from the [Releases](https://github.com/Loriage/BeszelBar/releases) page.

The app is signed and notarized by Apple, so macOS should recognize it as a trusted build when you install it.

### Build from source

```bash
# Requires Xcode 15+ and xcodegen
brew install xcodegen
git clone https://github.com/Loriage/BeszelBar.git
cd BeszelBar
./build.sh
open build/Release/BeszelBar.app
```

## Screenshot

<img src="screenshot.png" width="50%" alt="BeszelBar Screenshot">

## Features

- **Live system cards** — See all your servers with status indicators, CPU, memory, and disk at a glance
- **Rich system details** — Hover for detailed metrics including temperature, uptime, and usage bars
- **Container monitoring** — View Docker containers with health status, resource usage, and image info
- **Alert notifications** — Active alerts displayed prominently with triggering conditions
- **Multi-hub support** — Connect multiple Beszel instances and switch between them instantly
- **Native performance** — Built with SwiftUI and AppKit for minimal resource usage
- **Secure authentication** — Credentials stored safely in macOS Keychain
- **Auto-refresh** — Configurable polling interval from 10 seconds to 5 minutes

## Setup

1. Launch BeszelBar
2. Click the menu bar icon and open **Settings**
3. Add your Beszel hub URL, email, and password
4. Your servers will appear in the menu bar dropdown

BeszelBar supports both password and JWT token authentication. Tokens are automatically refreshed when needed.

## Requirements

- macOS 14.0 (Sonoma) or later
- A running [Beszel](https://github.com/henrygd/beszel) hub instance

## License

MIT License — see [LICENSE](LICENSE) for details.

## Releasing on Homebrew

BeszelBar should be distributed as a Homebrew `cask`, not a formula, because it ships as a macOS `.app`.

1. Create a tap repo named `homebrew-tap`.
2. Copy `dist/beszelbar.rb` into `Casks/beszelbar.rb` in that tap repo after each release.
3. Push a Git tag like `v1.0.0` on this repo to trigger `.github/workflows/release.yml`.
4. The workflow uploads `BeszelBar-1.0.0.zip` to the GitHub release and generates the matching cask file.

For local preparation before tagging:

```bash
chmod +x scripts/release-cask.sh
./scripts/release-cask.sh 1.0.0
```

The script writes `dist/BeszelBar-1.0.0.zip`, prints the SHA256, and emits the cask body you can publish in the tap.

### Signing and notarization

For a release that opens cleanly on macOS, sign with Developer ID and notarize before uploading the archive.

Local release script environment variables:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Bruno DURAND (VZFD28P342)"
export APP_STORE_CONNECT_API_KEY_P8="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
export APP_STORE_CONNECT_KEY_ID="ABC123XYZ"
export APP_STORE_CONNECT_ISSUER_ID="00000000-0000-0000-0000-000000000000"
./scripts/sign-and-notarize.sh 1.0.0
```

GitHub Actions secrets for automated signed releases:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APP_STORE_CONNECT_API_KEY_P8`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

## Acknowledgments

- [Beszel](https://github.com/henrygd/beszel) — Lightweight server monitoring hub
