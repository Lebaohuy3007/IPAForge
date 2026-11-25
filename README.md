# IPAForge

SwiftUI app for iOS 16+ to browse the App Store, configure Anisette endpoints, and track the current limits of the IPA download workflow.

**Read this in:** English | [Tiếng Việt](./README_vi.md)

### Testing

| iOS Version | Status |
|:---:|:---:|
| 18.7.9 | Tested |
| Other versions | Not verified |

> **Current status:** IPAForge can search the App Store and sign in to Apple's Developer Portal with an Apple ID. A separate App Store login and IPA downloads have not been implemented. These sign-in flows are not interchangeable.

## Features

* SwiftUI interface for iOS 16 and later.
* Search the App Store by name or App ID.
* Show the App Store storefront as read-only and use it for searches.
* Automatically choose Vietnamese for the Vietnam App Store storefront and English for other regions; manually switch between Vietnamese and English in Settings.
* View app icons, bundle IDs, developers, and versions.
* Manage and customize Anisette servers.
* Sign in to Apple's Developer Portal with an Apple ID and complete two-factor verification. This is not an App Store download session.
* Securely save and restore sign-in sessions.
* View sign-in and activity logs.
* Automated builds and tests through GitHub Actions.

## Library and protocol review

- [ipatool](https://github.com/majd/ipatool) is a MIT-licensed Go project. Its README lists iOS as a supported operating system; its exported `pkg/appstore` API includes App Store login with email, password, and a 2FA code. It is not a Swift SDK. IPAForge has not integrated it. Current upstream login provisions Store Anisette/AMD state, then still requests a machine MAC address; downloads also request that identity. The ordinary iOS app path and storage needs must be verified before using it. The proposed route and blocker are documented in [Downloader/ROADMAP.md](./Downloader/ROADMAP.md).
- [SideStore](https://github.com/SideStore/SideStore) and [AltStore](https://github.com/altstoreio/AltStore) use their own Apple signing and sideloading implementations; both READMEs publish AGPLv3. Their code is not copied into this MIT project. SideStore documentation recommends Anisette v3 and warns against sending account information to Anisette servers. IPAForge follows that separation but has not implemented the full protocol.
- References: [SideStore Anisette](https://docs.sidestore.io/docs/advanced/anisette), [ipatool](https://github.com/majd/ipatool), and [AltStore](https://github.com/altstoreio/AltStore).
- Anisette v3 uses an internal Swift client without adding a dependency or copying third-party library code. `swift-anisette` does not support iOS; `RemoteAnisette` does not declare a license; AnisetteKit publishes AGPL-3.0. These projects are not integrated.
- [StosSign](https://github.com/stossy11/StosSign) is a Swift package, not an HTTP service. The project pins revision `01dd7bc4f5084ade9e2ebbc7e338dc2e3f454d77` and links only its API/Auth/Common products. That revision supports iOS 14; this app requires iOS 16. StosSign handles SRP, two-factor authentication, and the Developer Team API. IPAForge passes Anisette v3 headers as `AnisetteData` and stores an encrypted session DTO in its vault. The user confirmed permission from the maintainer; the repository publishes no LICENSE file or license metadata, so this README does not claim a specific public license. Helpers from GetMoreRam that log Anisette payloads are not used.

## Build and test with Xcode

Open `AppStoreIPADownloader.xcodeproj`, select the `AppStoreIPADownloader` scheme, then build and run on iOS 16 or later. To run tests:

```sh
xcodebuild test \
  -project AppStoreIPADownloader.xcodeproj \
  -scheme AppStoreIPADownloader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

The user reported testing on iOS 18.7.9; the device model was not provided. This is a manual test report and does not mean every feature is complete or that the IPA is signed.

Confirm CI status from the latest GitHub Actions run. The Experimental Build workflow uses Xcode 27.2 on the `xcode-27` runner, which must have a compatible iOS Simulator runtime.

## GitHub Actions

- **Experimental Build** runs on pushes to any branch or through workflow dispatch. Unit tests are skipped by default for faster IPA builds; enable the `run_tests` input on a manual run to test in the Simulator. The app version comes from Xcode's `MARKETING_VERSION` (currently `1.0.0`); the build number is the GitHub Actions run number. The workflow uploads an unsigned IPA artifact named `IPAForge-1.0.0-<build>-Unsigned`. It is not a signed installable build.
- GitHub Actions already provides the macOS/Xcode runner for an ipatool integration spike; local Xcode is not required. The current workflow does not yet build an ipatool framework. Once added, its IPA artifact can be installed for your real-device login and machine-identity test.
- **Release Build** runs when pushing a `v*` tag or through workflow dispatch with `release_tag`; it tests, archives an unsigned Release build, and creates a GitHub Release. The artifact is named `AppStoreIPA-Release` and contains an unsigned `.xcarchive.zip`, not an IPA.
- No certificate or secret is needed to compile an unsigned build. Do not add private keys, certificates, or passwords to the repository.

The workflow that creates a GitHub Release requires Actions `contents: write` permission in repository settings. For workflow dispatch, provide a tag such as `v1.0.0`.

## Structure

```text
App/                 SwiftUI app entry
Views/               Login, search, details, downloads, logs, settings, Anisette management
ViewModels/          App environment/settings
Models/              App and download state
Authentication/
Anisette/
AppStore/
Downloader/
Export/
Logging/
Tests/
.github/workflows/   Experimental and release builds
```

## License

The project currently retains the [MIT License](./LICENSE). No source code or dependencies from SideStore or AltStore have been added. Any ipatool integration must preserve its MIT notice and pass the iOS feasibility checks in [Downloader/ROADMAP.md](./Downloader/ROADMAP.md).
