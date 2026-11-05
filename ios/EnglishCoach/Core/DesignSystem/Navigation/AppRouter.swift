import Observation

/// 路由栈封装（契约 §3.14）。
///
/// - 单例由 `AppEnvironment` 创建并注入 Environment（`@Observable` 直接作为可观察对象）；
/// - 页面只调用 `push/pop/popToRoot`，不要直接改 `path`（保留可写是为 `NavigationStack(path:)` 绑定）；
/// - 全部方法 MainActor（UI 状态）。
@MainActor
@Observable
final class AppRouter {
    /// `NavigationStack` 的路径。可直接绑定（`Binding(router.path)` 或 `Bindable`）。
    var path: [AppRoute]

    init(path: [AppRoute] = []) {
        self.path = path
    }

    /// 压入一个路由。
    func push(_ route: AppRoute) {
        path.append(route)
    }

    /// 返回上一页（栈空时无操作）。
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// 回到根（Tab 内首页）。
    func popToRoot() {
        path.removeAll()
    }

    /// 重置为指定路径（登录/登出切换时用）。
    func reset(to routes: [AppRoute]) {
        path = routes
    }

    // MARK: - 只读便利

    /// 是否可返回。
    var canPop: Bool {
        !path.isEmpty
    }

    /// 栈顶路由。
    var top: AppRoute? {
        path.last
    }
}
