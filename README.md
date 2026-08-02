# NetFlow Universal v4.1

Ứng dụng SwiftUI iOS/iPadOS 16+ theo dõi tổng lưu lượng Wi‑Fi và dữ liệu di động, quản lý gói ngày/tháng/năm, cảnh báo và xuất PDF chi tiết từng ngày.

## Điểm mới v3

- Một mã nguồn và một IPA có thể tự thích nghi theo **khả năng thực tế** của môi trường cài đặt.
- Trang **Khả năng hệ thống** kiểm tra thông báo, làm mới nền, vị trí, SSID, IP công cộng, VPN, Widget và Live Activities.
- Không đoán LiveContainer/TrollStore bằng đường dẫn riêng tư; ứng dụng bật/tắt UI theo quyền/API đang hoạt động.
- Giao diện Universal: TabView trên iPhone, NavigationSplitView trên iPad.
- Giữ mặc định **không chuyển dung lượng dư** sang chu kỳ mới.

## Giới hạn cần hiểu đúng

Một IPA không thể tự sinh entitlement sau khi đã ký. Widget, Live Activities, Access WiFi Information, App Groups hoặc Network Extension chỉ hoạt động khi target tương ứng tồn tại và chữ ký/provisioning giữ được entitlement. LiveContainer có thể chạy app chính nhưng thường không chạy đầy đủ app extension. TrollStore hoặc chứng chỉ phù hợp có thể giữ được nhiều khả năng hơn.

## Build

1. Mở `NetFlow.xcodeproj` bằng Xcode 15/16.
2. Chọn Development Team và Bundle Identifier riêng.
3. Build trên thiết bị thật để kiểm tra bộ đếm mạng, SSID và trạng thái nền.
4. Có thể tái tạo project bằng XcodeGen từ `project.yml`.

Không dùng CocoaPods hay thư viện ngoài.


## Build-ready v3.2

- Open `NetFlow.xcodeproj` in Xcode 15 or later.
- Select target **NetFlow** → **Signing & Capabilities** → choose your Team.
- Change the bundle identifier if `com.duyhoang.netflow` is already used.
- App icon asset catalog is now included in the target resources.
- Notification permission is requested on first launch and threshold alerts create local notifications.
- For Wi-Fi SSID, optionally add **Access WiFi Information** capability. Do not enable it when the signing profile does not support that entitlement.
- No third-party packages are required.

The app does not claim continuous background sampling. iOS may suspend it; totals are reconciled when it becomes active again.


## LiveContainer compatibility fix (v3.6)

The custom Info.plist now explicitly contains `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, `CFBundlePackageType`, version keys and iOS bundle metadata. This prevents direct IPA loaders from resolving the executable as `(null)` and showing `Failed to map ... (null): Bad file descriptor`.

After Archive/export, verify that `Payload/NetFlow.app/Info.plist` contains `CFBundleExecutable = NetFlow` and that `Payload/NetFlow.app/NetFlow` exists.


## v3.6 compile fix

- Fixed `SystemCapabilitiesService` references to Wi-Fi path, public IP and VPN state.
- Added stable compatibility accessors on `NetworkContextService`.
- Prevents the three Xcode errors: `pathUsesWiFi`, `publicIPAddress`, and `vpnConnected` not found.


## Thay đổi v3.6
- Phát hiện VPN nghiêm ngặt hơn để tránh báo kết nối sai do giao diện utun không hoạt động.
- Hiển thị riêng IP công cộng IPv4 và IPv6.
- Thời tiết và tên địa điểm chỉ lấy từ vị trí hiện tại bằng Core Location.
- Bổ sung tên nhà mạng bằng CoreTelephony khi iOS cung cấp.
- Bổ sung entitlement Access WiFi Information và cơ chế đọc SSID bằng NEHotspotNetwork.
- Dung lượng gói hỗ trợ MB, GB, TB; mặc định GB.
- Tổng quan hiển thị chu kỳ và dung lượng gói bằng màu xanh lá.

## v3.7 – Xcode build audit

- Replaced `ToolbarItemPlacement.topBarTrailing` with `navigationBarTrailing` for reliable iOS 16 compilation.
- Synchronized `project.yml` with the Wi-Fi entitlement, version and build number.
- Added `SWIFT_STRICT_CONCURRENCY = minimal` so Xcode 16 builds the Swift 5 code without Swift 6 concurrency diagnostics becoming blocking errors.
- Verified every Swift source is included in Compile Sources and all localization/icon resources are included in Copy Bundle Resources.


## Personal Development Team

Bản v4.0 mặc định không khai báo entitlement `com.apple.developer.networking.wifi-info`,
vì Apple Personal Development Team không hỗ trợ quyền này.

Kết quả:
- Xcode có thể tự tạo provisioning profile cho chứng chỉ cá nhân.
- Ứng dụng vẫn theo dõi lưu lượng, IP, VPN, vị trí, thời tiết, nhà mạng và xuất PDF.
- Tên Wi-Fi có thể hiển thị `Không khả dụng` nếu iOS không cho phép đọc SSID.
- Không cần bật Access Wi-Fi Information trong Signing & Capabilities.

Nếu sau này dùng tài khoản Apple Developer trả phí và App ID hỗ trợ quyền này,
có thể thêm lại capability Access Wi-Fi Information thủ công.


## v4.0 – NetworkInterfaceReader compile fix

- Viết lại hoàn toàn `NetworkInterfaceReader.swift` bằng API iOS 16 ổn định.
- Loại bỏ `NetworkExtension`, `NEHotspotNetwork` và CaptiveNetwork khỏi bản Personal Team.
- Sửa cách đọc `ifa_data`, `ifaddrs`, địa chỉ IPv4/IPv6 và cờ giao diện.
- Tách `CLLocationManagerDelegate` thành extension `nonisolated` để tránh lỗi actor isolation.
- Giữ SSID ở trạng thái không khả dụng thay vì gọi API cần entitlement không được Personal Team hỗ trợ.


## Thay đổi v4.1

- Chuyển “Cập nhật lần cuối” lên đầu trang Tổng quan.
- Chu kỳ là menu gọn với đúng 3 lựa chọn: Ngày, Tháng, Năm.
- Dữ liệu cũ dùng chu kỳ Tùy chỉnh/Không giới hạn sẽ được chuyển an toàn về Tháng khi mở trang Gói dữ liệu.
- Giữ thao tác chạm ra ngoài hoặc bấm Xong để ẩn bàn phím.
