# App Store authentication and IPA download research

**Repository:** `Lebaohuy3007/IPAForge`  
**Research checked:** 2026-11-28 (UTC; follow-up to the 2026-11-26 source review)
**Scope:** an iOS 16+ app that searches Apple's catalog and, if a compliant route exists, downloads an actual IPA with the fewest Apple Account prompts. This review does not bypass account authentication, app ownership, licensing, or FairPlay.

## Finding

Recent repositories now claim complete jailed-iOS download flows, so it would be inaccurate to say no technical demonstration exists. However, no reviewed route can currently be integrated into this MIT-licensed IPAForge project while also satisfying its identity, licensing, account, and FairPlay boundaries. Crumb's primary third-party notices state that its WaffleStore base has no license granting redistribution, its iPadN components are GPL-2.0-or-later, and redistribution rights for some bundled Apple-derived runtime libraries are unresolved. iPadN is GPL-2.0-or-later and its Store identity code creates a persistent random GUID. IPAToolKit uses a custom license. The MIT `ipatool` iOS build targets jailbroken devices and has recent authentication setup failures. No App Store authentication code was added to IPAForge.

The public anonymous API is viable for search and catalog metadata only. The live read-only check below found a free app and its metadata; it did not return a binary URL. The app's download provider therefore remains an explicit unavailable stub.

## Follow-up source review — 2026-11-28

