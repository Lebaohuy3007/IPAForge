# IPAForge

Ứng dụng SwiftUI cho iOS 16+ để duyệt App Store, cấu hình endpoint Anisette và theo dõi các giới hạn của quy trình tải IPA.

**Đọc bằng:** [English](./README.md) | Tiếng Việt

### Thử nghiệm

| iOS Version | Trạng thái |
|:---:|:---:|
| 18.7.9 | Đã thử nghiệm |
| Phiên bản khác | Chưa xác minh |

> **Tình trạng hiện tại:** IPAForge tìm kiếm App Store và có đăng nhập Apple ID riêng cho Developer Portal qua StosSign. App Store Login và tải IPA trực tiếp chưa được tích hợp vì chưa xác minh được Device Identity hợp lệ trong app iOS. Hồ sơ iOS 27 bên dưới chỉ là dữ liệu mô phỏng để kiểm tra tương thích, không phải Simulator hay thông tin thiết bị dùng để xác thực.

## Tính năng hiện có

* Giao diện SwiftUI, hỗ trợ iOS 16+ trở lên.
* Tìm kiếm ứng dụng trên App Store theo tên hoặc App ID.
* Hiển thị vùng App Store dạng chỉ đọc và dùng vùng đó khi tìm kiếm.
* Tự chọn tiếng Việt khi storefront App Store là Việt Nam và tiếng Anh ở các vùng khác; có thể đổi thủ công giữa tiếng Việt và tiếng Anh trong Cài đặt.
* Xem thông tin ứng dụng: icon, Bundle ID, nhà phát triển và phiên bản.
* Tạo và lưu nhiều Device Profile mô phỏng từ iOS 27 trở lên.
* Kiểm tra tương thích từ metadata hoặc IPA cục bộ; thiếu dữ liệu được đánh dấu Unknown.
* Đọc CRC của ZIP, `Payload/*.app/Info.plist`, bundle/version, MinimumOSVersion, UIDeviceFamily, capability, platform và Mach-O architecture trong IPA đã chọn.
* Quản lý và tùy chỉnh Anisette Server.
* Đăng nhập Apple ID vào Developer Portal, hỗ trợ xác minh 2FA. Đây không phải phiên đăng nhập để tải từ App Store.
* Lưu và khôi phục phiên đăng nhập an toàn.
* Theo dõi nhật ký đăng nhập và hoạt động.
* Hỗ trợ kiểm thử và build tự động qua GitHub Actions.

## Kiểm tra Swift trên Codespaces

Codespace có Swift 6.4.3 cho `x86_64-unknown-linux-gnu`, cài qua Swiftly tại `/home/codespace/.local/share/swiftly/bin`. `which swift` tìm thấy đường dẫn này khi chạy ngoài sandbox; shell sandbox có thể không đưa Swiftly vào `PATH`. Script bên dưới thử cả `PATH` lẫn đường dẫn Swiftly mặc định.

```sh
which swift
swift --version
bash Scripts/test-linux-core.sh
```

Linux script biên dịch trực tiếp `Models.swift`, `DeviceProfile.swift` và `CompatibilityChecker.swift` ở Swift 6 mode, rồi chạy 17 assertion cho logic thuần Swift. `DeviceProfileStore` được tách sang file riêng vì nó cần Combine; script không build IPAForge iOS và không thay thế XCTest.

Các thay đổi hiện còn ở working tree. Vì yêu cầu không commit/push, GitHub Actions chưa được chạy trên chính những thay đổi này; lần chạy Actions của một commit khác không xác nhận được chúng.

Trong 15 test mới của Device Profile / Compatibility / IPA inspection / Download queue:

