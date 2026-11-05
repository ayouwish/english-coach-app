import SwiftUI

/// App 入口（契约 §3.15）：只创建**唯一**的组合根并交给 `AppRoot`。
///
/// 依赖注入约定：
/// - `AppEnvironment` 通过 `.environment(_:)` 注入（全局唯一，App 层可见）；
/// - `SessionStore` / `AppRouter` / `\.roleCapabilities` 由 `AppRoot` 在页面子树注入，
///   Features 只能用这三种全局环境值（契约 §3.15 约定 2）。
@main
struct EnglishCoachApp: App {
    @State private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(appEnvironment)
                .preferredColorScheme(.light)
        }
    }
}
