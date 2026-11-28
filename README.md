# IPAForge

SwiftUI app for iOS 16+ to browse the App Store, configure Anisette endpoints, and track the current limits of the IPA download workflow.

**Read this in:** English | [Tiếng Việt](./README_vi.md)

### Testing

| iOS Version | Status |
|:---:|:---:|
| 18.7.9 | Tested |
| Other versions | Not verified |

> **Current status:** IPAForge can search public App Store metadata and sign in to Apple's Developer Portal with an Apple ID. It has no App Store login or direct IPA download engine. These sign-in flows are not interchangeable.

## Features

* SwiftUI interface for iOS 16 and later.
* Search the App Store by name or App ID.
* Show the App Store storefront as read-only and use it for searches.
* Automatically choose Vietnamese for the Vietnam App Store storefront and English for other regions; manually switch between Vietnamese and English in Settings.
* View app icons, bundle IDs, developers, and versions.
* Compare an app's Minimum OS metadata with a simulated iPhone 18 Pro running iOS 27.2. This is not a complete device compatibility check and does not enable IPA downloads.
* Manage Anisette servers. Before provisioning, IPAForge discloses that the selected server receives a persistent Anisette identifier, `adi_pb`, and some Apple provisioning exchange values. The server operator can read and retain values sent through it; approval can be revoked.
* Sign in to Apple's Developer Portal with an Apple ID and complete two-factor verification. This is not an App Store download session.
* Securely save and restore the Developer Portal session.
* View sign-in and activity logs.
* Automated builds and tests through GitHub Actions.
* Run an anonymous public API experiment and see its result in Activity Log.

## Library and protocol review

- [ipatool](https://github.com/majd/ipatool) is a MIT-licensed Go project with App Store login, 2FA and download code. Release 2.6.0 added a jailbroken-iOS build, but the latest v2.8.1 has open reports of authentication failing while creating its Unicorn ARM64 emulator on jailbroken iPhones. It is not a Swift SDK and has not been integrated. Desktop success does not establish an ordinary iOS route. See the [research and source review](./Downloader/AUTHENTICATION_RESEARCH.md).
- [Crumb](https://github.com/boierito/Crumb) and [iPadN](https://github.com/mengangs/ipadn) currently claim jailed iOS App Store sign-in and downloads. IPAForge has not independently reproduced those flows. Their source notices disclose GPL, unlicensed upstream, and Apple-derived runtime redistribution questions, so their code has not been integrated into this MIT project.
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

- **Experimental Build** runs only through workflow dispatch. Unit tests are skipped by default; enable the `run_tests` input to test in the Simulator. The app version comes from Xcode's `MARKETING_VERSION` (currently `1.0.0`); the build number is the GitHub Actions run number. The workflow uploads an unsigned IPA artifact named `IPAForge-1.0.0-Unsigned`. It is not a signed installable build.
- The Experimental Build workflow builds IPAForge itself. It does not include ipatool, test App Store authentication, or use a user's Apple Account. No iOS-compatible App Store identity path has been established, so this is not an App Store login test.
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

The project currently retains the [MIT License](./LICENSE.txt). No source code or dependencies from SideStore or AltStore have been added. See the [authentication research](./Downloader/AUTHENTICATION_RESEARCH.md) and [implementation roadmap](./Downloader/ROADMAP.md) before considering an App Store engine.