| Test trong `Tests/IPAForgeTests.swift` | Số test | Môi trường |
| --- | ---: | --- |
| `testDefaultProfileIsAnIOS27SimulatedProfile`, `testVersionComparisonAndProfileValidation`; sáu test `CompatibilityCheckerTests` | 8 | Logic tương đương đã chạy trong Linux harness; XCTest methods vẫn thuộc target Xcode |
| `testProfilesPersistAndRestoreSelectedModelAndVersion`, `testMultipleProfilesCanBeSelectedAndLastProfileCannotBeDeleted` | 2 | `DeviceProfileStore` dùng Combine; XCTest của app |
| `testValidIPAReadsMetadataAndMachOArchitecture`, `testInspectorRejectsWrongExtensionAndCorruptedZIP` | 2 | Foundation + ZIPFoundation; Linux có thể dùng được sau khi giải quyết dependency, nhưng chưa nằm trong harness hiện tại |
| `testProgressUsesActualBytesAndCancellationReachesProvider`, `testDownloadCompletesOnlyAfterIPAInspectionAndSavesValidatedFile`, `testFailureCanBeRetriedAsANewQueueTask` | 3 | `DownloadService` dùng Combine và app Documents; cần XCTest trên Apple platform |

Các test Anisette, Keychain/Security, UI và tích hợp với iOS của bộ cũ vẫn cần Xcode. Full XCTest target và iOS build chưa được xác nhận. Xem [bảng trạng thái kiểm thử](./Downloader/ROADMAP.md).

## Giới hạn App Store Downloader

Đăng nhập Apple ID hiện có trong app là phiên Developer Portal. Nó không thể dùng để mua license hay tải IPA từ App Store. Nút tải IPA hiện bị vô hiệu hóa; queue/provider chưa có backend App Store thật. Unit test dùng fixture/provider giả chỉ kiểm tra cơ chế queue và xác thực IPA, không chứng minh đăng nhập hoặc tải thật. IPAForge không tạo Device Identity giả và không giải mã FairPlay. Chi tiết nghiên cứu 20 repository, bằng chứng mã nguồn, blocker và trạng thái kiểm thử nằm trong [Downloader/ROADMAP.md](./Downloader/ROADMAP.md).

## Đối chiếu thư viện / giao thức

