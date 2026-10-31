import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// 哪些端点需要 Bearer。登录/刷新/吊销/健康检查不注入 token，
/// 它们的 401 也不能触发单飞刷新（否则递归）。
enum AuthPolicy: Sendable {
    case none
    case bearer
}

struct MultipartBody: Sendable {
    let boundary: String
    let data: Data

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

enum RequestBody: Sendable {
    case none
    case json(Data)
    case multipart(MultipartBody)
}

struct Endpoint: Sendable {
    let method: HTTPMethod
    /// 相对 baseURL 的路径，不带前导 `/`。
    let path: String
    let query: [URLQueryItem]
    let headers: [String: String]
    let body: RequestBody
    let timeout: TimeInterval
    let authPolicy: AuthPolicy

    init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: RequestBody = .none,
        timeout: TimeInterval = 15,
        authPolicy: AuthPolicy = .bearer
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.authPolicy = authPolicy
    }
}

// MARK: - 端点工厂

extension Endpoint {
    static func authToken(email: String, password: String) throws -> Endpoint {
        let data = try JSONEncoder().encode(TokenBody(email: email, password: password))
        return Endpoint(
            method: .post,
            path: "auth/token",
            body: .json(data),
            timeout: 10,
            authPolicy: .none
        )
    }

    static func authRefresh(refreshToken: String) throws -> Endpoint {
        let data = try JSONEncoder().encode(RefreshBody(refreshToken: refreshToken))
        return Endpoint(
            method: .post,
            path: "auth/refresh",
            body: .json(data),
            timeout: 10,
            authPolicy: .none
        )
    }

    static func authRevoke(refreshToken: String) throws -> Endpoint {
        let data = try JSONEncoder().encode(RefreshBody(refreshToken: refreshToken))
        return Endpoint(
            method: .post,
            path: "auth/revoke",
            body: .json(data),
            timeout: 5,
            authPolicy: .none
        )
    }

    static func me() -> Endpoint {
        Endpoint(method: .get, path: "auth/me", timeout: 10, authPolicy: .bearer)
    }

    static func sentences(level: String) -> Endpoint {
        Endpoint(
            method: .get,
            path: "sentences",
            query: [URLQueryItem(name: "level", value: level)],
            timeout: 15,
            authPolicy: .bearer
        )
    }

    static func attempt(
        audioData: Data,
        filename: String,
        mimeType: String,
        sentenceID: String,
        referenceText: String,
        mode: AttemptMode,
        durationMs: Int
    ) -> Endpoint {
        var builder = MultipartFormDataBuilder()
        // 字段顺序固定，便于服务端与抓包对齐（见 architecture.md §4.4）。
        builder.addFile(name: "audio", filename: filename, mimeType: mimeType, data: audioData)
        builder.addField(name: "sentence_id", value: sentenceID)
        builder.addField(name: "reference_text", value: referenceText)
        builder.addField(name: "mode", value: mode.rawValue)
        builder.addField(name: "duration_ms", value: String(durationMs))

        return Endpoint(
            method: .post,
            path: "attempts",
            body: .multipart(builder.finalize()),
            timeout: 60,
            authPolicy: .bearer
        )
    }

    static func tts(text: String, rate: TTSRate, format: TTSFormat) throws -> Endpoint {
        let data = try JSONEncoder().encode(
            TTSBody(text: text, rate: rate.rawValue, format: format.rawValue)
        )
        return Endpoint(
            method: .post,
            path: "tts",
            body: .json(data),
            timeout: 20,
            authPolicy: .bearer
        )
    }

    static func health() -> Endpoint {
        Endpoint(method: .get, path: "health", timeout: 10, authPolicy: .none)
    }

}

private struct TokenBody: Encodable {
    let email: String
    let password: String
}

private struct RefreshBody: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct TTSBody: Encodable {
    let text: String
    let rate: String
    let format: String
}

// MARK: - Multipart

/// 手写 multipart/form-data。M0 单段音频远小于 12MB，用内存 Data 足够；
/// 照片 OCR（M2）再切换成临时文件 + uploadTask。
struct MultipartFormDataBuilder {
    private let boundary = "Boundary-\(UUID().uuidString)"
    private var data = Data()

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append(Data(value.utf8))
        append("\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finalize() -> MultipartBody {
        append("--\(boundary)--\r\n")
        return MultipartBody(boundary: boundary, data: data)
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
