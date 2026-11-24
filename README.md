# IPAForge

Ứng dụng SwiftUI cho iOS 16+ để duyệt App Store, cấu hình endpoint Anisette và theo dõi các giới hạn của quy trình tải IPA.

### Thử nghiệm

| iOS Version | Trạng thái |
|:---:|:---:|
| 18.7.9 | Đã thử nghiệm |
| Phiên bản khác | Chưa xác minh |

> **Tình trạng hiện tại:** IPAForge hiện đã có chức năng tìm kiếm ứng dụng trên App Store và tích hợp đăng nhập Apple ID. Tuy nhiên, chức năng tải ứng dụng dưới dạng IPA vẫn chưa được triển khai. Đăng nhập Apple và các tính năng liên quan chưa được xác minh đầy đủ với tài khoản thật.

## Tính năng hiện có

* Giao diện SwiftUI, hỗ trợ iOS 16+ trở lên.
* Tìm kiếm ứng dụng trên App Store theo tên hoặc App ID.
* Chọn vùng App Store để xem kết quả theo quốc gia.
* Xem thông tin ứng dụng: icon, Bundle ID, nhà phát triển và phiên bản.
* Quản lý và tùy chỉnh Anisette Server.
* Đăng nhập Apple ID, hỗ trợ xác minh 2FA và chọn Developer Team.
* Lưu và khôi phục phiên đăng nhập an toàn.
* Theo dõi nhật ký đăng nhập và hoạt động.
* Hỗ trợ kiểm thử và build tự động qua GitHub Actions.

## Đối chiếu thư viện / giao thức

- [ipatool](https://github.com/majd/ipatool) là công cụ Go có quy trình App Store thực tế (auth, purchase, download), mã nguồn MIT. Đây là CLI đa nền tảng, không phải Swift/iOS SDK; chưa tích hợp hoặc port vào app vì phải xác nhận đầy đủ khả năng build/chạy trong sandbox iOS, vòng đời credentials, luồng 2FA và Anisette trước.
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

- **Experimental Build**: tự chạy khi push lên bất kỳ branch nào, hoặc chạy thủ công qua workflow dispatch. Mặc định bỏ qua unit tests để tạo IPA nhanh; khi chạy thủ công, có thể bật input `run_tests` để chạy test Simulator. Workflow build app version `1.0.0` (build number là GitHub Actions run number) và upload artifact `IPAForge-1.0.0-<build>-Unsigned` chứa IPA unsigned cùng version. Đây chưa phải bản cài đặt đã ký.
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

Project hiện giữ [MIT License](./LICENSE). Chưa đưa mã nguồn hoặc dependency từ SideStore/AltStore vào repository. Việc tích hợp ipatool trong tương lai cần giữ nguyên notice MIT và kiểm tra tương thích kỹ thuật trước khi triển khai.
