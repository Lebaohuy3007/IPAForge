# App Store IPA Downloader: implementation plan

## Current state

- `AppStoreService` searches and looks up public App Store metadata through the iTunes Search API.
- `AppDetailView` routes a normal download tap into the in-app queue. `DownloadService` now runs an asynchronous provider, saves the returned IPA in app Documents, verifies the ZIP signature, and exposes the result to the export screen.
- `AppStoreDownloadService` is the provider boundary for an in-process ipatool/Crumb-compatible engine. The backend URL approach was removed; no Apple private key is embedded in the iOS app.
- `DownloadTask` has progress/status fields, and the provider reports the completed transfer size to the queue. A streaming delegate is still needed for granular progress updates.
- `ExportService` checks for an `.ipa` ZIP signature and the detail screen can share a file URL when a completed task has one.
- Apple sign-in currently uses StosSign for Developer Portal sessions. The encrypted account record contains that session; it does not save the Apple password or an ipatool App Store session.

## App Store sign-in feasibility

The upstream `pkg/appstore.AppStore` interface exposes `Login`, `AccountInfo`, `Revoke`, `Download`, and other App Store operations. `LoginInput` accepts an email, password, and optional 2FA code, so a small Go adapter can expose a Swift-friendly login flow without changing IPAForge's separate StosSign Developer Portal login.

The adapter route is to wrap a pinned ipatool API in a small Go package with simple exported methods and bind that package into the iOS app with `gomobile`. Keep the Go object behind a Swift protocol so the UI and download queue do not depend on generated Go types. App Store session data must use an iOS Keychain-backed adapter; never log the returned `Account`, because ipatool's account model contains a password field.

There is one concrete blocker to verify before treating this as feasible: the current upstream `nativeLogin` still calls `Machine.MacAddress()` to form the Store machine identity, and `Download` also calls it before requesting the package. The default `Machine` implementation reads network interfaces via `net.Interfaces()`. Apple masks hardware MAC addresses from ordinary iOS apps, so the desktop implementation cannot be assumed to work on iOS. Do not fabricate or substitute an address. The upstream README's statement that iOS is supported does not by itself prove that login and downloads work inside a normal iOS app. Confirm with upstream or an upstream-supported iOS machine implementation, then test on a real device. If no supported method exists, stop this route rather than building around a fake identifier.

The native authentication path also provisions and persists Store Anisette/AMD state separately from this app's existing Anisette server setting. It must be reviewed for iOS compatibility and stored in the app's Keychain; the existing Developer Portal/StosSign session and Anisette server selection are not automatically reusable for App Store authentication.

Builds and simulator checks should run on the repository's GitHub Actions macOS/Xcode runner, not in this workspace. The existing Experimental Build workflow already builds the iOS app on that runner, but it does not yet build or link an ipatool framework. Add the Go wrapper and `gomobile bind` steps to an Actions job after the wrapper is ready. The user is willing to install and test an IPA on a real device, which is needed to check login and machine identity; a simulator build alone cannot prove those work.

## What ipatool offers

The upstream README describes ipatool as a Go CLI and lists iOS among its supported operating systems. The project also exports `pkg/appstore.AppStore`, with operations for App Store login, lookup, free-app license acquisition, and download. Its download API accepts an account, app, platform, output path, context, and progress reporter, and returns the destination and SINF records.

The package is not a drop-in Swift dependency. Its constructor needs keychain, cookie-jar, operating-system, and machine implementations. The current native login provisions Store Anisette state, then still reaches the MAC-dependent login flow; downloads also read the machine MAC. Its App Store login/session flow is separate from this app's StosSign Developer Portal session. The current upstream `main` also declares Go 1.26.5, so the first integration attempt must pin and verify a release or commit rather than follow `main`.

## Recommended next steps

1. **Resolve iOS support and machine identity:** ask upstream whether App Store login/download is supported in a normal iOS app, including the required Store Anisette provisioning and `Machine` implementation. Do not substitute an invented MAC address.
2. **Build a pinned Go-to-iOS spike in GitHub Actions:** add a macOS/Xcode job that installs pinned Go and gomobile toolchains, builds the wrapper for iOS device and simulator targets, and uploads the resulting framework as an artifact. Then package it into an unsigned IPA for the user's real-device login/2FA test.
3. **Session boundary and storage:** keep App Store login separate from StosSign. Store ipatool's account blob only through an iOS Keychain-backed adapter, account for its password field, and support revoke/sign-out.
4. **Swift adapter:** keep `DownloadService` as the app-facing API. Translate progress, cancellation, and errors into `DownloadTask`, and write packages only to app-controlled storage.
5. **Package verification and export:** verify a completed package as a ZIP containing `Payload/*.app/Info.plist`, then offer Share/Save to Files. Remove partial files when a task is cancelled or fails.

## First implementation milestone

The queue and package handling are wired, but the direct App Store engine still needs to be ported into the iOS target. The next implementation must provide Store Anisette/AMD, SAP signing, App Store session handling, license acquisition and FairPlay download inside the app. Do not place Apple credentials or private keys in source code or logs.

## Upstream references

- [ipatool README](https://github.com/majd/ipatool/blob/main/README.md)
- [ipatool App Store API](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore.go)
- [ipatool App Store download implementation](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore_download.go)
- [ipatool Go module](https://github.com/majd/ipatool/blob/main/go.mod)
