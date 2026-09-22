# Changelog

All notable changes to NetFlow are documented here.

## [4.2.0] - 2026-09-22

### Added
- Data-plan usage forecasting based on the current cycle's measured cellular usage.
- Projected end-of-cycle usage, average daily usage, and an over-limit indicator.
- Monthly and yearly CSV exports using stable machine-readable byte columns.
- JSON backup and restore for settings, data-plan configuration, usage history, and alerts.
- GitHub Actions checks for static validation and an unsigned iOS build.
- Issue templates for bug reports and feature requests.

### Changed
- Updated the app version to 4.2.0 (Build 29).
- Expanded the repository documentation around local-first behavior and development.

## [4.1.12] - 2026-08-12

### Changed
- Improved location selection and reverse-geocoded display names.
- Refined cellular plan status coloring.
- Improved public-IP and VPN state handling.
- Fixed data-plan cycle resets, midnight sample splitting, persistence migration, and localization coverage.
