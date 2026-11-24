# IPAForge

Ứng dụng SwiftUI cho iOS 16+ để duyệt App Store, cấu hình endpoint Anisette và theo dõi các giới hạn của quy trình tải IPA. Giao diện hỗ trợ cả Light và Dark Mode.

> **Tình trạng hiện tại:** Đây chưa phải downloader hoạt động đầu-cuối. App Store Search dùng iTunes Search API công khai và chạy thật. Đăng nhập Apple qua StosSign (SRP/2FA), lấy Developer Teams và lưu/khôi phục session mã hóa đã được nối vào ứng dụng; chưa xác minh với tài khoản Apple thật hoặc chạy được Xcode test trong môi trường hiện tại. Tải package từ Store chưa được triển khai.

## Tính năng hiện có

- SwiftUI app và Xcode project, deployment target iOS 16, Swift language mode 5.
- Giao diện chính có App Store Search và Profile; mục Settings/Today/editorial/demo đã bỏ khỏi thanh điều hướng.
- Tìm kiếm ứng dụng theo tên hoặc App ID, xem bundle ID, developer, version, icon và metadata có sẵn.
- Quản lý danh sách Anisette Server SideStore/jkcoxson và nguồn tùy chỉnh; SideStore được chọn mặc định, chạm để đổi server, thêm/sửa/xóa nguồn trong cùng màn hình, chống URL trùng và lưu lựa chọn bằng UserDefaults.
- Probe bất đồng bộ GET `/v3/client_info`, timeout 8 giây, đo RTT bằng monotonic clock; chỉ đánh dấu usable khi có `client_info` và `user_agent`.
- Client Anisette v3 lấy metadata, thực hiện Apple provisioning qua WebSocket của server đã chọn, lưu `identifier`/`adi.pb` trong AppleAccountVault mã hóa AES-256-GCM/Keychain, rồi yêu cầu `/v3/get_headers`. Không gửi Apple ID, mật khẩu hoặc mã 2FA; server được chọn nhận identifier và dữ liệu provisioning cần cho v3.
- Log Viewer có mức log, xóa/copy nhật ký và bộ lọc thông tin xác thực.
- Màn hình Sign In dùng StosSign để xác thực Apple ID, nhận mã 2FA, tải Developer Teams và cho chọn team; Login Logs riêng, tự cuộn, có thời gian/mức độ, xóa độc lập với log toàn app và lọc dữ liệu nhạy cảm.
- Dịch vụ tải xuống từ chối rõ ràng thay vì báo thành công giả.
- Kho phiên Apple Account dùng AES-256-GCM với khóa trong Keychain iOS, mục Keychain chỉ dùng trên thiết bị hiện tại; session StosSign được chuyển sang DTO phiên bản hóa, không lưu mật khẩu. Nhiều tài khoản có thể được khôi phục bằng cách lấy Anisette v3 mới và xác minh account/teams với Apple.
- Unit tests cho URL validation, Anisette v3, timeout/payload sai, `/v3/get_headers`, CRUD/persistence server, log sanitization, xác thực/2FA bằng provider giả lập, mã hóa/khôi phục/xóa vault và kiểm tra file export.
- Hai GitHub Actions workflow build/test trên macOS.

## Giới hạn quan trọng

1. **Chưa xác minh đăng nhập trực tiếp với Apple.** Mã tích hợp StosSign, SRP, 2FA, Developer Teams và session restore; Apple có thể thay đổi API hoặc từ chối Anisette. Dùng tài khoản thử nghiệm phù hợp và xác minh trên iOS trước khi dựa vào tính năng này.
2. **Anisette server là bên thứ ba.** Client v3 provision identity và lấy headers từ server được chọn; identity được lưu mã hóa, nhưng server nhận identifier và dữ liệu provisioning. Probe chỉ xác minh `/v3/client_info`, không bảo đảm provisioning hoặc `/v3/get_headers` thành công. Apple ID, mật khẩu và mã 2FA được gửi trong các request xác thực trực tiếp tới Apple qua StosSign, không gửi tới Anisette server.
3. **Server đang chọn không tự failover.** Khi probe tiếp theo thất bại, lựa chọn vẫn hiển thị để tránh đổi identity âm thầm nhưng không còn trạng thái usable; người dùng có thể chọn một nguồn đã probe hợp lệ.
4. **IPA download chưa triển khai.** Nút Download IPA tạo trạng thái lỗi giải thích, không gọi mua/tải Store, không vượt DRM và không tạo package giả.
5. **Share Sheet chỉ được bật khi có file `.ipa`.** Export kiểm tra file tồn tại, đuôi `.ipa` và ZIP local-header signature; bước này không xác minh đầy đủ cấu trúc `Payload/*.app`. Chưa có file tải về do downloader chưa hoạt động; không tạo file mẫu để tạo cảm giác hoàn thành.
6. **Build workflow unsigned.** App có version hiển thị `1.0.0`; Experimental Build dùng số thứ tự workflow làm build number, đóng gói `.app` vào `Payload/` và xuất `IPAForge-1.0.0-<build>-unsigned.ipa`. File IPA chưa được ký và không thể cài trực tiếp; muốn cài đặt cần cấu hình signing hợp lệ và xác minh riêng trên thiết bị. Release Build hiện xuất `.xcarchive.zip`, không phải IPA.
7. API tìm kiếm công khai không chứng minh người dùng sở hữu ứng dụng, quyền tải lại hoặc khả năng lấy binary.

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

- **Experimental Build**: workflow dispatch thủ công; chạy unit tests, build app version `1.0.0` (build number là GitHub Actions run number) và upload artifact `IPAForge-1.0.0-<build>-Unsigned` chứa IPA unsigned cùng version. Đây chưa phải bản cài đặt đã ký.
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
