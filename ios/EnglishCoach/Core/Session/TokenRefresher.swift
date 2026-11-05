import Foundation

/// 单飞刷新（single-flight）。
///
/// 为什么必须是单飞：`/auth/refresh` 是**一次性轮换**——旧 refresh 用一次就失效。
/// 如果 3 个并发 401 各自去 refresh，后两个会拿着已失效的 refresh 去换，直接把用户踢下线。
/// 因此 actor 内只保存一个在飞 `Task`，其余调用等待同一个结果。
actor TokenRefresher: AccessTokenRefreshing {
    private let client: HTTPClient
    private let store: any TokenStoring
    private let baseURL: URL
    private var inFlight: Task<StoredTokens, Error>?

    init(client: HTTPClient, store: any TokenStoring, baseURL: URL) {
        self.client = client
        self.store = store
        self.baseURL = baseURL
    }

    func accessToken(rejecting staleAccessToken: String?) async throws -> String {
        // 1) 别的请求已经刷新成功：直接用新 token，不再发 refresh。
        if let current = await store.load(),
           !current.accessToken.isEmpty,
           current.accessToken != staleAccessToken,
           current.hasUsableAccessToken() {
            return current.accessToken
        }

        // 2) 已有刷新在飞：等它，不重复发 refresh。
        if let existing = inFlight {
            let tokens = try await existing.value
            return tokens.accessToken
        }

        // 3) 由本调用发起唯一一次刷新。
        let store = self.store
        let client = self.client
        let baseURL = self.baseURL
        let task = Task<StoredTokens, Error> {
            guard let current = await store.load(), !current.refreshToken.isEmpty else {
                throw APIError.unauthorized
            }

            let endpoint = try Endpoint.authRefresh(refreshToken: current.refreshToken)
            let response = try await client.send(
                endpoint,
                baseURL: baseURL,
                bearerToken: nil,
                as: AuthTokenDTO.self
            )

            guard let access = response.accessToken, !access.isEmpty else {
                throw APIError.unauthorized
            }
            var refresh = current.refreshToken
            if let rotated = response.refreshToken, !rotated.isEmpty {
                refresh = rotated
            }
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
            let stored = StoredTokens(
                accessToken: access,
                refreshToken: refresh,
                expiresAt: expiresAt,
                baseURL: baseURL.absoluteString
            )

            do {
                try await store.save(stored)
            } catch {
                // refresh 已经轮换成功但本地写失败：旧 refresh 已失效，继续用旧值只会反复 401。
                await store.clear()
                throw error
            }
            return stored
        }
        inFlight = task

        do {
            let stored = try await task.value
            inFlight = nil
            return stored.accessToken
        } catch {
            inFlight = nil
            if let apiError = error as? APIError {
                switch apiError {
                case .unauthorized, .forbidden:
                    // 服务端明确拒绝 refresh（过期/被吊销/已被轮换）才清 token；
                    // 纯网络错误保留 token，按离线处理，避免 NAS 短暂不可达就把全家登出。
                    await store.clear()
                default:
                    break
                }
            }
            throw error
        }
    }
}