- [ApplePackage](https://github.com/Lakr233/ApplePackage) là Swift Package MIT, manifest khai báo iOS 15+, nhưng yêu cầu Swift 6.2 và dùng SAP-signed App Store authentication. Source `DeviceIdentifier.system()` chủ động lỗi trên iOS; package đề xuất GUID ngẫu nhiên đã lưu, trái yêu cầu không tự tạo Device Identifier. Chưa tích hợp và chưa xác minh đăng nhập thực trên iOS.
- [ipatool](https://github.com/majd/ipatool) là dự án Go MIT với API App Store login/2FA. Luồng hiện tại có SAP signing và machine identity phụ thuộc MAC; không phải Swift SDK và chưa xác minh được chạy đăng nhập trên iOS thông thường.
- [ipaverse](https://github.com/bahattinkoc/ipaverse) tham khảo được quy trình GSA/SRP-6a, 2FA và App Store session, nhưng là app macOS dùng IOKit/`ifconfig`/Anisette macOS. Không thể sao chép thẳng vào target iOS.
- GSA/SRP-6a và SAP-signed authentication là hai đường triển khai khác nhau trong các nguồn đã xem. ApplePackage hiện không triển khai GSA/SRP-6a. Chi tiết blocker, phạm vi và các kiểm tra còn thiếu được ghi ở [Downloader/ROADMAP.md](./Downloader/ROADMAP.md).
- [SideStore](https://github.com/SideStore/SideStore) và [AltStore](https://github.com/altstoreio/AltStore) dùng nền tảng Apple signing/sideloading riêng; cả hai README công bố AGPLv3. Không sao chép mã của hai dự án vào project MIT này. Tài liệu SideStore khuyến nghị Anisette v3 và nhấn mạnh không gửi account info đến Anisette server; app hiện chỉ áp dụng nguyên tắc tách biệt đó, chưa triển khai protocol.
- Tài liệu tham khảo: [SideStore Anisette](https://docs.sidestore.io/docs/advanced/anisette), [ipatool](https://github.com/majd/ipatool), [AltStore](https://github.com/altstoreio/AltStore).
- Anisette v3 dùng client Swift nội bộ, không thêm dependency hoặc sao chép mã thư viện bên thứ ba. `swift-anisette` không hỗ trợ iOS; `RemoteAnisette` không khai báo license; AnisetteKit công bố AGPL-3.0. Các dự án này không được tích hợp.
- [StosSign](https://github.com/stossy11/StosSign) là Swift Package (không phải HTTP service), được pin trực tiếp tại revision `01dd7bc4f5084ade9e2ebbc7e338dc2e3f454d77` và chỉ liên kết các product API/Auth/Common cần thiết. Revision này hỗ trợ iOS 14; ứng dụng yêu cầu iOS 16. StosSign xử lý SRP/2FA và Developer Team API; IPAForge chuyển `AnisetteData` từ headers v3 và lưu DTO session đã mã hóa trong vault. Người dùng xác nhận đã được maintainer cho phép sử dụng; repository hiện không công bố tệp LICENSE hoặc license metadata, nên tài liệu này không khẳng định một license công khai cụ thể. Không dùng helper của GetMoreRam vốn log payload Anisette.

## Build và test bằng Xcode

Mở `AppStoreIPADownloader.xcodeproj`, chọn scheme `AppStoreIPADownloader`, sau đó build/run trên iOS 16 trở lên. Để chạy test:

```sh
xcodebuild test \
  -project AppStoreIPADownloader.xcodeproj \
  -scheme AppStoreIPADownloader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Thiết bị đã thử: iOS 18.7.9 (theo xác nhận của người dùng; không nêu model thiết bị). Đây là thông tin thử nghiệm thủ công, không đồng nghĩa mọi chức năng đã hoàn thiện hoặc IPA đã được ký.

CI cần được xác nhận bằng lần chạy workflow gần nhất trên GitHub Actions. Workflow Experimental Build dùng Xcode 27.2 trên runner `xcode-27`; runner phải có runtime iOS Simulator tương thích.

## GitHub Actions

- **Experimental Build**: tự chạy khi push lên bất kỳ branch nào, hoặc chạy thủ công qua workflow dispatch. Mặc định bỏ qua unit tests để tạo IPA nhanh; khi chạy thủ công, có thể bật input `run_tests` để chạy test Simulator. Version trong app lấy theo `MARKETING_VERSION` khai báo trong Xcode (hiện là `1.0.0`); build number là GitHub Actions run number. Workflow upload artifact `IPAForge-1.0.0-<build>-Unsigned` chứa IPA unsigned cùng version. Đây chưa phải bản cài đặt đã ký.
- Chưa có workflow kiểm thử App Store Login. Không chỉnh workflow `experimental.yml` cho nhiệm vụ này; build app hiện tại không thể xác minh đăng nhập App Store thật.
- **Release Build**: chạy khi push tag `v*` hoặc workflow dispatch với `release_tag`; test, archive Release unsigned và tạo GitHub Release. Artifact tên `AppStoreIPA-Release`, file đính kèm là unsigned `.xcarchive.zip`, không phải IPA.
- Chưa cần certificate/secret để compile unsigned. Không thêm private key, certificate hay mật khẩu vào repository.

Workflow tạo GitHub Release cần quyền `contents: write` được bật cho Actions trong repository settings. Với workflow dispatch, cung cấp tag, ví dụ `v1.0.0`.

## Cấu trúc

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

## Giấy phép

Project hiện giữ [MIT License](./LICENSE). Chưa đưa mã nguồn hoặc dependency từ SideStore/AltStore vào repository. Nếu tích hợp ipatool, cần giữ notice MIT và vượt qua các bước kiểm tra khả năng chạy trên iOS trong [Downloader/ROADMAP.md](./Downloader/ROADMAP.md).
