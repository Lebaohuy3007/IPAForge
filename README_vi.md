# IPAForge

Ứng dụng SwiftUI cho iOS 16+ để duyệt App Store, cấu hình endpoint Anisette và theo dõi các giới hạn của quy trình tải IPA.

**Đọc bằng:** [English](./README.md) | Tiếng Việt

### Thử nghiệm

| iOS Version | Trạng thái |
|:---:|:---:|
| 18.7.9 | Đã thử nghiệm |
| Phiên bản khác | Chưa xác minh |

> **Tình trạng hiện tại:** IPAForge tìm kiếm metadata công khai của App Store và có đăng nhập Apple ID riêng cho Developer Portal qua StosSign. App Store Login và tải IPA trực tiếp chưa được tích hợp. Mục Compatibility chỉ so sánh Minimum OS với iPhone 18 Pro/iOS 27.2 mô phỏng; không xác minh đầy đủ khả năng tương thích thiết bị và không bật tải IPA.

## Tính năng hiện có

* Giao diện SwiftUI, hỗ trợ iOS 16+ trở lên.
* Tìm kiếm ứng dụng trên App Store theo tên hoặc App ID.
* Hiển thị vùng App Store dạng chỉ đọc và dùng vùng đó khi tìm kiếm.
* Tự chọn tiếng Việt khi storefront App Store là Việt Nam và tiếng Anh ở các vùng khác; có thể đổi thủ công giữa tiếng Việt và tiếng Anh trong Cài đặt.
* Xem thông tin ứng dụng: icon, Bundle ID, nhà phát triển và phiên bản.
* So sánh Minimum OS của ứng dụng với iPhone 18 Pro/iOS 27.2 mô phỏng; kết quả chỉ áp dụng cho yêu cầu iOS tối thiểu, không phải xác nhận tương thích đầy đủ.
* Quản lý Anisette Server. Trước khi cấp phát, IPAForge thông báo server được chọn sẽ nhận identifier Anisette dùng lâu dài, `adi_pb` và một số dữ liệu trao đổi cấp phát với Apple. Người vận hành có thể đọc và lưu dữ liệu gửi qua server; có thể thu hồi quyền đã cấp.
* Đăng nhập Apple ID vào Developer Portal, hỗ trợ xác minh 2FA. Đây không phải phiên đăng nhập để tải từ App Store.
* Lưu và khôi phục an toàn phiên Developer Portal; đây không phải phiên App Store.
* Theo dõi nhật ký đăng nhập và hoạt động.
* Hỗ trợ kiểm thử và build tự động qua GitHub Actions.
* Chạy thử nghiệm API công khai không cần đăng nhập; kết quả hai thử nghiệm được ghi trong Activity Log.

## Kiểm tra

Trong môi trường Linux Codespaces, Swift 6.4.3 và `swiftc` có sẵn. `swiftc -frontend -parse` phân tích cú pháp toàn bộ file `.swift` thành công; `bash Scripts/test-linux-core.sh` biên dịch phần logic Swift thuần và chạy thành công 17 assertions. Script này không build ứng dụng iOS và không thay thế XCTest.

Repository không có `Package.swift`, nên không phải Swift Package độc lập và không chạy `swift test`. Xcode project có khai báo các Swift Package dependency, nhưng XCTest, build iOS và Simulator cần Xcode/iOS SDK nên chưa được xác minh trong môi trường Linux. Kiểm tra thêm gồm `git diff --check`, YAML workflow, JSON của String Catalog, XML Privacy Manifest và target membership trong Xcode project.

Các thay đổi hiện còn ở working tree. Vì yêu cầu không commit/push, GitHub Actions chưa được chạy trên chính những thay đổi này; lần chạy Actions của một commit khác không xác nhận được chúng.

Các test dùng `MockURLProtocol` chỉ kiểm tra logic ứng dụng, không xác minh xác thực Apple hay tải IPA thật. Xem [bảng trạng thái kiểm thử](./Downloader/ROADMAP.md).

## Giới hạn App Store Downloader

