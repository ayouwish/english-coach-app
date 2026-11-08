import Foundation
import OSLog
import PhotosUI
import SwiftUI
import UIKit

private let pickerLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "media")

/// 相册选择按钮（task-14 冻结签名：`init(onImage:)`）。
///
/// 用系统 `PhotosPicker`（底层是 `PHPickerViewController` 的跨进程选择器）：
/// - **不申请相册读取权限**，也不需要 `NSPhotoLibraryUsageDescription`；
/// - 用户选中一张后才把图片数据交给 App，未选中/取消都不会回调（页面无副作用）；
/// - 只匹配图片（`matching: .images`），不开启多选。
///
/// 调用方把它当成一个普通按钮放进“选来源”区域即可；**不要**再包一层
/// `PHPhotoLibrary.requestAuthorization`。
struct PhotoLibraryPicker: View {
    private let relay: ImageActionRelay
    @State private var selection: PhotosPickerItem?

    /// 用 `@MainActor` 是为了在主线程构造接力盒；调用点（SwiftUI 视图构建）本来就在主线程。
    @MainActor
    init(onImage: @escaping (UIImage) -> Void) {
        self.relay = ImageActionRelay(onImage)
    }

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Label("从相册选择", systemImage: "photo.on.rectangle")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 16)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("从相册选择一张照片")
        .onChange(of: selection) { _, newItem in
            guard let newItem else { return }
            // 清空选择，允许用户再次选择同一张照片（否则 onChange 不再触发）。
            selection = nil
            load(newItem)
        }
    }

    /// 把 `PhotosPickerItem` 的字节读出来并解成 `UIImage`。
    ///
    /// 只捕获 Sendable 的接力盒和 item，不把 View 自身带进 `Task`；
    /// `UIImage(data:)` 的解码是懒加载（真正绘制时才解像素），不会在这里卡住主线程。
    private func load(_ item: PhotosPickerItem) {
        let relay = relay
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                pickerLogger.debug("photo picker load failed")
                return
            }
            relay.deliver(image)
        }
    }
}

/// `PhotoLibraryPicker` 的回调接力盒。
///
/// 全局 actor 隔离的类隐式满足 `Sendable`，因此可以安全地被 `@MainActor` 的 `Task` 捕获；
/// 它只做一件事：回到主线程后把图片交给调用方闭包。
@MainActor
private final class ImageActionRelay {
    private let onImage: (UIImage) -> Void

    init(_ onImage: @escaping (UIImage) -> Void) {
        self.onImage = onImage
    }

    func deliver(_ image: UIImage) {
        onImage(image)
    }
}
