# IPAForge

SwiftUI app for iOS 16+ to browse the App Store, configure Anisette endpoints, and track the current limits of the IPA download workflow.

**Read this in:** English | [Tiếng Việt](./README_vi.md)

### Testing

| iOS Version | Status |
|:---:|:---:|
| 18.7.9 | Tested |
| Other versions | Not verified |

> **Current status:** IPAForge can search the App Store and sign in with an Apple ID. Downloading apps as IPA files has not been implemented. Apple sign-in and related features have not been fully verified with a real account.

## Features

* SwiftUI interface for iOS 16 and later.
* Search the App Store by name or App ID.
* Show the App Store storefront as read-only and use it for searches.
* Choose the app language.
* View app icons, bundle IDs, developers, and versions.
* Manage and customize Anisette servers.
* Sign in with an Apple ID, complete two-factor verification, and select a Developer Team.
* Securely save and restore sign-in sessions.
* View sign-in and activity logs.
* Automated builds and tests through GitHub Actions.

## Library and protocol review

- [ipatool](https://github.com/majd/ipatool) is a MIT-licensed Go tool with an App Store workflow for authentication, purchasing, and downloading. It is a cross-platform CLI, not a Swift/iOS SDK. It has not been integrated or ported because iOS sandbox compatibility, credential lifecycle, two-factor authentication, and Anisette support need to be validated first.
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

The project currently retains the [MIT License](./LICENSE). No source code or dependencies from SideStore or AltStore have been added. A future ipatool integration must preserve its MIT notice and be checked for technical compatibility first.
