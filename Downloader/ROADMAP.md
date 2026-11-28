# App Store Login and IPA Downloader roadmap

For the 2026-11-26 source register, 16-path ranking, elimination rounds, live anonymous API result, and Experiment B checklist, see [AUTHENTICATION_RESEARCH.md](./AUTHENTICATION_RESEARCH.md).

## Current implementation status

- `AppStoreService` searches and looks up public App Store metadata through the iTunes Search API.
- The App Store screen can run an anonymous Search/Lookup experiment and records Experiment A and Experiment B's blocked result in the existing Activity Log.
- The existing `AuthenticationService` and StosSign provider authenticate to Apple's **Developer Portal** and fetch Developer Teams. That session is not an App Store session.
- The IPA download queue uses an in-process provider boundary, saves a returned IPA to app Documents, checks the ZIP signature, and exposes the file to the export screen. A real App Store provider is not integrated.
- App Store Login has not been implemented. There is no separate App Store session vault, no App Store login UI, and no live App Store authentication test.

## App Store Login source review

### ApplePackage

[Lakr233/ApplePackage](https://github.com/Lakr233/ApplePackage) is the closest Swift reference. Its package manifest declares iOS 15+ and MIT, requires the Swift 6.2 package tools version, and depends on OpenSSL, AsyncHTTPClient, ZIPFoundation, Swift Collections, and Swift Log. Its authentication actor retains its SAP signer and cookies across the 2FA continuation. It returns DSID, storefront, password token, cookies, and a password-bearing account model; IPAForge would need to map only required fields into a separate Keychain session, never use the package's JSON account-file persistence or print its `debugDescription`. The package uses Swift language mode 6; compatibility with this Swift 5 app still needs an Xcode build check.

Its current flow is SAP-signed App Store authentication, not the GSA/SRP-6a flow described by ipaverse. The source posts the credential plist over HTTPS with an SAP action signature. `DeviceIdentifier.system()` explicitly fails on iOS; the package exposes a random 12-character fallback and documents that it must be stored and reused. The task requirements prohibit inventing a device identifier, so that fallback cannot be used. Apple documents `identifierForVendor` as an app-vendor identifier that can change after the vendor's apps are removed; the reviewed sources do not establish that it is a valid replacement for the App Store client GUID. IPAForge must not silently substitute it.

The package's iOS deployment declaration is evidence that some package code may compile for iOS, but it does not establish that App Store login succeeds on a normal iOS device with a supported identity. No package dependency was added because the identity requirement is unresolved. Its Swift 6.2 tools-version and language mode also need a build-compatibility check against this app's Xcode project, which currently sets Swift language mode 5.

### ipaverse

[bahattinkoc/ipaverse](https://github.com/bahattinkoc/ipaverse) is a macOS app, not an iOS implementation. Its App Store service uses GrandSlam/SRP-6a, 2FA, a PET bridge to Store credentials, license acquisition, downloads, progress, and SINF patching. The reviewed source imports IOKit and uses `/sbin/ifconfig`/`Process` to read a MAC; it tries the Mac serial next and falls back to a random UUID. Its local Anisette path uses macOS facilities. It cannot be copied into the iOS target unchanged, and the random fallback violates the no-fabricated-identity constraint.

References: [ipaverse AppStoreService.swift](https://github.com/bahattinkoc/ipaverse/blob/main/ipaverse/ipaverse/Services/AppStoreService.swift), [ipaverse README](https://github.com/bahattinkoc/ipaverse/blob/main/README.md).

### ipatool

[majd/ipatool](https://github.com/majd/ipatool) is MIT-licensed Go and provides App Store login, 2FA, account/session, lookup, purchase, and download APIs. Release v2.8.1 is current at this review date. Release v2.6.0 added a jailbroken-iOS binary, but open issues [#680](https://github.com/majd/ipatool/issues/680) and [#682](https://github.com/majd/ipatool/issues/682) report its authentication emulator failing to initialize on jailbroken iPhones. It is not a Swift SDK, and desktop success does not establish a usable ordinary-iOS identity or successful login in IPAForge.

References: [ipatool App Store login source](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore_login.go), [ipatool package API](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore.go), [ipatool module](https://github.com/majd/ipatool/blob/main/go.mod).

## Protocol and security findings

- GSA/SRP-6a and SAP-signed Store authentication are distinct implementation paths in the reviewed projects. Do not combine their headers or session fields without protocol evidence.
- An App Store session needs its own DSID, storefront, password token, cookies, and pod/routing data. StosSign's Developer Portal session is not interchangeable.
- Anisette v3 headers and Store AMD proofs are related device-authentication data, but are not automatically interchangeable. Any provider must be explicitly selected/injected; no fixed remote Anisette endpoint is embedded for App Store login.
- Persist only an App Store session in Keychain. Do not serialize a password-bearing upstream account model to a file, UserDefaults, logs, or test fixtures. Never log passwords, 2FA codes, cookies, tokens, Anisette payloads, or SAP signatures.
- Public iOS `identifierForVendor` is vendor-scoped and may change under documented conditions. The reviewed sources do not prove that it is accepted as the App Store protocol's device identity. Using a random or transformed value would violate this task's requirements.

## App Store Login blocker and next steps

The task explicitly requires no fabricated device identity or Anisette data. ApplePackage's only documented iOS fallback is a generated GUID, while its system identity provider fails on iOS. ipatool and ipaverse do not provide a verified normal-iOS identity path either. Therefore a truthful App Store login cannot be implemented from these references under the current constraints.

Do not add a success-shaped UI, mock login provider, synthetic identity, or claims of completion. Resume implementation only after an iOS-compatible, protocol-supported device identity/authentication path is identified and can be verified on a real device. Then add the independent App Store auth provider/service/session vault, implement 2FA and restore/expiry handling, add mock tests, and run a live login test only with the user's own account. Do not change `experimental.yml` for this milestone.

## IPA download engine status

The queue and package handling are wired, but the direct App Store download engine is not implemented. A real engine still needs App Store authentication, SAP/AMD or other required proofs, license acquisition, download, and FairPlay package handling. The current milestone does not connect App Store Login to that engine, does not implement FairPlay decryption, and does not claim that IPA downloads work.

## Verification record

- Repository/code review: completed for the references linked above.
- App Store Login mock tests: not added; no provider implementation exists to test yet. The v3/experiment mocks cover public API response handling, experiment reporting, and queue/IPA behavior only; they do not authenticate or contact Apple.
- Build compatibility of ApplePackage inside IPAForge: not verified; no dependency was added.
- Live Apple Account authentication: not tested.
- App Store IPA downloads: not part of this login milestone.

## ALL-IN-ONE v3 review — 2026-11-26

### Repository audit

The current project is an Xcode iOS app with deployment target **iOS 16.0** and Swift language mode **5**. The existing workflows are `experimental.yml`, `upload.yml`, and `release.yml`; none was changed for this work.

| Component | Finding | Status |
| --- | --- | --- |
| `AppStoreService.swift` | Calls the public iTunes Search/Lookup API for app metadata. It has no Apple Account authentication, version history, licensing, or IPA URL flow. | IMPLEMENTED (public metadata only) |
| `AppStoreExperimentService.swift` | Runs anonymous Search/Lookup checks, records status in the existing logger, and marks binary access unsupported and Experiment B blocked before credentials. | IMPLEMENTED (no live authentication) |
| `AuthenticationService.swift`, `StosSignAuthenticationProvider.swift` | Sign in to Apple Developer Portal and load Developer Teams. Its session is separate from App Store session cookies, DSID, storefront, password token, and pod data. | IMPLEMENTED (Developer Portal only) |
| `AppStoreDownloadService.swift` | Provider boundary currently throws `directEngineUnavailable`. It does not authenticate, acquire a license, or fetch an IPA. | BLOCKED |
| `DownloadService.swift` | Queue state, provider cancellation, byte-based progress, retry-as-new-task, temporary file cleanup, IPA inspection, and save-after-validation are implemented. No production provider can currently start a real transfer. | PARTIALLY IMPLEMENTED |
| Device Profile and compatibility | App Details now uses a fixed simulated iPhone 18 Pro / iOS 27.2 profile and displays only the Minimum OS result. The Profile screen no longer exposes the custom Device Profile editor. | IMPLEMENTED (fixed simulated minimum-OS check) |
| IPA validation | ZIP entry paths and size are bounded; ZIP entries are streamed and CRC checked; `Payload/*.app/Info.plist`, bundle metadata, and Mach-O architecture are inspected. No package is extracted to an untrusted path. | IMPLEMENTED; no current follow-up syntax/typecheck/runtime result |
| GitHub Actions | Workflows were read and left unchanged. | NOT TESTED |

At the 2026-11-28 follow-up, `command -v swiftc`, a filesystem search, and the Linux test script did not find a Swift compiler in the command-execution environment. `xcodebuild` and the Apple iOS SDK are also absent. Older toolchain/test results elsewhere in this report are historical and do not apply to this follow-up. Do not interpret the local profile as an Xcode Simulator or as device hardware.

### Extended repository research

The following **20 new repository projects** were checked in addition to the three references already documented above. DLiPA's public repository page currently exposes a README/screenshots but no implementation source to audit; its capabilities remain author claims. Known forks, wrappers, and derived projects are marked so they are not counted as independent authentication proofs. At least five materially different implementation patterns appear in the reviewed source (SAP/ipatool-compatible clients, GSA/SRP clients, iPadN's WebKit/WebAssembly SAP + StoreProof path, Apple-framework/ADI emulation, and experimental Mac-ADI/private-protocol clients). Some patterns overlap; these are not five independently verified iOS login solutions.

| Project | Source | Platform | Language | Authentication | Device identity | Download | License | Status | Relevance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Crumb | [README/Credits](https://github.com/boierito/Crumb) | iOS 16.4+ | Swift | README claims Apple ID/2FA; credits ipatool and iPadN | Relies on referenced Store-proof work; no independent supported identity demonstrated here | README claims latest/older version download and export | Mixed third-party terms; README says whole project is not MIT | AUTHOR CLAIM; source and iPadN credits verified | Closest iOS UI reference, but derived code and GPL-2.0-or-later components make direct reuse unsuitable |
| DLiPA | [README](https://github.com/AhmedBafkir/DLiPA) | iOS 13+ (author claim) | Unknown from available source | README claims Apple ID and 2FA | UNKNOWN | README claims latest/older IPA downloads | UNKNOWN; no implementation/license evidence reviewed | AUTHOR CLAIM; NOT TESTED | Cannot use as technical proof because implementation source is not exposed in the inspected repository |
| iPAGet | [README and layout](https://github.com/ipaget/ipaget) | Windows/macOS/Linux desktop | TypeScript, Rust, Go | README credits ipatool for Store auth/download | Desktop/device-management flow; no iOS identity path | Desktop IPA/version manager | CC BY-NC-SA 4.0 | VERIFIED IN README/layout; desktop | Wrapper reference only; license is not compatible with copying into this MIT app |
| ipatool-rs (`Kosthi/ipatool-rs`, mirrored/forked at `urobee/ipatool`) | [README](https://github.com/Kosthi/ipatool-rs), [Rust workspace](https://github.com/Kosthi/ipatool-rs/tree/master/crates), [fork relationship](https://github.com/urobee/ipatool) | macOS/Linux/Windows CLI | Rust | SAP-signed Store login, 2FA, license and download flows (README/source layout) | Runs extracted Apple desktop frameworks in an x86-64 emulator; desktop machine, not iOS hardware | Streaming and Range resume claimed in source/docs | MIT per repository license | SOURCE AVAILABLE; AUTHOR CLAIM; NOT TESTED here | Useful current SAP reference, but the mirror/fork is one code line and its emulator is not an iOS sandbox identity solution |
| a23bc/ipa-downloader | [README/source tree](https://github.com/a23bc/ipa-downloader) | iOS 15+ | Swift | Source tree names SRP-6a, 2FA, and Anisette headers | Requires a local/remote Anisette sidecar; no verified native Store identity shown | README claims encrypted chunk download; purchase requires an iTunes Store private key extracted from iTunes/macOS or a jailbroken device | MIT | SOURCE AVAILABLE; several major requirements are author-documented; NOT TESTED | Useful Swift UI/queue reference, but do not add or distribute an extracted Apple private key |
| ElJoker63/ipa-downloader | [repository](https://github.com/ElJoker63/ipa-downloader) | Desktop | Go with desktop UI | Forked from `majd/ipatool`; same Store protocol family | Inherited from ipatool family; no iOS identity path | Desktop search/purchase/download | MIT | VERIFIED FORK RELATIONSHIP | A fork, not an independent auth result; do not count it as a separate protocol |
| Ranshen1209/IPATool | [README/source tree](https://github.com/Ranshen1209/IPATool) | macOS | Swift/SwiftUI | README describes private-protocol login, 2FA, and session restore | macOS environment; iOS identity unverified | README describes chunking, retry/resume, license and IPA processing | UNKNOWN in inspected repository page | AUTHOR CLAIM; 7-commit prototype; NOT TESTED | Useful architecture ideas only; does not establish an iOS client |
| WaffleStore | [source](https://github.com/nxtcoreee3/WaffleStore), [latest release](https://github.com/nxtcoreee3/WaffleStore/releases), [maintainer status](https://www.nxtcoreee3.online/wafflestore.html) | Jailed iOS 16.4+ | Swift | App Store downgrade/login flow; release 2.3.1 says its backend was fixed for iOS 27 | Not established as a supported identity contract for IPAForge | Release claims IPA retrieval and downgrade | UNKNOWN in inspected repo metadata | Conflicting current status: 2026-10-17 release says fixed; maintainer site currently labels WaffleStore EOL and says old builds no longer work | Crumb lists it as an origin; status conflict means do not rely on it without a real-device check |
| SideStore | [README/source](https://github.com/SideStore/SideStore), [agent/source notes](https://github.com/SideStore/SideStore/blob/develop/AGENTS.md) | iOS/iPadOS | Swift | Personal-account signing/refresh and Anisette for sideloading | Uses its sideloading/device-pairing flow, not App Store purchase identity | Installs/refreshes sideloaded apps; not a Store IPA downloader | AGPL-3.0 | VERIFIED IN SOURCE; fork of AltStore with substantial later changes | Useful only for understanding sideloading/Anisette boundaries; do not reuse AGPL code |
| AltStore | [README](https://github.com/altstoreio/AltStore) | iOS + macOS AltServer | Swift | Personal developer-account signing/refresh | AltServer handles device install/refresh; not Store identity | Sideloads supplied IPAs; not App Store IPA acquisition | AGPL-3.0 | VERIFIED IN SOURCE | Adjacent account flow, not the requested App Store downloader |
| iPadN | [AppleService.swift](https://raw.githubusercontent.com/mengangs/ipadn/main/iPadn-iOS/iPadn/Services/AppleService.swift), [SAPSigner.swift](https://raw.githubusercontent.com/mengangs/ipadn/main/iPadn-iOS/iPadn/Services/SAPSigner.swift), [README](https://github.com/mengangs/ipadn) | iOS/iPadOS 16+ | Swift, WebKit/WebAssembly | Source implements SAP signing, 2FA, Store AMD proof/provisioning | `AppleService.guid` generates a random 12-hex GUID and saves it; `SAPSigner` also derives/randomizes a Store identifier. This violates this task's no-fabricated-identity rule. | README claims search, versions, license, downloads and install | GPL-2.0 (repo badge; Crumb credits GPL-2.0-or-later components) | VERIFIED IN SOURCE for identity path; feature claims from author | Strong technical reference, but cannot copy into this MIT app or use its generated identity |
| ipakeep | [README and implementation layout](https://github.com/seifreed/ipakeep), [auth source](https://github.com/seifreed/ipakeep/tree/main/src/infrastructure/appstore) | macOS/Linux/Windows CLI | Rust | Native Store/SAP or GrandSlam flows; trusted-device 2FA | Executes Apple desktop framework/ADI code in its own ARM64 interpreter and provisions an emulated desktop machine | Downloads authorized encrypted IPAs and adds SINF/metadata | MIT | SOURCE AVAILABLE; author reports tests on desktop; NOT TESTED in IPAForge | Separate and technically rich desktop implementation; emulator/desktop identity cannot be moved into this iOS app |
| OldStore | [README/source tree](https://github.com/pmt1506/OldStore) | Self-hosted Node server/web client | TypeScript/JavaScript | Private StoreAPI login and zero-price license acquisition | Server-side account session; no iOS device identity | Downloads encrypted IPA and inserts SINF/metadata; README says no decryption | No license file verified in inspected repository | AUTHOR CLAIM; code available; NOT TESTED | Server reference, derived from AssppWeb/ipatool architecture; not an in-app provider |
| apple-auth | [README/integration guide](https://github.com/apple-auth/apple-auth), [full docs](https://github.com/apple-auth/apple-auth/blob/main/docs/full-docs.md) | C++20/Swift/Python on multiple OSes | C++, Swift, C, Python | SAP/ADI and Store clients; optional App Store module | README explicitly says iPhone uses Mac ADI, is experimental, and is not recommended | Optional encrypted IPA client requires a special build flag and native dependencies | MIT | VERIFIED IN README/docs; NOT TESTED | Not a supported iPhone identity route; no integration |
| decryptipa | [README](https://github.com/R0GUEEE/decryptipa) | iOS front end plus remote/jailbroken workflows | Swift and helper tools | README describes Apple login/2FA/session import; its supported flow relies on a desktop session or remote components in some cases | Does not demonstrate Store identity generation inside a stock iOS sandbox | Primarily a remote decryption workflow; decryption is out of scope | UNKNOWN in inspected page | AUTHOR CLAIM; NOT TESTED | Helps identify the iOS sandbox limitation; not a download engine to reuse |
| IPADown | [protocol notes](https://github.com/j1ans/IPADown/blob/main/PROTOCOL.md), [current project README](https://github.com/j1ans/IPADown) | Windows/macOS/Linux desktop | Electron, Go, JavaScript | The protocol note says its old unsigned login gets HTTP 403; current bridge calls ipatool | Earlier notes use host MAC as GUID; this is not an iOS identity | Desktop download/install management | UNKNOWN in inspected page | Protocol document explicitly marks old flow obsolete; current bridge is an ipatool wrapper | Useful negative evidence; old protocol snippets must not be treated as a current implementation |
| IPAToolKit | [Package.swift](https://raw.githubusercontent.com/maclub-net/IPAToolKit/main/Package.swift), [AppStoreClient.swift](https://raw.githubusercontent.com/maclub-net/IPAToolKit/main/Sources/IPAToolCore/AppStoreClient.swift), [README](https://github.com/maclub-net/IPAToolKit) | Declares iOS 15+/macOS 14+ | Swift + C | Swift Store client with SAP signing, 2FA, purchase/download | Source lines 185–203 generate a random 6-byte hardware ID and persist it in UserDefaults on non-IOKit platforms, including iOS. Not acceptable under this task. | README/source includes purchase and IPA download calls | Custom license: non-commercial use; commercial license required | VERIFIED IN SOURCE for generated identity and custom license; iOS success NOT TESTED | Closest-looking Swift package is disqualified by its own generated identity path and license constraints |
| ipatool-kit | [repository and crate layout](https://github.com/ipatool-kit/ipatool-kit) | Desktop CLI/TUI/library | Rust | Authenticated Store flows are in `ipatool_kit::store` and purchases modules | No iOS identity path documented | Search/purchase/download of authorized IPAs | MIT per README | SOURCE AVAILABLE; README says it is inspired by ipatool; NOT TESTED | Separate Rust code, same broad protocol family; no direct iOS integration evidence |
| Provision | [README](https://github.com/Dadoum/Provision), [lib source](https://github.com/Dadoum/Provision/tree/main/lib/provision) | Linux tools/server, Android libraries | D, C/C++ | ADI provisioning/Anisette server used by other clients | README example creates random machine UUIDs and describes the device as a Mac; this is not a real iOS identity | Removed `sideload_ipa` code; current project is not an IPA downloader | LGPL terms in repository | VERIFIED IN SOURCE for desktop/Linux design; not an iOS implementation | Useful to understand remote Anisette provisioning; not a compliant in-app identity source |

#### Repository relationships and what counts as independent

- `ElJoker63/ipa-downloader` is explicitly a fork of `majd/ipatool`; iPAGet credits and wraps ipatool; OldStore says it is based on AssppWeb, which itself is based on ipatool/Asspp; current IPADown says its auth bridge calls ipatool. `Kosthi/ipatool-rs` and `urobee/ipatool` are the same fork family. Count these as one ipatool-derived protocol family, not six independent auth proofs.
- SideStore is an AltStore fork (with later rewrites); neither repository is an App Store IPA downloader.
- Crumb states that it builds on WaffleStore and ipatool and credits iPadN's GPL StoreProof/SAP work. WaffleStore's latest release and maintainer's current EOL page disagree, so treat runtime status as unverified.
- DLiPA's README is not code evidence. Ranshen and several projects describe private protocols, but no local build or real-account test was run here.
- Across all 20 new projects, the source supports at least five materially different implementation patterns, with overlaps, not five validated solutions: ipatool-compatible SAP clients; GSA/SRP clients; iPadN's WebKit/WebAssembly SAP + StoreProof; desktop Apple-framework/ADI emulation; and experimental Mac-ADI/private-protocol clients.

### Current protocol evidence and Device Identity decision

The most relevant current community protocol report is [ipatool issue #642](https://github.com/majd/ipatool/issues/642). A contributor reports that, on a Mac, Configurator's `AMSAnisette` type-2 `X-Apple-AMD` and `X-Apple-AMD-M` headers are distinct from AuthKit's `X-Apple-I-MD*`; adding local Store AMD proof plus a SAP signature allowed their patched client to log in and list purchases. A later comment reports downloading an already-owned IPA, but says new-license acquisition was not verified and the IPA remained FairPlay-encrypted. The report is environment-specific and is not a guarantee for every account or endpoint. It shows why IPAForge's remote Anisette v3 headers cannot simply be relabeled as Store AMD. ipatool 2.8.0/2.8.1 restore desktop authentication, but latest iOS issue reports still fail at Unicorn emulator setup; this is not an ordinary-iOS proof.

The blockers are concrete:

1. Apple documents `UIDevice.identifierForVendor` as vendor-scoped, with a documented reset condition; none of the reviewed primary sources says it is the Store protocol's accepted GUID or hardware ID. It cannot be silently substituted.
2. The current Swift candidate IPAToolKit explicitly generates and persists random hardware bytes on iOS. iPadN generates a random GUID and derives/randomizes Store identifiers. Both are ruled out by this task.
3. `apple-auth` says its iPhone path uses Mac ADI and is experimental/not recommended. ipatool's current iOS binary targets jailbroken devices; open issues #680 and #682 report an ARM64 emulator failure before authentication. Desktop emulators such as ipatool-rs/ipakeep do not establish a real iOS device identity.
4. The public Anisette endpoint in IPAForge only returns Anisette v3/AuthKit data. The reviewed current protocol report distinguishes those headers from Store AMD. No reviewed source provides an Apple-supported public iOS API for Store AMD/SAP device proof in this app's sandbox.

**Decision: App Store Authentication remains BLOCKED.** Keep the Developer Portal/StosSign flow separate. Do not add App Store login/session classes, a success-shaped UI, or a fake provider until an iOS-compatible identity path is demonstrated on a physical device with the user's own account.

### Official technical sources

| Source | Evidence used |
| --- | --- |
| [Xcode SDK and system requirements](https://developer.apple.com/xcode/system-requirements/) | Current page lists Xcode 27.3 beta 2 with iOS 27.3 SDK, Xcode 27.2 with iOS 27.2 SDK, deployment target support through iOS 27, iOS device support from 17, and iOS Simulator support from 17. The project can keep its iOS 16 deployment target. |
| [Run on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices) | Xcode Simulator runs on a Mac and does not reproduce all physical-device features/performance; device-specific behavior needs real-device verification. |
| [Managing simulated devices / runtimes](https://developer.apple.com/documentation/Xcode/managing-your-simulated-and-physical-devices-in-device-hub?changes=la_7_9&language=objc) and [adding runtimes](https://developer.apple.com/documentation/safari-developer-tools/adding-additional-simulators?changes=_4) | A real Simulator is a Device Hub configuration with an installed OS runtime. `DeviceProfile` is only local input data and cannot create that runtime. |
| [MinimumOSVersion](https://developer.apple.com/documentation/BundleResources/Information-Property-List/MinimumOSVersion) | Minimum required OS is a string in app metadata; Xcode normally derives it from Deployment Target. |
| [UIRequiredDeviceCapabilities](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequireddevicecapabilities) | Array entries mean required hardware; dictionary `true` means required and `false` means the device must not have that feature. Compatibility code follows these semantics. |
| [UIDeviceFamily](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html) | Official archived reference identifies family `1` as iPhone/iPod touch and `2` as iPad. |
| [identifierForVendor](https://developer.apple.com/documentation/UIKit/UIDevice/identifierForVendor) | The value is scoped to the app vendor and can change after all that vendor's apps are removed and later reinstalled. It is not documented as an App Store client identity. |
| [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), [XNU Mach-O CPU subtypes](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/machine.h), and [LLVM Mach-O subtypes](https://llvm.org/doxygen/BinaryFormat_2MachO_8h.html) | iOS 27 introduces `arm64e.x1`; Apple XNU/LLVM distinguish ARM64, ARM64E, and ARM64E.X1 CPU subtypes. These slices must not be collapsed into one `arm64` label. |
| [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) | Apple provides Keychain APIs for small sensitive values; an eventual App Store session vault should store only necessary session material there. |
| [URLSession download/resume](https://developer.apple.com/documentation/foundation/pausing-and-resuming-downloads) | `URLSessionDownloadTask` can return resume data on cancellation, but resume is conditional on server byte-range and validator support. No resume implementation is claimed yet. |
| [ZIPFoundation Archive API](https://github.com/weichsel/ZIPFoundation/blob/development/Sources/ZIPFoundation/Archive.swift) and [license](https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE) | ZIPFoundation provides streaming extraction and CRC checks; the inspector compares the returned CRC with each ZIP entry's declared checksum. Library is MIT and supports Apple platforms. |

### Implementation details

#### DeviceProfile and compatibility

- A local `DeviceProfile` preset defaults to iPhone 18 Pro / iOS 27.2; it has no connection to Apple authentication.
- App Details compares the catalog Minimum OS against that fixed preset. The overall Unknown banner and checks whose metadata is unavailable are hidden; the Profile screen no longer links to the custom profile editor.
- The compatibility checker compares minimum OS, `UIDeviceFamily`, required/prohibited capabilities, `CFBundleSupportedPlatforms`, and Mach-O architecture. Any failed requirement yields Incompatible; incomplete or malformed metadata yields Unknown; Compatible is only returned when all criteria are known and pass.
- The public iTunes catalog currently provides Minimum OS but not the other device requirements. App Details therefore evaluates that one criterion and hides the overall Unknown result instead of implying a complete device-compatibility check. The local IPA inspector still reads additional fields rather than guessing missing metadata.
- IPAForge's deployment target remains iOS 16.0. This profile is not an iOS 27 Simulator, test device, or Store identity.

#### IPA inspection and download queue

- Added a local IPA file importer. It checks `.ipa`, ZIP signature/archive opening, entry count/expanded-size bounds, safe unique paths, `Payload/<App>.app/Info.plist`, executable, bundle ID/version/build/minimum OS/family/capabilities/platform, Mach-O CPU subtype (including `arm64e.x1`), and CRCs. Unknown slices remain Unknown. Inspection streams entries instead of extracting untrusted paths.
- Queue progress now uses provider-reported downloaded/total bytes only. When the total is unknown, the UI shows indeterminate progress and bytes received without fabricating a percentage.
- Cancel cancels the worker task; each attempt has a unique temporary folder and a provider contract requiring the underlying transfer to stop before the provider returns. Retry creates a new task and path. A provider that ignores cancellation cannot be claimed safe; the only production provider is still blocked/stubbed.
- A successful provider result is inspected and validated before the IPA is moved into Documents. The default provider still throws `directEngineUnavailable`, so App Detail disables the download action and explains the blocker. FairPlay decryption is not implemented.

### Verification status — 2026-11-28 follow-up

The actual baseline for this follow-up was branch `main`, commit `93d9e7afd885cae8cbd4ecc004b3b8847bcfacdd`. The tree already contained user edits to the README, roadmap, localization catalogs, UI, `prompt.txt`, and an untracked `phanhoi.txt`; those were preserved. The current worktree remains uncommitted.

| Check | Result |
| --- | --- |
| `git diff --check` | PASS |
| Linux core harness | NOT RUN: `bash Scripts/test-linux-core.sh` was attempted and exited 127 because this execution shell could not find `swiftc` on PATH or at the script's Swiftly fallback path. A filesystem search also found no compiler binary. |
| Swift syntax parse / typecheck | NOT RUN: `swift` and `swiftc` are unavailable. |
| Xcode build / XCTest / Simulator | NOT RUN: `xcodebuild` and the iOS SDK are unavailable on this Linux host. |
| Live anonymous App Store API request | NOT RUN from IPAForge in this follow-up. The in-app experiment remains available and uses the existing Activity Log. |
| App Store login, license, binary download, real IPA and Apple signature verification | NOT TESTED. The production provider remains unavailable; no account credentials were used. |
| Workflow YAML | PASS: all three workflow files parsed with Ruby's YAML parser. |
| Localization / Privacy manifest / target membership | PASS: all three String Catalogs are valid, complete for English/Vietnamese, and identical; `PrivacyInfo.xcprivacy` parsed and is in app resources; project sources are in their app/test targets. `Tests/LinuxCoreChecks.swift` is intentionally script-only. |

The source currently has 61 XCTest methods. This is a static count, not a test result. Added regression coverage includes approval before Anisette identity transmission, event/correlation IDs, the unavailable-provider status, late progress after verification starts, Anisette HTTP diagnostics without response-body logging, and same-origin WSS validation. The updated Linux compatibility checks were not run.

An exact-tree GitHub Actions run is also NOT RUN. The workflows build a checkout from GitHub; without committing/pushing this tree, dispatching one would test a different revision. The workflow files were not changed. See the follow-up in [AUTHENTICATION_RESEARCH.md](./AUTHENTICATION_RESEARCH.md) for the current source review and App Store integration blocker.

### 2026-11-28 implementation follow-up

- Anisette v3 access now requires per-server approval before identity data is sent. The prompt names the selected HTTPS server and discloses the persistent `identifier`, `adi_pb`, and Apple provisioning exchange values that pass through it; approval is encrypted in Keychain and can be revoked, clearing that server's saved identity. A saved Developer Portal session does not auto-send Anisette data before approval.
- Removed the client metadata rewrite from macOS `10.12.6` to `27.0`; selected-server metadata now passes through unchanged.
- The unavailable download provider no longer displays authentication or metadata-loading states. Late progress callbacks cannot replace `Verifying`; cancellation is checked before reporting validation success. Validation logs state that Apple code-signature verification was not performed.
- `LoggingService` remains the single Activity Log and adds event IDs, optional correlation IDs, and sanitized diagnostics for public Search/Lookup and Anisette HTTP requests: method, query-free endpoint, actual HTTP status or N/A, response type/size, duration, redirect flag, retry count/Retry-After, server request ID, parsing/validation, error domain/code, reason, and next action. Anisette WebSocket handshake status is recorded when `URLSession` exposes it; otherwise the log reports N/A. Response bodies and Anisette values are not stored. Logs remain in-memory, capped at 500 entries.
- Anisette network requests now share the sign-in/server-selection correlation ID. HTTP parsing outcomes and cancellation are logged without recording headers, provisioning messages, `identifier`, `adi_pb`, or response bodies. The client requires WSS for provisioning, limits Apple-returned provisioning URLs to HTTPS on the default Apple origin without credentials/query/fragment, and rejects redirects outside the configured secure origin.
- Manually entered capabilities and architectures on simulated profiles remain Unknown; only Minimum OS is evaluated for the fixed Details profile.
- `PrivacyInfo.xcprivacy` now declares `UserDefaults` reason `CA92.1` alongside the existing disk-space reason and is included in app resources.
- The experimental download provider remains unavailable. Crumb and iPadN are current iOS-facing references, but their GPL/unlicensed upstream/proprietary-runtime conditions prevent straightforward reuse under the current project setup without a separate licensing decision. No Store login, license acquisition, binary download, IPA, or Apple signature result is claimed.
