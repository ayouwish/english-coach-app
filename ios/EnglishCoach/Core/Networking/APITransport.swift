import Foundation
import OSLog

/// 共享的 URLSession 封装：只负责构造请求、发请求、把失败映射成 `APIError`。
/// 不处理认证（Bearer 注入与 401 重放在 `APITransport`）。
final class HTTPClient: Sendable {
    private let session: URLSession
    private let logger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "net")

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        // 移动端凭据只有 Bearer，完全不读写 Cookie，避免两套凭据混用。
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // 录音后要立即评分：宁可快速失败展示离线态，也不要静默挂起。
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func sendData(for endpoint: Endpoint, baseURL: URL, bearerToken: String?) async throws -> Data {
        let request = try Self.makeRequest(endpoint: endpoint, baseURL: baseURL, bearerToken: bearerToken)
        let startedAt = Date()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.decoding(path: endpoint.path)
            }
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logger.debug(
                "\(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public) -> \(http.statusCode) \(elapsedMs)ms"
            )
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(status: http.statusCode, data: data)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw error.code == .cancelled ? APIError.cancelled : APIError.transport(error.code)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(.unknown)
        }
    }

    func send<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        baseURL: URL,
        bearerToken: String?,
        as type: T.Type
    ) async throws -> T {
        let data = try await sendData(for: endpoint, baseURL: baseURL, bearerToken: bearerToken)
        return try Self.decode(data, path: endpoint.path)
    }

    static func decode<T: Decodable & Sendable>(_ data: Data, path: String) throws -> T {
        do {
            let decoder = JSONDecoder()
            // snake_case → camelCase；未知字段默认忽略，后端加字段不会让客户端崩。
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(path: path)
        }
    }

    private static func makeRequest(endpoint: Endpoint, baseURL: URL, bearerToken: String?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }
        var path = components.path
        if !path.hasSuffix("/") {
            path += "/"
        }
        path += endpoint.path
        components.path = path
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let url = components.url else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        switch endpoint.body {
        case .none:
            break
        case .json(let data):
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .multipart(let multipart):
            request.httpBody = multipart.data
            request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func error(status: Int, data: Data) -> APIError {
        if status == 401 {
            return .unauthorized
        }
        if status == 403 {
            return .forbidden
        }

        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let code = ServerErrorCode(rawCode: envelope?.error.code)
        return .server(code: code, message: envelope?.error.message, status: status)
    }
}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String?
        let message: String?
    }

    let error: Body
}

protocol AccessTokenRefreshing: Sendable {
    /// `staleAccessToken` 是刚刚被 401 拒绝的 access token。
    /// 单飞刷新逻辑保证：并发 401 只会发出一次 /auth/refresh。
    func accessToken(rejecting staleAccessToken: String?) async throws -> String
}

/// 业务请求入口：注入 Bearer，401 时单飞刷新并重放一次。
final class APITransport: Sendable {
    let baseURL: URL
    private let client: HTTPClient
    private let tokens: any TokenStoring
    private let refresher: any AccessTokenRefreshing

    init(
        baseURL: URL,
        client: HTTPClient,
        tokens: any TokenStoring,
        refresher: any AccessTokenRefreshing
    ) {
        self.baseURL = baseURL
        self.client = client
        self.tokens = tokens
        self.refresher = refresher
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await sendData(endpoint)
        return try HTTPClient.decode(data, path: endpoint.path)
    }

    func sendData(_ endpoint: Endpoint) async throws -> Data {
        guard endpoint.authPolicy == .bearer else {
            return try await client.sendData(for: endpoint, baseURL: baseURL, bearerToken: nil)
        }

        let token = try await currentAccessToken()
        do {
            return try await client.sendData(for: endpoint, baseURL: baseURL, bearerToken: token)
        } catch let error as APIError {
            guard case .unauthorized = error else { throw error }
            // 只有这一个 401 会触发刷新；重放仍 401 时直接抛 .unauthorized 由上层登出。
            // 刷新被服务端拒绝时 TokenRefresher 会清 Keychain，网络错误则保留 token。
            let refreshed = try await refresher.accessToken(rejecting: token)
            return try await client.sendData(for: endpoint, baseURL: baseURL, bearerToken: refreshed)
        }
    }

    private func currentAccessToken() async throws -> String {
        if let stored = await tokens.load(), !stored.accessToken.isEmpty {
            return stored.accessToken
        }
        // access 不在但 refresh 还在：先刷新再发业务请求。
        return try await refresher.accessToken(rejecting: nil)
    }
}
