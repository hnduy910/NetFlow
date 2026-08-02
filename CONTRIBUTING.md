# Contributing to NetFlow

Thank you for taking the time to improve NetFlow. Bug reports, documentation fixes, accessibility improvements, localization updates, and focused code changes are welcome.

## Before you start

- Search existing issues and pull requests before opening a new one.
- For a large feature or architectural change, open an issue first so the scope can be discussed.
- Never commit passwords, signing certificates, provisioning profiles, API keys, or device-specific personal data.

## Local setup

1. Install Xcode 15 or later on macOS.
2. Open `NetFlow.xcodeproj` (or the project generated from `project.yml`).
3. Select an iPhone, iPad, or Simulator destination.
4. Select your development team when signing is required.
5. Build and run with **Product → Run** (`⌘R`).

NetFlow uses Apple's native frameworks and does not require CocoaPods or third-party packages. Network values, Wi-Fi information, background refresh, and entitlements can behave differently on a Simulator; validate device-specific behavior on a physical device when needed.

## Development workflow

1. Fork the repository and create a focused branch from `main`.
2. Make the smallest change that solves the issue.
3. Keep user-visible text localized consistently in English and Vietnamese.
4. Preserve the app's local-first privacy behavior and avoid adding unnecessary network services.
5. Build the app and test the affected flow on an appropriate Simulator or device.
6. Update the README or screenshots when a user-visible feature changes.
7. Open a pull request with a concise summary, testing notes, and screenshots for UI changes.

## Pull request checklist

- [ ] The change is limited to the stated purpose.
- [ ] The project builds successfully in Xcode.
- [ ] Relevant flows were tested on a Simulator or device.
- [ ] Localization and accessibility were considered.
- [ ] No secrets or personal data are included.
- [ ] Documentation and screenshots are updated when needed.

## Bug reports and feature requests

Include the device or Simulator model, iOS version, Xcode version, exact steps to reproduce, and any relevant console output. Redact identifiers and private data before attaching logs or screenshots.

