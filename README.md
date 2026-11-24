# AppStore IPA Downloader

Ứng dụng SwiftUI cho iOS 16+ để duyệt App Store, cấu hình endpoint Anisette và theo dõi các giới hạn của quy trình tải IPA. Mục tiêu thiết bị là iPhone XS Max; giao diện hỗ trợ cả Light và Dark Mode.

> **Tình trạng hiện tại:** Đây chưa phải downloader hoạt động đầu-cuối. App Store Search dùng iTunes Search API công khai và chạy thật. Đăng nhập Apple Account, trao đổi Anisette v3, tải package từ Store và tiến trình download chưa được triển khai. Giao diện không giả lập đăng nhập/thành công và không tạo file IPA giả.

## Tính năng hiện có

- SwiftUI app và Xcode project, deployment target iOS 16, Swift language mode 5.
- Tìm kiếm ứng dụng theo tên hoặc App ID, xem bundle ID, developer, version, icon và metadata có sẵn.
- Cấu hình/lưu URL Anisette; chỉ chấp nhận HTTPS, kiểm tra khả năng truy cập endpoint mà không gửi Apple Account.
- Log Viewer có mức log, xóa/copy nhật ký và bộ lọc thông tin xác thực.
- Dịch vụ xác thực và tải xuống từ chối rõ ràng thay vì báo thành công giả.
- Unit tests cho URL validation, tìm kiếm bằng URLProtocol giả lập, log sanitization, lỗi xác thực và kiểm tra file export.
- Hai GitHub Actions workflow build/test trên macOS.

## Giới hạn quan trọng

1. **Authentication/2FA chưa có.** `AuthenticationService` cố ý không gửi hoặc lưu email, mật khẩu, mã xác minh, token hay cookie. Không nhập tài khoản Apple thật vào bản này.
2. **Anisette status chỉ kiểm tra HTTPS reachability.** Đây không phải xác nhận giao thức Anisette v3 tương thích hoặc kiểm tra provisioning. Không có thông tin tài khoản nào được gửi đến server.
3. **IPA download chưa triển khai.** Nút Download IPA tạo trạng thái lỗi giải thích, không gọi mua/tải Store, không vượt DRM và không tạo package giả.
4. **Share Sheet chỉ được bật khi có file `.ipa`.** Export kiểm tra file tồn tại, đuôi `.ipa` và ZIP local-header signature; bước này không xác minh đầy đủ cấu trúc `Payload/*.app`. Chưa có file tải về do downloader chưa hoạt động; không tạo file mẫu để tạo cảm giác hoàn thành.
5. **Build workflow unsigned.** Artifact là `.app` hoặc `.xcarchive` unsigned, không phải IPA ký và chưa được chứng minh cài được trên iPhone. Muốn cài đặt cần cấu hình signing hợp lệ và xác minh riêng trên thiết bị.
6. API tìm kiếm công khai không chứng minh người dùng sở hữu ứng dụng, quyền tải lại hoặc khả năng lấy binary.

## Đối chiếu thư viện / giao thức

- [ipatool](https://github.com/majd/ipatool) là công cụ Go có quy trình App Store thực tế (auth, purchase, download), mã nguồn MIT. Đây là CLI đa nền tảng, không phải Swift/iOS SDK; chưa tích hợp hoặc port vào app vì phải xác nhận đầy đủ khả năng build/chạy trong sandbox iOS, vòng đời credentials, luồng 2FA và Anisette trước.
- [SideStore](https://github.com/SideStore/SideStore) và [AltStore](https://github.com/altstoreio/AltStore) dùng nền tảng Apple signing/sideloading riêng; cả hai README công bố AGPLv3. Không sao chép mã của hai dự án vào project MIT này. Tài liệu SideStore khuyến nghị Anisette v3 và nhấn mạnh không gửi account info đến Anisette server; app hiện chỉ áp dụng nguyên tắc tách biệt đó, chưa triển khai protocol.
- Tài liệu tham khảo: [SideStore Anisette](https://docs.sidestore.io/docs/advanced/anisette), [ipatool](https://github.com/majd/ipatool), [AltStore](https://github.com/altstoreio/AltStore).

## Build và test bằng Xcode

Mở `AppStoreIPADownloader.xcodeproj`, chọn scheme `AppStoreIPADownloader`, sau đó build/run trên iOS 16 trở lên. Để chạy test:

```sh
xcodebuild test \
  -project AppStoreIPADownloader.xcodeproj \
  -scheme AppStoreIPADownloader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Chưa thể xác nhận build/test trong môi trường Codespaces hiện tại do không có Xcode hoặc Swift toolchain. GitHub Actions dùng macOS runner để thực hiện xác nhận này.

## GitHub Actions

- **Experimental Build**: chạy khi push `main` hoặc workflow dispatch; chạy unit tests, build unsigned `.app`, upload artifact `AppStoreIPA-Experimental`.
- **Release Build**: chạy khi push tag `v*` hoặc workflow dispatch với `release_tag`; test, archive Release unsigned và tạo GitHub Release. Artifact tên `AppStoreIPA-Release`, file đính kèm là unsigned `.xcarchive.zip`.
- Chưa cần certificate/secret để compile unsigned. Không thêm private key, certificate hay mật khẩu vào repository.

Workflow tạo GitHub Release cần quyền `contents: write` được bật cho Actions trong repository settings. Với workflow dispatch, cung cấp tag, ví dụ `v1.0.0`.

## Cấu trúc

```text
App/                 SwiftUI app entry
Views/               Login, search, details, downloads, logs, settings
ViewModels/          App environment/settings
Models/              App and download state
Services/            Separated services under their own feature folders
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
