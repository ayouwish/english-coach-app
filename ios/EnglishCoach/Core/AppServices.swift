import Foundation

/// 一组与 baseURL 绑定的业务 Service（契约 §3.15）。
///
/// 为什么定义在 Core：Features 的根页面通过构造参数接收本类型
/// （`PracticeView(services: AppServices, audio: AudioCoordinator)`），
/// 但不能反向依赖 App 层。登录后才可用；换服务器必须重建（token 与服务器绑定）。
///
/// 由 `AppEnvironment.configure(baseURL:)` 装配：8 个 Service 共用同一个 `APITransport`
/// （同一个 `HTTPClient`/`URLSession`、同一个单飞 `TokenRefresher`）。
@MainActor
struct AppServices {
    let practice: PracticeService
    let flow: FlowService
    let chat: ChatService
    let story: StoryService
    let stats: StatsService
    let account: AccountService
    let dictionary: DictionaryService
    let media: MediaService
}