Đăng nhập Apple ID hiện có trong app là phiên Developer Portal. Nó không thể dùng để mua license hay tải IPA từ App Store. Nút tải IPA hiện bị vô hiệu hóa; queue/provider chưa có backend App Store thật. Nút thử nghiệm công khai kiểm tra Search/Lookup không cần tài khoản và ghi kết quả cùng blocker xác thực vào Activity Log. Test dùng fixture/provider giả chỉ kiểm tra logic; không chứng minh đăng nhập hoặc tải thật. IPAForge không tạo Device Identity giả và không giải mã FairPlay. Xem [nghiên cứu xác thực và bảng chấm điểm](./Downloader/AUTHENTICATION_RESEARCH.md) cùng [roadmap](./Downloader/ROADMAP.md).

## Đối chiếu thư viện / giao thức

- [ApplePackage](https://github.com/Lakr233/ApplePackage) là Swift Package MIT, manifest khai báo iOS 15+, nhưng yêu cầu Swift 6.2 và dùng SAP-signed App Store authentication. Source `DeviceIdentifier.system()` chủ động lỗi trên iOS; package đề xuất GUID ngẫu nhiên đã lưu, trái yêu cầu không tự tạo Device Identifier. Chưa tích hợp và chưa xác minh đăng nhập thực trên iOS.
- [ipatool](https://github.com/majd/ipatool) là dự án Go MIT với API App Store login/2FA và download. Bản iOS dành cho thiết bị jailbreak; issue của v2.8.1 báo lỗi Unicorn ARM64 trước khi xác thực trên iPhone jailbreak. Không phải Swift SDK và chưa có đường đã xác minh cho IPAForge iOS thông thường.
- [Crumb](https://github.com/boierito/Crumb) và [iPadN](https://github.com/mengangs/ipadn) hiện tuyên bố hỗ trợ đăng nhập và tải App Store trên iOS không jailbreak. IPAForge chưa tự xác minh các luồng đó. Thông báo license của họ nêu GPL, upstream không có license và quyền phân phối một số runtime có nguồn gốc Apple chưa rõ; vì vậy chưa tích hợp mã vào project MIT này.
- [ipaverse](https://github.com/bahattinkoc/ipaverse) tham khảo được quy trình GSA/SRP-6a, 2FA, PET-to-Store, license và download, nhưng là app macOS dùng IOKit/`ifconfig`; mã nguồn còn có UUID ngẫu nhiên làm định danh dự phòng. Không thể sao chép thẳng vào target iOS theo yêu cầu không tạo identity giả.
- GSA/SRP-6a và SAP-signed authentication là hai đường triển khai khác nhau trong các nguồn đã xem. ApplePackage hiện không triển khai GSA/SRP-6a. Chi tiết blocker, phạm vi và các kiểm tra còn thiếu được ghi ở [Downloader/ROADMAP.md](./Downloader/ROADMAP.md).
- [SideStore](https://github.com/SideStore/SideStore) và [AltStore](https://github.com/altstoreio/AltStore) dùng nền tảng Apple signing/sideloading riêng; cả hai README công bố AGPLv3. Không sao chép mã của hai dự án vào project MIT này. Tài liệu SideStore khuyến nghị Anisette v3 và nhấn mạnh không gửi account info đến Anisette server; app hiện chỉ áp dụng nguyên tắc tách biệt đó, chưa triển khai protocol.
- Tài liệu tham khảo: [SideStore Anisette](https://docs.sidestore.io/docs/advanced/anisette), [ipatool](https://github.com/majd/ipatool), [AltStore](https://github.com/altstoreio/AltStore), [nghiên cứu và bảng chấm điểm](./Downloader/AUTHENTICATION_RESEARCH.md).
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

Workflow Experimental Build dùng Xcode 27.2 trên runner `xcode-27`; runner cần có runtime iOS Simulator tương thích khi bật test. CI chưa được chạy trên working tree này.

## GitHub Actions

- **Experimental Build**: chỉ chạy thủ công qua workflow dispatch. Mặc định bỏ qua unit tests; có thể bật input `run_tests` để chạy test Simulator. Version trong app lấy theo `MARKETING_VERSION` khai báo trong Xcode (hiện là `1.0.0`); build number là GitHub Actions run number. Workflow upload artifact `IPAForge-1.0.0-Unsigned` chứa IPA unsigned. Đây chưa phải bản cài đặt đã ký.
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

Project hiện giữ [MIT License](./LICENSE.txt). Chưa đưa mã nguồn hoặc dependency từ SideStore/AltStore vào repository. Xem [nghiên cứu](./Downloader/AUTHENTICATION_RESEARCH.md) trước khi cân nhắc engine App Store.
