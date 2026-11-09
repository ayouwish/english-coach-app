import AVFoundation
import OSLog
import SwiftUI
import UIKit

private let cameraLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "media")

/// 相机拍照（task-14 冻结签名：`init(onImage:onCancel:)`）。
///
/// 调用方式：页面用 `.fullScreenCover(isPresented: $showCamera) { CameraPicker(...) }` 包住。
///
/// 权限策略（story 创建向导 / 头像页共用）：
/// - 已授权 → 直接打开相机；
/// - **被拒/受家长控制**（`.denied` / `.restricted`）→ **不弹任何系统或自绘权限框**，
///   调用 `onCancel`，由页面展示自己的权限引导卡（去设置文案由页面负责）；
/// - 首次使用（`.notDetermined`）→ 触发一次系统授权弹窗；用户拒绝后同样走 `onCancel`；
/// - 设备没有相机（模拟器）→ 立即 `onCancel`，不崩溃。
///
/// 回调都在主线程；`onImage` / `onCancel` 只会被调用一次。
struct CameraPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController

    private let onImage: (UIImage) -> Void
    private let onCancel: () -> Void

    init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onImage = onImage
        self.onCancel = onCancel
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        let coordinator = context.coordinator

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraLogger.debug("camera source unavailable")
            coordinator.notifyCancel()
            return Self.makePlaceholderController()
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return Self.makeCameraController(coordinator: coordinator)
        case .notDetermined:
            // 首次进入：相机权限的系统弹窗只能在这里触发一次；拒绝了就回调用方展示引导。
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard !granted else { return }
                Task { @MainActor in
                    coordinator.notifyCancel()
                }
            }
            return Self.makeCameraController(coordinator: coordinator)
        case .denied, .restricted:
            cameraLogger.debug("camera access denied")
            coordinator.notifyCancel()
            return Self.makePlaceholderController()
        @unknown default:
            coordinator.notifyCancel()
            return Self.makePlaceholderController()
        }
    }

    @MainActor
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // 相机界面由系统维护，无需增量更新。
    }

    // MARK: - 控制器构造

    @MainActor
    private static func makeCameraController(coordinator: Coordinator) -> UIViewController {
        let picker = UIImagePickerController()
        picker.delegate = coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    @MainActor
    private static func makePlaceholderController() -> UIViewController {
        // 不可用/被拒时先给一个空容器，`onCancel` 在下一个 runloop 回调，页面随即关闭本 cover。
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor.secondarySystemBackground
        return controller
    }

    /// 相机代理。iOS 26 SDK 里 UIKit 的代理协议已经是 `@MainActor`，
    /// Coordinator 本身也是 `@MainActor`，直接声明一致性即可（不再需要 `@preconcurrency`）。
    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onImage: (UIImage) -> Void
        private let onCancel: () -> Void
        private var didNotify = false

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard !didNotify else { return }
            guard let image = info[.originalImage] as? UIImage else {
                cameraLogger.debug("camera returned no image")
                notifyCancel()
                return
            }
            didNotify = true
            onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            notifyCancel()
        }

        /// 把取消回调推迟到下一个 runloop：避免在 SwiftUI 视图更新过程中改状态。
        func notifyCancel() {
            guard !didNotify else { return }
            didNotify = true
            Task { @MainActor [weak self] in
                self?.onCancel()
            }
        }
    }
}
