# AppStore IPA Downloader

Ứng dụng SwiftUI cho iOS 16+ để duyệt App Store, cấu hình endpoint Anisette và theo dõi các giới hạn của quy trình tải IPA. Mục tiêu thiết bị là iPhone XS Max; giao diện hỗ trợ cả Light và Dark Mode.

> **Tình trạng hiện tại:** Đây chưa phải downloader hoạt động đầu-cuối. App Store Search dùng iTunes Search API công khai và chạy thật. Quản lý nguồn và kiểm tra phản hồi Anisette v1 đã có; Apple Account sign-in, Apple SRP/2FA, Anisette v3 provisioning/get_headers và tải package từ Store chưa được triển khai. Giao diện không giả lập đăng nhập/thành công và không tạo file IPA giả.

## Tính năng hiện có

- SwiftUI app và Xcode project, deployment target iOS 16, Swift language mode 5.
- Tìm kiếm ứng dụng theo tên hoặc App ID, xem bundle ID, developer, version, icon và metadata có sẵn.
- Quản lý danh sách Anisette Server SideStore/jkcoxson và nguồn tùy chỉnh; thêm/sửa/xóa, chống URL trùng, chọn nguồn, xác nhận xóa, lưu danh sách và lựa chọn bằng UserDefaults.
- Probe bất đồng bộ GET endpoint gốc, timeout 8 giây, đo RTT bằng monotonic clock. Phân biệt không phản hồi, có phản hồi nhưng payload không hợp lệ, và JSON Anisette v1 có hai trường bắt buộc `X-Apple-I-MD`/`X-Apple-I-MD-M`.
- Không đánh dấu `/v3/client_info` hoặc HTTP reachability là Anisette hợp lệ; không gửi Apple ID, mật khẩu, mã 2FA, token hay Anisette identity khi probe.
- Log Viewer có mức log, xóa/copy nhật ký và bộ lọc thông tin xác thực.
- Dịch vụ xác thực và tải xuống từ chối rõ ràng thay vì báo thành công giả.
- Unit tests cho URL validation, probe Anisette v1/timeout/payload sai, CRUD và persistence danh sách server, chọn/không failover, tìm kiếm bằng URLProtocol giả lập, log sanitization, lỗi xác thực và kiểm tra file export.
- Hai GitHub Actions workflow build/test trên macOS.

## Giới hạn quan trọng

1. **Authentication/2FA chưa có.** `AuthenticationService` cố ý không gửi hoặc lưu email, mật khẩu, mã xác minh, token hay cookie. Không nhập tài khoản Apple thật vào bản này.
2. **Chỉ probe Anisette v1 đã được kiểm tra.** Giao thức đang probe là GET root JSON và xác thực hai trường theo response model Anisette v1. `ani.sidestore.io` hoặc nguồn chỉ hỗ trợ v3 sẽ không được đánh dấu sẵn sàng nếu không trả về schema v1 này. Chưa tích hợp `/v3/client_info`, `/v3/get_headers`, provisioning WebSocket hoặc `adi.pb`; không thể xác nhận server v3 dùng được. Không có dữ liệu tài khoản hay Anisette identity nào gửi khi probe.
3. **Server đang chọn không tự failover.** Khi probe tiếp theo thất bại, lựa chọn vẫn hiển thị để tránh đổi identity âm thầm nhưng không còn trạng thái usable; người dùng có thể chọn một nguồn đã probe hợp lệ. Không có phiên Apple đang hoạt động trong bản này.
4. **IPA download chưa triển khai.** Nút Download IPA tạo trạng thái lỗi giải thích, không gọi mua/tải Store, không vượt DRM và không tạo package giả.
5. **Share Sheet chỉ được bật khi có file `.ipa`.** Export kiểm tra file tồn tại, đuôi `.ipa` và ZIP local-header signature; bước này không xác minh đầy đủ cấu trúc `Payload/*.app`. Chưa có file tải về do downloader chưa hoạt động; không tạo file mẫu để tạo cảm giác hoàn thành.
6. **Build workflow unsigned.** Artifact là `.app` hoặc `.xcarchive` unsigned, không phải IPA ký và chưa được chứng minh cài được trên iPhone. Muốn cài đặt cần cấu hình signing hợp lệ và xác minh riêng trên thiết bị.
7. API tìm kiếm công khai không chứng minh người dùng sở hữu ứng dụng, quyền tải lại hoặc khả năng lấy binary.

## Đối chiếu thư viện / giao thức

- [ipatool](https://github.com/majd/ipatool) là công cụ Go có quy trình App Store thực tế (auth, purchase, download), mã nguồn MIT. Đây là CLI đa nền tảng, không phải Swift/iOS SDK; chưa tích hợp hoặc port vào app vì phải xác nhận đầy đủ khả năng build/chạy trong sandbox iOS, vòng đời credentials, luồng 2FA và Anisette trước.
- [SideStore](https://github.com/SideStore/SideStore) và [AltStore](https://github.com/altstoreio/AltStore) dùng nền tảng Apple signing/sideloading riêng; cả hai README công bố AGPLv3. Không sao chép mã của hai dự án vào project MIT này. Tài liệu SideStore khuyến nghị Anisette v3 và nhấn mạnh không gửi account info đến Anisette server; app hiện chỉ áp dụng nguyên tắc tách biệt đó, chưa triển khai protocol.
- Tài liệu tham khảo: [SideStore Anisette](https://docs.sidestore.io/docs/advanced/anisette), [ipatool](https://github.com/majd/ipatool), [AltStore](https://github.com/altstoreio/AltStore).
- Bộ response v1 được đối chiếu với [AnisetteKit AnisetteDataResponse](https://github.com/mahee96/AnisetteKit) và SideSign; chưa tích hợp mã của các dự án này.

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

- **Experimental Build**: workflow dispatch thủ công; chạy unit tests, build unsigned `.app`, upload artifact `AppStoreIPA-Experimental`.
- **Release Build**: chạy khi push tag `v*` hoặc workflow dispatch với `release_tag`; test, archive Release unsigned và tạo GitHub Release. Artifact tên `AppStoreIPA-Release`, file đính kèm là unsigned `.xcarchive.zip`.
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
