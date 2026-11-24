# Hướng dẫn cho agent

## Trước khi sửa đổi

- Đọc `README.md`, tài liệu liên quan và mã nguồn hiện tại để hiểu kiến trúc, luồng dữ liệu, quy ước và giới hạn của tính năng.
- Kiểm tra cấu trúc repository và các module hiện có trước khi thiết kế thay đổi. Không suy đoán rằng một module, dịch vụ hoặc công nghệ tồn tại nếu chưa xác minh trong mã nguồn.
- Nêu rõ phạm vi dự định thay đổi; giữ bản sửa nhỏ, tương thích với hành vi hiện tại và không tạo module trùng lặp.

## Kiến trúc và phong cách

- Tuân thủ ngôn ngữ, framework, cấu trúc thư mục, quy ước định dạng và ranh giới module hiện có của repository.
- Nếu repository có phần TypeScript/Electron hoặc monorepo, tuân thủ cấu trúc workspace và ranh giới package hiện hành; không đưa mã Swift/iOS vào các phần đó.
- Trạng thái hiện tại của repository này là ứng dụng SwiftUI/Xcode cho iOS, dùng Swift language mode 5; chưa có `package.json`, cấu trúc Electron/TypeScript monorepo hoặc các module `SecretStore`/Electron `safeStorage`. Không được mô tả hoặc sử dụng những thành phần này như thể chúng đã tồn tại.
- Tái sử dụng API và module sẵn có. Chỉ tạo module mới khi kiến trúc yêu cầu rõ ràng và không có thành phần hiện hữu phù hợp.
- Không tự ý xóa, thay thế hoặc làm thay đổi chức năng hiện có. Chỉ làm vậy khi cần thiết cho yêu cầu, giải thích lý do và giữ các hành vi không liên quan.

## Dữ liệu nhạy cảm

- Không lưu mật khẩu, token, cookie, mã xác minh, khóa riêng hoặc dữ liệu nhạy cảm dưới dạng văn bản thuần; không ghi chúng vào log, fixture, tệp cấu hình hoặc tài liệu.
- Với thành phần Electron, dùng `SecretStore` và Electron `safeStorage` hiện có nếu chúng thực sự có trong repository. Xác minh API và cách gọi trước khi sử dụng.
- Nếu cần lưu bí mật nhưng kho lưu trữ an toàn chưa tồn tại hoặc hệ điều hành không hỗ trợ, không tự tạo cơ chế plaintext hay fallback kém an toàn. Báo rõ giới hạn và xin quyết định trước khi thêm hoặc thay đổi kiến trúc lưu trữ.
- Trong ứng dụng Swift hiện tại, không gửi hoặc lưu thông tin đăng nhập Apple nếu luồng xác thực và giải pháp lưu trữ an toàn chưa được triển khai, kiểm tra đầy đủ.

## Kiểm thử và xác minh

- Viết hoặc cập nhật kiểm thử tập trung cho mọi chức năng mới và các lỗi được sửa; không dùng dữ liệu tài khoản thật trong kiểm thử hoặc CI.
- Chạy các lệnh kiểm tra được tài liệu và cấu hình dự án quy định. Với project iOS hiện tại, lệnh test chuẩn là:

  ```sh
  xcodebuild test \
    -project AppStoreIPADownloader.xcodeproj \
    -scheme AppStoreIPADownloader \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
    CODE_SIGNING_ALLOWED=NO
  ```

- Nếu môi trường không có Xcode hoặc không thể chạy một kiểm tra, nói rõ kiểm tra nào chưa chạy và không tuyên bố đã xác minh. Dùng workflow GitHub Actions phù hợp khi cần xác nhận build/test trên macOS.
- Trước khi hoàn tất, kiểm tra diff, lỗi định dạng và mọi thay đổi ngoài phạm vi; không sửa các thay đổi có sẵn của người dùng.