This follow-up changes the candidate assessment, not IPAForge's implementation result. [Crumb's current README](https://github.com/boierito/Crumb/blob/main/README.md) claims a normally sideloaded iOS/iPadOS 16.4+ app with Apple ID/2FA, free-app license acquisition when Apple allows it, package download, and export. [Its third-party notices](https://github.com/boierito/Crumb/blob/main/THIRD_PARTY_NOTICES.md) are the deciding integration evidence: the whole project is not MIT, its WaffleStore base has no license grant, it ports GPL-2.0-or-later iPadN code, and it records unresolved redistribution rights for Apple-derived runtime binaries. Those claims make Crumb a relevant technical reference, but not a source we can copy or redistribute under IPAForge's current license without resolving the licensing boundary.

[iPadN's latest indexed release](https://github.com/mengangs/ipadn/releases) is v2.3.5 and its [repository](https://github.com/mengangs/ipadn) declares GPL-2.0. Its release notes claim ordinary iOS 16+ App Store login, free-app license retry, history, and download features. That is a live iOS implementation claim; IPAForge did not independently reproduce it. Its reviewed `AppleService.swift` persists a randomly generated GUID, its SAP signer has another generated identifier path, and the repository includes FairPlay decryption code. These are incompatible with this task's no-fabricated-identity/no-DRM boundary and require a project license decision before any code could be reused.

[IPAToolKit's README](https://github.com/maclub-net/IPAToolKit/blob/main/README.md) claims an iOS 15+ Swift package with sign-in, 2FA, purchase, and download calls, but publishes a custom license that permits personal/educational non-commercial use and requires a separate license for commercial use. Its non-IOKit identity code also generates a random hardware identifier. It is not a safe default dependency for IPAForge.

The best integration choice remains **no direct App Store provider** until the identity, code license, and runtime redistribution questions are cleared. The public Search/Lookup engine and local IPA inspection remain available; `AppStoreDownloadService` still throws `directEngineUnavailable`. The sources establish that community iOS implementations are being attempted; they do not establish a clean, redistributable implementation for this MIT project.

The current workspace also adds a local Anisette approval gate. Before provisioning through a selected server, it discloses that the server receives a persistent `identifier`, `adi_pb`, and some Apple provisioning exchange values. The operator can read and retain values sent through it. Approval is stored in Keychain and can be revoked, which deletes both approval and the server-scoped identity. This is not App Store authentication or Store AMD proof.

Anisette HTTP requests now write sanitized diagnostics to the existing in-memory Activity Log with the sign-in/server-selection correlation ID: actual status or N/A, endpoint, method, duration, response type/size, redirect state, Retry-After, safe request ID, and error domain/code. Parsing and cancellation outcomes are also recorded. Response bodies and Anisette values are excluded. WebSocket handshake status is recorded when `URLSession` exposes it; otherwise it remains N/A. This follow-up adds a mock test for HTTP 503 and response-body omission, but that test has not run in the current environment.

The command-execution environment for this follow-up is Linux. `command -v swiftc`, a filesystem search, and the Linux core harness did not find a compiler; the script exited 127. `xcodebuild` is also absent. No new XCTest, Simulator, physical-device, live App Store request from IPAForge, or GitHub Actions result is claimed for this follow-up. See the current [roadmap verification status](./ROADMAP.md).

### Anonymous API observation — 2026-11-28

Because the Swift app could not run in this host, a separate read-only `curl` request was made directly to Apple's public endpoints. This is not an IPAForge in-app Activity Log entry. No Apple Account, cookies, Anisette data, or private Store endpoint was used.

| Request | HTTP | Duration | Response bytes | Observation |
| --- | ---: | ---: | ---: | --- |
| `GET https://itunes.apple.com/search` with `Apple Store`, US storefront | 200 | 1,370 ms | 491,101 | 47 catalog records; expected app ID `375380948` present and priced at 0. |
| `GET https://itunes.apple.com/lookup` for app ID `375380948`, US storefront | 200 | 62 ms | 10,460 | One record: `com.apple.store.Jolly`, version `6.10`, minimum OS `26.0`, price 0. The record contained no `downloadUrl` field. |

These responses verify only public search/metadata. No binary request or IPA integrity/signature check was made. The calls could not be inserted into the running app's in-memory Activity Log because the iOS app cannot run in this Linux host; the app code now records the same kind of sanitized diagnostics when its experiment is run.

## Repository audit

At the start of the original 2026-11-26 pass the repository was on `main`, commit `fdbda80` (`Update AppStore UI`). For the 2026-11-28 follow-up, the actual baseline was `main` at `93d9e7afd885cae8cbd4ecc004b3b8847bcfacdd`; `prompt.txt` and the existing user changes were preserved. The project uses an explicit Xcode project file, Swift language mode 5, and iOS deployment target 16.0. Its package references are StosSign at a pinned revision and ZIPFoundation; no App Store authentication/download package is integrated.

| Area | Current state |
| --- | --- |
| `AppStoreService` | Uses the public iTunes Search/Lookup API for app metadata. It has no Store login, license, Store session, or binary URL implementation. |
| Developer Portal authentication | `AuthenticationService`, `StosSignAuthenticationProvider`, `AppleAccountVault`, and the existing login UI authenticate to the Developer Portal and retrieve Developer Teams. This is not App Store authentication. |
| Anisette | `AnisetteService` obtains Anisette v3/AuthKit data from the selected service and persists its own identity through the encrypted account vault. This is not Store AMD proof and is not a Store session. |
| Store AMD / SAP | No Store AMD provider or App Store SAP authentication is implemented. Public sources reviewed distinguish these from AuthKit Anisette and Developer Portal SRP. |
| `DownloadService` | Queue, actual-byte progress, cancellation boundary, retry-as-new-task, IPA inspection, and save-after-validation are present. The production `AppStoreDownloadService` still throws `directEngineUnavailable`. |
| `IPAInspector` / export | Locally supplied IPAs are inspected and can be shared/exported. This does not acquire an App Store license or fetch an App Store binary. |
| Activity Log | Reuses `LoggingService`; no second logging subsystem was added. The new experiment runner records Experiment A and the blocked/not-attempted result of Experiment B. |
| GitHub Actions | `.github/workflows/experimental.yml` still uses `xcode-27`, Xcode 27.2, and the existing optional `run_tests` input. No workflow was changed and no credentials were put in CI. |

The four kinds of Apple identity involved here are distinct: Developer Portal authentication, App Store authentication, Anisette/AuthKit, and Store AMD/SAP. Store purchase/license state is another separate concern. No session or token is copied between them.

## Experiment A — public access, no account

Two read-only requests were made to Apple's public API on 2026-11-26. No Apple Account, cookie, session, Anisette value, or private endpoint was used.

| Check | Result |
| --- | --- |
| Search | **PASS** — `GET /search` returned HTTP 200 and included Apple Store, app ID `375380948`. |
| Metadata | **PASS** — `GET /lookup?id=375380948&country=us` returned one catalog record: `com.apple.store.Jolly`, version `6.10`, price `0` / Free, minimum OS `26.0`. |
| Binary access | **NOT SUPPORTED** by the documented public Search/Lookup interface. The result contains catalog fields and store/artwork URLs, not an IPA download URL. `fileSizeBytes` is a size field, not a binary locator. |
| IPA download | **NOT TESTED** — there was no public binary endpoint to call. No private commerce endpoint was probed anonymously. |
| IPA integrity | **NOT TESTED** — no IPA was obtained, so `IPAInspector` was not run. |

Primary references: [iTunes Search API overview](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html) and [Search API result fields](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html). These archived docs are old (the overview says updated 2017); the live endpoint result above is a separate 2026 observation. The public API's purpose and response shape do not document a licensed binary-download operation.

## Experiment B — minimum authentication

**NOT TESTED / BLOCKED before credential entry.** No compliant iOS App Store auth/device-identity provider is implemented or supported by the reviewed evidence. No Apple ID, password, or 2FA code was requested, stored, or sent. Therefore these steps have no live result: sign-in, 2FA, session restore, paid-app ownership, free-app license acquisition, download, IPA verification, and file export.

This is not a failed login. The experiment did not begin because there is no candidate path that meets the project's identity and platform requirements. A Mac/Xcode/iPhone checklist is provided below for a future route that clears that gate.

## Sixteen approaches considered

At least eight are technically distinct rather than forks of one implementation family.

| # | Approach | What the source supports | Finding for IPAForge |
| ---: | --- | --- | --- |
| 1 | Public anonymous Search/Lookup | Catalog search and metadata, tested live without login. | Useful and implemented; no documented binary access, so it fails the IPA goal. |
| 2 | Anonymous private Store commerce endpoints | Community clients expose private purchase/download endpoints. | Not public API; no evidence that a binary is authorized without a Store session/license. Not probed. |
| 3 | Open an App Store product in Apple's system UI | The system App Store can install an app under the device's Apple Account. | Does not return/export an IPA to IPAForge. |
| 4 | StoreKit / native StoreKit transactions | Transactions and entitlements for in-app purchases made by the app. | Not an API to buy/download arbitrary App Store apps or export their binaries. |
| 5 | App Store Connect API | JWT-authenticated management of apps in a developer team. | Team-scoped developer API, not consumer App Store account authentication or a download API for third-party apps. |
| 6 | TestFlight | Developer-uploaded beta builds assigned to invited testers; testers install through TestFlight. | Does not acquire arbitrary public App Store apps or expose a generic IPA export. |
| 7 | Xcode / Transporter / developer-owned build | A developer can archive and distribute their own build to registered devices or TestFlight. | Legitimate for the developer's own app, outside the goal of downloading another publisher's App Store binary. |
| 8 | `majd/ipatool` Go client | Current releases provide Store auth, 2FA, account/session, purchase, and IPA download on desktop; release history also includes a jailbroken-iOS build. | Real desktop download evidence, but not a verified ordinary iOS app route. Latest iOS auth reports show an emulator architecture failure even on jailbroken devices. |
| 9 | `bahattinkoc/ipaverse` GSA/PET client | Swift/macOS source implements GSA SRP-6a, 2FA, PET-to-MZFinance exchange, free-app license acquisition, download, and package preparation. | macOS-only; source reads MAC/serial and falls back to a random UUID. Cannot be copied into the ordinary iOS app under the no-fabricated-identity rule. |
| 10 | `Lakr233/ApplePackage` Swift package | Swift SAP-signed authentication, package APIs, and iOS 15+ declared platform. | iOS platform declaration is not proof the identity path works. The reviewed iOS fallback generates an identifier; Swift 6 language mode also differs from this Swift 5 app. |
| 11 | `iPadN` / `Crumb` / `WaffleStore` jailed-iOS family | iPadN release notes and Crumb's current README claim ordinary iOS App Store login, license and download flows. | iPadN generates/persists a random GUID and uses GPL-2.0 code; Crumb's own third-party notices identify an unlicensed WaffleStore base and unresolved Apple-derived runtime redistribution rights. These claims were not independently reproduced by IPAForge. |
| 12 | `maclub-net/IPAToolKit` Swift/C | Public Swift client APIs cover Store auth, purchase, and downloads. | On non-IOKit platforms its own source creates and stores a random 6-byte hardware identifier. Its published custom license is also non-commercial. |
| 13 | `apple-auth` / Mac ADI | C++/Swift/Python code offers Apple auth components; its docs describe an iPhone path. | The project labels the iPhone Mac-ADI path experimental/not recommended. No stock-iOS identity or success proof. |
| 14 | `ipakeep` desktop Apple-framework emulation | Rust client implements Apple authentication, store APIs, license acquisition, and encrypted IPA downloads. | Desktop emulator/ADI path; no iOS app identity. |
| 15 | User-controlled macOS helper | A desktop client could acquire an authorized encrypted package and transfer a file to iOS. | A possible separate desktop workflow, but credentials, identity, license, and network work happen outside IPAForge. It adds a host and does not meet direct iOS integration. |
| 16 | Import an IPA the user already has | IPAForge can inspect and export a local `.ipa`. | Implemented as local file handling; it does not download from Apple or establish licensing. |

### Source-level findings

#### Public API, official account APIs, and app distribution

Apple's [App Store Connect API overview](https://developer.apple.com/documentation/appstoreconnectapi/) describes a JWT API whose keys come from a developer organization's App Store Connect account. The [Apps resource](https://developer.apple.com/documentation/appstoreconnectapi/apps) manages that developer's app records; [Build Bundles](https://developer.apple.com/documentation/appstoreconnectapi/build-bundles) describes metadata for binaries uploaded as builds. That scope does not grant access to arbitrary consumer App Store binaries.

Apple [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) returns identity information and tokens for authenticating a person to the relying app/service. It is not an App Store consumer session. Apple's [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) can securely store small secrets; using Keychain does not make a private Store token supported, valid, or renewable.

StoreKit's [Transaction API](https://developer.apple.com/documentation/storekit/transaction) and [`currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements) describe purchases and entitlements for in-app products. They are not APIs for downloading/exporting other App Store apps. Apple's [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) requires a developer-uploaded build and assigned testers; testers install a thinned build with TestFlight. Apple's [Developer Program License Agreement](https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-English.pdf) describes developer distribution channels, not a general third-party IPA export route.

#### `ipatool` — latest desktop implementation and the iOS boundary

As checked on 2026-11-26, [v2.8.1](https://github.com/majd/ipatool/releases) was the latest release (2026-11-11). v2.8.0 (2026-11-08) reports restored App Store authentication using local Anisette generation/provisioning and modern Store operations. The current [README](https://github.com/majd/ipatool) describes app package download; the source entry points are [`appstore_login.go`](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore_login.go) and [`appstore.go`](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore.go). These establish a capable Go desktop implementation, not a Swift framework or an ordinary iOS application service.

Release 2.6.0 says it added builds for jailbroken iOS devices. Two current reports matter: [issue #680](https://github.com/majd/ipatool/issues/680) reports v2.8.1 login failing on an iPhone 11 at Unicorn ARM64 emulator initialization; [issue #682](https://github.com/majd/ipatool/issues/682) reports the same class of failure on a rootless-jailbroken iPhone 12 Pro Max. Those are reporter-provided, device-specific observations, not a proof every device fails. They do show that “an iOS binary exists” is not evidence of a working IPAForge path. No jailbroken runtime, private Apple framework, or synthetic identity is accepted as a solution here.

#### `ipaverse` — detailed source review

The current [README](https://github.com/bahattinkoc/ipaverse/blob/main/README.md) requires Apple Silicon Mac and macOS 14.6+. It explicitly describes App Store downloads as FairPlay-encrypted and says paid apps must already be licensed to the active Apple Account. Its [`AppStoreService.swift`](https://github.com/bahattinkoc/ipaverse/blob/main/ipaverse/ipaverse/Services/AppStoreService.swift) implements GSA/SRP-6a, a 2FA continuation, and a bridge using the GSA PET to obtain Store `passwordToken`, DSID, storefront, and pod values. Its purchase path acquires a free-app license when needed; its download path requests the private Store package and applies SINF metadata for the returned encrypted package.

That file imports IOKit and invokes `/sbin/ifconfig` through `Process` to find a MAC address. If no MAC is found, it tries the Mac serial; if that is missing too, it falls back to a random UUID. All three identity choices are Mac-specific or fabricated for an iOS Store identity. The README's local Anisette option is AOSKit on macOS, with configured Anisette v3 service fallback. The Anisette data, GSA/PET, Store session, license, and package request are distinct steps. The project is a strong source reference for those transitions, but cannot supply an ordinary iOS provider for this app.

#### Other code audited

- [`ApplePackage/Package.swift`](https://raw.githubusercontent.com/Lakr233/ApplePackage/main/Package.swift) declares iOS 15+ but also Swift language mode 6 and dependencies on OpenSSL, AsyncHTTPClient, ZIPFoundation, Collections, and Swift Log. A platform declaration alone does not verify a valid Store identity. Its iOS fallback, inspected in the authentication/device-identifier source, is generated and persisted; that is prohibited by this prompt.
- [`iPadN AppleService.swift`](https://raw.githubusercontent.com/mengangs/ipadn/main/iPadn-iOS/iPadn/Services/AppleService.swift) generates a six-byte random GUID (12 hex characters) and stores it in UserDefaults. [`SAPSigner.swift`](https://raw.githubusercontent.com/mengangs/ipadn/main/iPadn-iOS/iPadn/Services/SAPSigner.swift) derives a Store identifier from that GUID and contains a random identifier path. The source is iOS-native but fails the identity constraint. The repository uses GPL-2.0; Crumb credits GPL components, so copying code would also require a separate license review.
- [`IPAToolKit AppStoreClient.swift`](https://raw.githubusercontent.com/maclub-net/IPAToolKit/main/Sources/IPAToolCore/AppStoreClient.swift) uses the real MAC path when IOKit is available; its non-IOKit path explicitly creates and persists a random 6-byte hardware identifier in UserDefaults. Its custom license restricts use to non-commercial terms unless separately licensed.
- [`apple-auth`](https://github.com/apple-auth/apple-auth) documents its iPhone Mac-ADI path as experimental and not recommended. It does not establish a supported stock-iOS Store identity.
- [`ipakeep`](https://github.com/seifreed/ipakeep/tree/main/src/infrastructure/appstore) implements App Store authentication and store API modules in a desktop Rust toolkit, including Apple desktop-framework emulation; no iOS identity path is documented.
- SideStore/AltStore provide useful Anisette and personal-account signing context, but their signing/refresh operation is not App Store acquisition. SideStore's [Anisette guidance](https://docs.sidestore.io/docs/advanced/anisette) warns against disclosing Apple credentials to Anisette services. Neither is an App Store IPA download engine.

## Technical discussions and failure evidence

These reports are evidence of changing private behavior and implementation limits, not guarantees about every account or device.

| Discussion | Date / status checked | Useful result |
| --- | --- | --- |
| [`ipatool` #642](https://github.com/majd/ipatool/issues/642) | Opened 2026-11-06; closed via #643; comments through 2026-11-08 | A contributor separated AuthKit `X-Apple-I-MD*` from Store AMD `X-Apple-AMD*`. A patched Mac/Linux client reportedly obtained a Store session and downloaded an already-owned IPA. The author explicitly says new-license acquisition was not verified and the IPA remained FairPlay-encrypted. This is the clearest distinction between Anisette, Store AMD, authentication, license, and download. |
| [`ipatool` #680](https://github.com/majd/ipatool/issues/680) | Opened 2026-11-20; open at check | Official iOS ARM64 ipatool 2.8.1 binary reportedly fails on iPhone 11 while opening the Unicorn ARM64 authentication emulator. |
| [`ipatool` #682](https://github.com/majd/ipatool/issues/682) | Opened 2026-11-21; open at check | Reports the same emulator initialization failure on a rootless-jailbroken iPhone 12 Pro Max running iOS 15.1.1. |
| [`ipatool` #681](https://github.com/majd/ipatool/issues/681) | Opened 2026-11-21; open at check | A macOS non-interactive login with a real 2FA account reportedly stalled before the 2FA handoff. The maintainer's issue template explicitly says the exact blocked stage was not locally reproduced; synthetic-account control does not validate real 2FA. |
| [`ipatool` #498](https://github.com/majd/ipatool/issues/498) | Opened 2026-06-15; closed later | Some auth-fix branches reported login success followed immediately by `password token is expired` on download. This is older than 2.8.x, but demonstrates why login success cannot stand in for a completed download/license test. |
| [`ipatool` #550](https://github.com/majd/ipatool/issues/550) | Opened 2026-09-09; closed | v2.5 users reported transient 500/204/404/403 authentication responses. Later releases changed the implementation; retain as evidence that private endpoints and edge behavior change, not as current failure proof. |
| [`ipatool` #465](https://github.com/majd/ipatool/issues/465) | Opened 2026-04-13; closed | A changed password produced a confusing 2FA continuation prompt. Older-version report; useful for explicit 2FA-state/error handling. |

This satisfies the research minimum of five technical issues/discussions. The report distinguishes user observations, source evidence, and independently run tests; none of the community account tests was repeated with IPAForge credentials.

## Weighted ranking and elimination

Scores are weighted points, not raw percentages. Each criterion uses a 0–5 assessment and contributes `weight × score / 5`.

| Criterion | Weight |
| --- | ---: |
| Real IPA acquisition | 25 |
| Ordinary iOS compatibility | 15 |
| Few authentication steps | 15 |
| Session persistence | 10 |
| License handling | 10 |
| Stability | 10 |
| Security | 10 |
| Maintainability | 5 |

| Approach | IPA /25 | iOS /15 | Auth /15 | Session /10 | License /10 | Stable /10 | Secure /10 | Maintain /5 | Total /100 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Public anonymous Search/Lookup | 0 | 15 | 15 | 0 | 0 | 8 | 10 | 4 | **52** |
| Private Store endpoint without a session | 0 | 6 | 9 | 0 | 0 | 2 | 3 | 1 | **21** |
| Apple's system App Store install UI | 0 | 15 | 12 | 10 | 10 | 10 | 10 | 5 | **72** |
| StoreKit transaction / entitlement APIs | 0 | 15 | 9 | 10 | 3 | 10 | 10 | 5 | **62** |
| App Store Connect API | 0 | 6 | 3 | 4 | 2 | 10 | 8 | 4 | **37** |
| TestFlight beta installation | 5 | 12 | 9 | 6 | 8 | 8 | 10 | 5 | **63** |
| Xcode/Transporter for developer-owned builds | 20 | 6 | 3 | 4 | 10 | 10 | 8 | 5 | **66** |
| `ipatool` Go Store client | 25 | 3 | 6 | 8 | 8 | 4 | 6 | 4 | **64** |
| `ipaverse` GSA/PET on macOS | 25 | 0 | 9 | 8 | 8 | 6 | 6 | 4 | **66** |
| `ApplePackage` Swift package | 25 | 6 | 6 | 6 | 8 | 6 | 4 | 4 | **65** |
| WaffleStore / MuffinStore / PancakeStore predecessors | 20 | 12 | 6 | 8 | 6 | 4 | 2 | 3 | **61** |
| Crumb current iOS source claims (not independently reproduced) | 20 | 15 | 12 | 8 | 0 | 4 | 2 | 2 | **63** |
| iPadN v2.3.5 source/release claims (not independently reproduced) | 20 | 15 | 12 | 8 | 4 | 6 | 2 | 2 | **69** |
| IPAToolKit Swift/C | 25 | 6 | 6 | 6 | 8 | 4 | 2 | 2 | **59** |
| `apple-auth` Mac-ADI iPhone path | 25 | 3 | 6 | 8 | 8 | 2 | 3 | 2 | **57** |
| `ipakeep` desktop framework emulation | 25 | 0 | 9 | 8 | 8 | 6 | 6 | 3 | **65** |
| User-controlled Mac helper + IPA transfer | 25 | 3 | 6 | 8 | 8 | 6 | 4 | 3 | **63** |
| Import a user-supplied IPA | 0 | 15 | 15 | 0 | 0 | 8 | 8 | 5 | **51** |

The scores compare these options against **the stated IPAForge goal**, not each project's own purpose. A high pre-elimination score does not mean an approach is acceptable.

### Elimination rounds

1. **Real binary:** eliminate public Search/Lookup, private unauthenticated speculation, system App Store UI, StoreKit, App Store Connect, TestFlight, and local IPA import. They do not download a generic App Store IPA into this app. Xcode/Transporter can produce the developer's own uploaded build, not another publisher's app.
2. **Platform:** eliminate `ipaverse` and `ipakeep` as in-app engines because they require macOS. Eliminate current `ipatool` for ordinary iOS integration: its latest iOS build targets jailbroken devices and the current iPhone reports fail during authentication setup. A desktop helper remains an external workflow only.
3. **Identity and authentication:** eliminate the reviewed ApplePackage fallback, iPadN, IPAToolKit, and Mac-ADI iPhone experiment. They use a generated identifier, depend on desktop identity/private frameworks, or are explicitly experimental; none establishes a permitted iOS Store identity. `UIDevice.identifierForVendor` is not documented as a Store GUID and is not substituted.
4. **License:** no remaining candidate proves a supported way for this iOS app to acquire the necessary App Store license for a free app or reuse an already-owned app's Store license.
5. **Security:** do not store or route Apple Account credentials through a third-party anisette service, CI secret, or unreviewed relay. Do not serialize upstream password-bearing account structures or log tokens/cookies/Anisette/SAP material.
6. **Finalists:** Apple's system install flow is legitimate but cannot export an IPA; public metadata is safe but has no binary; desktop tools can fetch encrypted packages in some environments but are not this iOS app and do not prove a supported device identity. None meets every requirement.

## Winner and counterargument

**Winner: no viable direct iOS App Store IPA download approach established as of 2026-11-26.** The current safe implementation remains public metadata search plus local IPA inspection/export. That is a partial product capability, not a downloader.

There is no supported estimate for login count, 2FA frequency, or cross-launch Store session restore because Experiment B never reached authentication. Keychain can protect a future session secret, but only after a valid Store session format, expiry behavior, and logout/revocation behavior are proven. The existing vault stores Developer Portal session data only.

Three concrete ways the strongest source candidates can fail:

1. **Authentication can succeed while commerce fails.** Issue #498 records that exact state for earlier ipatool auth fixes; issue #642 separately reports missing Store AMD proof and says new-license acquisition was not tested. A valid GSA/SAP step is not proof of a download license.
2. **A nominal iOS build can fail before login.** Issues #680 and #682 report Unicorn ARM64 initialization failures on actual jailbroken iPhones. No normal IPAForge device build was run here.
3. **The identity path can violate the prompt even if requests work.** ipaverse uses Mac MAC/serial and a random fallback; iPadN and IPAToolKit generate persistent IDs when hardware identity is unavailable. Success with such a value would not satisfy the no-fabricated-identity rule.

Further risks are Apple changing private endpoints, account-specific 2FA/challenges, Store token expiry, license acquisition differences between free and already-owned apps, and FairPlay encryption. The downloaded original can remain account-bound/encrypted; this review does not attempt decryption or signature bypass.

## Experiment B manual checklist for a future compliant candidate

Run this only after a source establishes a non-fabricated iOS identity path and the app can be built for a physical device. Use an Apple Account the tester controls. Never paste unredacted output into Activity Log or a public issue.

1. Build on a Mac with Xcode, install to a physical iPhone, and confirm Activity Log contains no password, 2FA code, cookie, token, Anisette body, device identity, or SAP signature.
2. Record only the auth mode and sanitized HTTP/error class. Enter account credentials in the app only if the selected provider is documented and sends them directly to Apple.
3. If Apple requests 2FA, enter one current code and record whether the account reaches Store session state. Do not mark login complete from a GSA-only result.
4. Close and reopen IPAForge. Confirm a session restore with a real Store request, not only a nonempty token string. Test logout and confirm Keychain material is removed.
5. Test one free app and separately an app already owned by that account. Do not test paid-app purchase unless the user explicitly chooses to buy it.
6. Confirm a license result, then obtain a nonempty package URL and transfer bytes. Record HTTP status and actual bytes only; do not log response bodies or proof headers.
7. Run the returned file through `IPAInspector`, check ZIP CRC, app metadata and Mach-O, and export it from IPAForge. Record whether the IPA remains FairPlay-encrypted; do not attempt to decrypt it.
8. Repeat after relaunch to test session persistence and after a controlled sign-out to test expiry/re-authentication. Stop on account challenge, unexpected identity request, or secret leakage.

## Activity Log behavior

The existing `LoggingService` is reused. The App Store screen now has an anonymous experiment action that reports both experiments and writes their final results to the existing Activity Log. It records timestamps through the logger and HTTP status for public requests; it never stores response bodies or credentials.

- Experiment A records start, anonymous mode, session unavailable, public search, metadata lookup, binary unsupported, IPA download/integrity not tested, and its final result.
- Experiment B is marked blocked before sign-in, with 2FA/session/license/download/IPA checks not tested. It does not emit a false authentication success.
- Queue events record download start, actual-byte progress milestones, IPA verification, completion, cancellation, and categorized failure. No authentication or license event is claimed while there is no production engine.
- `LogSanitizer` remains in the path for log messages. Passwords, verification codes, session tokens, cookies, Anisette fields, identifiers, and bearer values must never be logged.

## Implementation self-review

| Risk found | Handling |
| --- | --- |
| Public API failures previously collapsed into a generic invalid response, hiding HTTP status. | `AppStoreService` now reports non-2xx status separately and exposes the status to the experiment logger; XCTest covers 503. |
| A catalog record could be mistaken for a free-app test without checking price. | `AppRecord` now retains the catalog price; Experiment A requires the expected app ID and `price == 0` for both checks. |
| A 2xx response with malformed JSON could appear to be a successful request. | Decoding still rejects malformed data; experiment logs include HTTP status plus an invalid-response classification; XCTest covers malformed JSON. |
| Logging arbitrary provider `localizedDescription` could expose a token or server body. | Download failure logs now use a safe category/status summary and omit raw provider error text. Existing `LogSanitizer` remains active. |
| Timed-out transfers could leave a partial IPA in the temporary directory. | The queue removes the attempt directory on failure; a new XCTest creates a partial file, throws timeout, and checks cleanup. |
| CRC mismatch errors could be indistinguishable from generic ZIP corruption. | `IPAInspector` maps ZIPFoundation's CRC error to an explicit CRC mismatch; the fixture test corrupts the central-directory checksum and asserts that classification. |
| The Activity Log stores entries in memory and caps them at 500, so a result disappears after app relaunch or manual clear. | This matches the existing `LoggingService` behavior; no second persistence/logging store was introduced. Copy the log before clearing or closing if the experiment record must be retained. |

Those checks were performed during the 2026-11-26 pass. The separate 2026-11-28 follow-up has no Swift compiler or Xcode in its current environment; its test status is recorded below and supersedes the older environment summary for that follow-up.

## Tests and environment — 2026-11-26 historical verification

The Xcode XCTest suite had 23 v3/experiment-focused cases at that historical checkpoint: public API search/lookup status and error behavior, a mock-only experiment report, IPA fixtures for valid/missing/malformed/CRC/Mach-O cases, and queue progress/cancellation/retry/timeout cleanup. Those mocks verify app behavior; they are not the live Apple result above. Existing Developer Portal authentication tests do not test App Store authentication. No Store auth or license mocks were added because there is no provider implementation to exercise.

| Verification | Result |
| --- | --- |
| Public Apple Search endpoint, live, anonymous | PASS — HTTP 200, free app returned |
| Public Apple Lookup endpoint, live, anonymous | PASS — one metadata record returned |
| Anonymous binary access / IPA / CRC | NOT SUPPORTED / NOT TESTED / NOT TESTED |
| App Store login, 2FA, restore, license, real IPA | NOT TESTED; blocked before credentials |
| Linux Swift harness | PASS — `Scripts/test-linux-core.sh`, 17 assertions; covers pure profile/compatibility logic, not the iOS app |
| Swift syntax parse | PASS — all project Swift files parsed; syntax only |
| Xcode build and full XCTest | NOT TESTED — this environment is Linux and has no `xcodebuild` or iOS SDK |
| Simulator / physical device | NOT TESTED in this turn |
| GitHub Actions on this exact tree | NOT RUN — no commit/push, and dispatching the remote branch would build different source |
| Workflow configuration | Unchanged; Xcode 27.2 and runner `xcode-27` retained |

## Sources checked

All links below were accessed on 2026-11-26 UTC. Apple does not display a last-updated date on every current documentation page; for those pages the date below is the access/check date. The archived Search API pages report their own older update date. For raw GitHub files without a file history/date in the view, the current branch content was reviewed, but a separate last-commit date was not visible. That is stated rather than presented as a 2026 protocol guarantee.

### Apple and primary technical sources

1. [iTunes Search API overview](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html) — archived; page says updated 2017-09-19. Search/lookup purpose and use limits.
2. [Understanding Search Results](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html) — archived; response-field documentation checked 2026-11-26, including artwork and product view URLs.
3. [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/) — current page checked 2026-11-26; API scope and JWT/API-key authorization. No page update date displayed.
4. [App Store Connect Apps resource](https://developer.apple.com/documentation/appstoreconnectapi/apps) — page checked 2026-11-26; developer-team app records and upload scope; no update date displayed.
5. [Build Bundles resource](https://developer.apple.com/documentation/appstoreconnectapi/build-bundles) — checked 2026-11-26; metadata describing uploaded build binaries; no update date displayed.
6. [Sign in with Apple authentication](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) — checked 2026-11-26; app/service user identity tokens, distinct from Store session.
7. [AuthenticationServices overview](https://developer.apple.com/documentation/authenticationservices/) — checked 2026-11-26; framework scope for app/service authentication and web sign-in.
8. [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) — checked 2026-11-26; secure storage mechanism, not Store token semantics.
9. [StoreKit Transaction](https://developer.apple.com/documentation/storekit/transaction) — checked 2026-11-26; in-app purchase transactions, not app binaries.
10. [StoreKit currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) — checked 2026-11-26; IAP/subscription entitlements.
11. [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) — checked 2026-11-26; uploaded beta builds and invitation-based testing.
12. [Apple Developer Program License Agreement](https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-English.pdf) — checked 2026-11-26; distribution categories and developer responsibilities.
13. [Running apps on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices) — checked 2026-11-26; Simulator is a Mac/Xcode environment and does not replace physical-device verification.

### Repositories and implementation source

14. [`majd/ipatool` current releases](https://github.com/majd/ipatool/releases) — v2.8.1 dated 2026-11-11; v2.8.0 auth restoration dated 2026-11-08.
15. [`majd/ipatool` App Store login source](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore_login.go) — authentication implementation entry point.
16. [`majd/ipatool` App Store API source](https://github.com/majd/ipatool/blob/main/pkg/appstore/appstore.go) — Store-facing operations and download interfaces.
17. [`bahattinkoc/ipaverse` AppStoreService.swift](https://github.com/bahattinkoc/ipaverse/blob/main/ipaverse/ipaverse/Services/AppStoreService.swift) — GSA/PET, 2FA, Store license and download code; source imports IOKit and uses macOS process/MAC logic.
18. [`ipaverse` README](https://github.com/bahattinkoc/ipaverse/blob/main/README.md) — macOS 14.6+ requirement, free/paid license notes, FairPlay-encrypted output.
19. [`ApplePackage` Package.swift](https://raw.githubusercontent.com/Lakr233/ApplePackage/main/Package.swift) — iOS 15 declaration, Swift 6 mode, package dependencies.
20. [`iPadN` AppleService.swift](https://raw.githubusercontent.com/mengangs/ipadn/main/iPadn-iOS/iPadn/Services/AppleService.swift) — generated and persisted Store GUID.
21. [`iPadN` SAPSigner.swift](https://raw.githubusercontent.com/mengangs/ipadn/main/iPadn-iOS/iPadn/Services/SAPSigner.swift) — derived/random Store identifier and SAP/WebKit runtime.
22. [`IPAToolKit` AppStoreClient.swift](https://raw.githubusercontent.com/maclub-net/IPAToolKit/main/Sources/IPAToolCore/AppStoreClient.swift) — actual Store calls and non-IOKit random hardware identity.
23. [`apple-auth` full documentation](https://github.com/apple-auth/apple-auth/blob/main/docs/full-docs.md) — platform notes; iPhone Mac-ADI path is experimental/not recommended.
24. [`ipakeep` App Store authentication and API tree](https://github.com/seifreed/ipakeep/tree/main/src/infrastructure/appstore) — desktop Rust authentication/store modules.
25. [SideStore Anisette documentation](https://docs.sidestore.io/docs/advanced/anisette) — Anisette's sideloading context and account-data boundary.
26. [Crumb repository](https://github.com/boierito/Crumb) — iOS-facing project credits/source relationship to WaffleStore, ipatool and iPadN.
27. [AltStore repository](https://github.com/altstoreio/AltStore) — sideloading/refresh flow, not App Store binary acquisition.

### GitHub issues / technical discussions

28. [`ipatool` #642](https://github.com/majd/ipatool/issues/642) — Store AMD vs AuthKit Anisette and reported owned-app download on desktop.
29. [`ipatool` #680](https://github.com/majd/ipatool/issues/680) — v2.8.1 iPhone 11 authentication emulator failure, opened 2026-11-20.
30. [`ipatool` #682](https://github.com/majd/ipatool/issues/682) — v2.8.1 iOS ARM64 authentication failure on rootless-jailbroken iPhone, opened 2026-11-21.
31. [`ipatool` #681](https://github.com/majd/ipatool/issues/681) — non-interactive login stall before 2FA handoff, opened 2026-11-21.
32. [`ipatool` #498](https://github.com/majd/ipatool/issues/498) — login-success/download-token-expired case, opened 2026-06-15.
33. [`ipatool` #550](https://github.com/majd/ipatool/issues/550) — HTTP 500/204/404 login response variability, opened 2026-09-09.
34. [`ipatool` #465](https://github.com/majd/ipatool/issues/465) — 2FA continuation behavior after a password change, opened 2026-04-13.

### Follow-up sources checked 2026-11-28

35. [Crumb README](https://github.com/boierito/Crumb/blob/main/README.md) — claims an ordinary iOS 16.4+ sign-in, 2FA, free-license, IPA-download, and export flow.
36. [Crumb third-party notices](https://github.com/boierito/Crumb/blob/main/THIRD_PARTY_NOTICES.md) — documents the WaffleStore no-license state, GPL iPadN components, and unresolved redistribution rights for Apple-derived runtime libraries.
37. [iPadN latest releases](https://github.com/mengangs/ipadn/releases) — v2.3.5 release notes claim iOS 16+ login/download and free-license retry behavior; these claims were not independently reproduced by IPAForge.
38. [iPadN repository](https://github.com/mengangs/ipadn) — GPL-2.0 project page and iOS-facing feature claims.
39. [IPAToolKit README](https://github.com/maclub-net/IPAToolKit/blob/main/README.md) — iOS 15+ package claim and custom license terms.
40. [Apple required-reason API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) and [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) — the app uses UserDefaults for local settings and declares reason `CA92.1` in `PrivacyInfo.xcprivacy`.
41. [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [runner-images inventory](https://github.com/actions/runner-images/blob/main/README.md) — `xcode-27` is a current macOS arm64 GitHub-hosted runner label.

This list exceeds the prompt's minima: more than 15 useful references, more than 5 official/primary technical sources, more than 5 source repositories, and more than 5 technical issues/discussions. Issue claims are kept separate from IPAForge's direct public-API experiment.
