import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    enum DemoAccount: String, CaseIterable, Identifiable {
        case child
        case parent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .child: return "孩子演示账号（A1）"
            case .parent: return "家长演示账号（B1）"
            }
        }

        // 与后端 `web/src/data/accounts.json` 的种子账号一致。
        // 若 NAS 用 BOOTSTRAP_* 覆盖过，请以实际部署为准（README 已注明）。
        var email: String {
            switch self {
            case .child: return "girl@example.com"
            case .parent: return "dad@example.com"
            }
        }

        var password: String {
            switch self {
            case .child: return "Girl12345!"
            case .parent: return "Dad12345!"
            }
        }
    }

    let app: AppEnvironment

    var email: String
    var password: String
    var baseURLText: String

    private(set) var isSubmitting = false
    private(set) var isTestingConnection = false
    private(set) var errorMessage: String?
    private(set) var errorCanRetry = false
    private(set) var connectionMessage: String?
    private(set) var connectionSucceeded: Bool?

    init(app: AppEnvironment) {
        self.app = app
        self.email = ""
        self.password = ""
        self.baseURLText = app.config.baseURLText
    }

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        isFormValid && !isSubmitting
    }

    var usesInsecureBaseURL: Bool {
        AppConfig.normalize(baseURLText)?.scheme?.lowercased() == "http"
    }

    func useDemoAccount(_ account: DemoAccount) {
        email = account.email
        password = account.password
        if baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURLText = app.demoBaseURL
        }
        errorMessage = nil
        errorCanRetry = false
    }

    func login() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        errorCanRetry = false
        connectionMessage = nil
        defer { isSubmitting = false }

        do {
            try await app.signIn(
                baseURLText: baseURLText,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch let error as APIError {
            errorMessage = message(for: error)
            errorCanRetry = error.canRetry
        } catch {
            errorMessage = "登录失败，请重试"
            errorCanRetry = true
        }
    }

    func testConnection() async {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        connectionMessage = nil
        connectionSucceeded = nil
        defer { isTestingConnection = false }

        do {
            try await app.testConnection(baseURLText: baseURLText)
            connectionMessage = "服务器连上了"
            connectionSucceeded = true
        } catch let error as APIError {
            connectionMessage = error.userMessage(forChild: false)
            connectionSucceeded = false
        } catch {
            connectionMessage = "连不上服务器，请检查地址和网络"
            connectionSucceeded = false
        }
    }

    private func message(for error: APIError) -> String {
        switch error {
        case .unauthorized:
            // 后端登录失败统一返回 401 + code=bad_request，文案是“邮箱或密码不正确”。
            return "邮箱或密码不正确"
        case .server(let code, let message, _):
            switch code {
            case .tooManyRequests, .dailyLimitReached:
                return message ?? error.userMessage(forChild: false)
            case .badRequest:
                return message ?? error.userMessage(forChild: false)
            default:
                return error.userMessage(forChild: false)
            }
        default:
            return error.userMessage(forChild: false)
        }
    }
}
