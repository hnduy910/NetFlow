# NetFlow 4.2.0 (Build 29)

[![iOS CI](https://github.com/hnduy910/NetFlow/actions/workflows/ci.yml/badge.svg)](https://github.com/hnduy910/NetFlow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://www.swift.org/)

> A local-first SwiftUI app for understanding Wi-Fi and cellular data usage on iPhone and iPad.

NetFlow is an open-source iOS/iPadOS app for monitoring network usage, managing data plans, reviewing history, exporting reports, and understanding whether current cellular usage is likely to exceed a plan. It uses native Apple frameworks, requires no account or backend, and keeps usage history on the device.

## What's new in 4.2.0

- **Usage Forecast** — estimates average cellular usage per day and projected end-of-cycle usage.
- **Plan Risk Indicator** — shows whether current usage is projected to exceed the configured data plan.
- **CSV Export** — exports monthly or yearly usage with stable byte-level columns for analysis.
- **Backup & Restore** — exports/imports settings, data-plan configuration, history, and alerts as JSON.
- **Repository CI** — validates the project and builds against the iOS Simulator SDK on GitHub Actions.

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Features

- Wi-Fi and cellular usage summaries
- Current connection status, local/public IP information, VPN status, and transfer speed
- Daily, monthly, and yearly usage history
- Data-plan limits with daily, monthly, yearly, custom, and unlimited cycles
- Data-plan usage forecasting
- Usage alerts for percentage and remaining-data thresholds
- Monthly and yearly PDF reports
- Monthly and yearly CSV exports
- Local JSON backup and restore
- English and Vietnamese localization
- Light, dark, and system appearance options

## Local-first privacy

NetFlow is designed so usage history and plan data stay on the device. No NetFlow account is required and the project has no third-party package dependency.

Some optional dashboard information — such as public IP, weather, approximate location fallback, and reverse geocoding — uses network services documented in the source. NetFlow does not record browsing content.

## Screenshots

| Dashboard | History |
| --- | --- |
| ![NetFlow Dashboard](docs/images/dashboard.png) | ![NetFlow History](docs/images/history.png) |

| Data Plan | Settings |
| --- | --- |
| ![NetFlow Data Plan](docs/images/plan.png) | ![NetFlow Settings](docs/images/settings.png) |

| System Capabilities |
| --- |
| ![NetFlow System Capabilities](docs/images/capabilities.png) |

## Requirements

- macOS with Xcode 15 or later
- iOS/iPadOS 16 or later
- iPhone, iPad, or Simulator

A physical iPhone is recommended when validating cellular counters, VPN interfaces, and other device-specific networking behavior.

## Run locally

```bash
git clone https://github.com/hnduy910/NetFlow.git
cd NetFlow
open NetFlow.xcodeproj
```

Then select an iPhone/iPad Simulator or a physical device and run with **Product → Run** (`⌘R`). A GitHub connection is not required for the app to run.

For static validation:

```bash
bash Tools/check_project.sh
```

## Releases

GitHub Releases provide source snapshots and an automatically built **unsigned IPA**. Unsigned IPAs require an appropriate sideloading/signing method before installation on a normal device.

## Repository layout

```text
NetFlow/
├── App/
├── Models/
├── Resources/
├── Services/
└── Views/
Tools/
.github/
└── workflows/
```

## Contributing

Bug reports, documentation improvements, focused feature proposals, and pull requests are welcome. Good first contributions include localization improvements, accessibility fixes, test coverage, and small UI refinements.

Please read [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md) before contributing.

## License

NetFlow is available under the [MIT License](LICENSE).
