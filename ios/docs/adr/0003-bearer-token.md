# ADR-0003 · 移动端认证：Bearer Token + 单飞刷新（取代 ADR-0001）

- **状态**：Accepted（2026-10-31，用户拍板）
- **取代**：[ADR-0001](0001-cookie-session-vs-bearer-token.md)（Cookie 持久化，已作废）
- **决策者**：项目负责人
- **相关**：`docs/architecture.md` §4.3/§4.7、`docs/open-questions.md` Q1 / B17、仓库共享 [`docs/adr/0002-bearer-token.md`](../../../docs/adr/0002-bearer-token.md)、共享 `docs/backend-contract.md` §1

---

## 背景

后端 Web 端使用 **Cookie 会话**（`POST /api/auth/login` → httpOnly Cookie）。原生客户端如果沿用 Cookie，需要依赖 `HTTPCookieStorage` 的持久化行为，且跨平台（iOS / HarmonyOS）无法保证一致；ADR-0001 曾选择该方案，但被用户否决。

用户决定：**移动端直接上 Bearer Token，Web 端继续用 Cookie（双模式并存，互不影响）**。后端三个 token 端点列为 **P0、阻塞 M0**：

| 端点 | 状态 | 契约 |
| --- | --- | --- |
| `POST /api/auth/token` | **【待后端新增】** | 请求 `{email,password}` → 200 `{access_token, refresh_token, token_type:"Bearer", expires_in:3600, user}`；失败 401 `{error:{code:"bad_request"\|"unauthorized", message}}` |
| `POST /api/auth/refresh` | **【待后端新增】** | 请求 `{refresh_token}` → 200 新的一对 `{access_token, refresh_token, token_type, expires_in}`；**一次性轮换**（旧 refresh 立即失效） |
| `POST /api/auth/revoke` | **【待后端新增】** | 请求 `{refresh_token}` → **204**；重复吊销按成功处理【待确认】 |

所有现有接口同时接受 `Authorization: Bearer <access_token>` 与 Cookie；两套凭据必须解析到同一个 `userId`。`GET /api/auth/me` 在 Bearer 下同样可用。

---

## 决策

**移动端所有业务请求使用 `Authorization: Bearer <access_token>`；token 存 Keychain；网络层做单飞刷新；退出调用 `/revoke` 并清本地。**

具体约定：

1. **有效期**：access **1h**（`expires_in=3600`），refresh **30d**。不实现“永久登录”，refresh 到期即重新登录。
2. **存储**：`access_token` 与 `refresh_token` 只存 **Keychain**，**不写日志、不进 UserDefaults、不进任何明文文件**。
3. **注入**：`APIClient` 为需要鉴权的端点统一注入 `Authorization` 头；登录/刷新/吊销/`/health` 不注入。
4. **单飞刷新**：任意业务请求收到 **401** → 只允许一个刷新任务在跑，其余请求等待同一结果，成功后各自**重放原请求一次**；重放仍 401 则登出。
5. **失败语义**：
   - refresh 被服务端拒绝（401/403，refresh 过期/已吊销/已被轮换）→ **清 token → 跳登录**；
   - refresh 因**网络不可达**失败 → **保留 token**，按离线处理并提示重试（否则 NAS 短暂不可达就会把全家登出）；
   - 业务接口 403（角色无权）→ 不登出，按 `forbidden` 文案处理。
6. **退出**：`POST /api/auth/revoke {refresh_token}` → 本地清 token + 账户缓存 + 跳登录；离线退出时仍清本地，但服务端 refresh 可能仍有效（见 §6）。
7. **切换 base URL**：token 与服务器绑定，切换后**必须清 token 并要求重新登录**。
8. **Web 不变**：Cookie 仍是 Web 的凭据；客户端不读写 Cookie（`httpCookieStorage = nil`、`httpShouldSetCookies = false`），避免两种凭据混用。

---

## 客户端实现

### 1. Keychain 项

| Key（`kSecAttrAccount`） | 内容 | 可访问性 |
| --- | --- | --- |
| `accessToken` | access token 字符串 | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| `refreshToken` | refresh token 字符串 | 同上 |
| `tokenMeta` | 非敏感元数据 JSON：`{expiresAt, baseURLHash}` | 同上（随 token 一起删） |
| `lastUser` | `{email, userId, role}`，仅用于登录页预填与冷启动占位 | `kSecAttrAccessibleAfterFirstUnlock` |

- `service = "top.dreamsearch.english.coach.auth"`；
- `ThisDeviceOnly` 保证备份/迁移到另一台设备时 token 不跟随（换机必须重新登录）；
- 读取失败/解码失败 → 视为“无 token”，走登录，不要崩溃；写失败要 `OSLog` 记录**错误码**（不记录 token 本身）。

### 2. 刷新算法（单飞）

```swift
struct TokenPair: Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

actor TokenRefresher {
    private let store: TokenStore
    private let authAPI: AuthAPI
    private var inFlight: Task<TokenPair, Error>?

    /// `staleAccess` = 刚被 401 拒绝的那个 access token。
    func accessToken(rejecting staleAccess: String) async throws -> String {
        // 1) 其他请求已经刷新成功：直接用新 token，不再发 refresh
        if let current = await store.snapshot(),
           current.accessToken != staleAccess,
           current.expiresAt > Date().addingTimeInterval(30) {
            return current.accessToken
        }
        // 2) 已有刷新在飞：等它（不重复发 refresh，避免“一次性轮换”把新 token 用废）
        if let task = inFlight {
            return try await task.value.accessToken
        }
        // 3) 由本调用发起唯一一次刷新
        let task = Task {
            let pair = try await authAPI.refresh()   // 读取 Keychain 里的 refresh_token
            await store.save(pair)                   // 原子写回两个 token + expiresAt
            return pair
        }
        inFlight = task
        do {
            let pair = try await task.value
            inFlight = nil
            return pair.accessToken
        } catch {
            inFlight = nil
            if error.isCredentialRejection {         // 401/403，不是网络错误
                await store.clear()
            }
            throw error
        }
    }
}
```

要点：

- **必须单飞**：refresh 是**一次性轮换**，并发刷新会让第二个请求拿着已失效的旧 refresh 去换，直接把用户踢下线。
- 等待者拿到新 token 后**重放原请求一次**，用 `retried` 标记防止无限循环；重放仍 401 → 统一登出。
- 刷新任务取消：页面取消导致等待被取消时，**不要取消**共享的 refresh 任务（用 `Task` 不随父任务取消，或引用计数），否则所有等待者一起失败。
- 不主动定时刷新；access 过期由 401 触发即可。可在剩余 <60s 时提前刷新作为优化，但不是必需【客户端自行实现】。

### 3. 请求路径

```
业务请求（带 access）
  ├─ 200 → 正常
  ├─ 401 → TokenRefresher.accessToken(rejecting: used)
  │        ├─ 成功 → 用新 access 重放一次 → 200 / 仍 401 → 登出
  │        └─ 失败（401/403）→ 清 token → 登出
  ├─ 403 → forbidden 文案（不登出）
  └─ 网络错误 → 原样上抛，不触发刷新
```

- 登录/刷新/吊销端点自身 **401 不进入刷新流程**（否则递归）；
- `/auth/me` 401 与业务请求同规则；
- 登出动作要幂等：并发的多个 401 最终只触发一次跳登录（`SessionStore.phase` 已变化则忽略）。

### 4. 冷启动

```
读 Keychain
 ├─ 无 token → 登录页
 ├─ 有 token 且 access 未过期 → GET /auth/me（带 Bearer）
 │     ├─ 200 → 主界面
 │     ├─ 401 → 刷新一次 → 成功则重试 /me；失败则登录页
 │     └─ 网络错误 → 离线外壳（保留 token，联网后重试，不要求重新输密码）
 └─ 有 token 但 access 已过期 → 先 refresh → 成功则 /me；失败按上一条的 401 分支
```

### 5. 不做什么

- ❌ 不把 token 写进 `UserDefaults` / 明文 JSON / 剪贴板；
- ❌ 不在日志、崩溃上报、诊断信息里出现 token（连前缀也不要）；
- ❌ 不做“refresh 失败自动重试 3 次再登出”——refresh 是凭据判断，重试无意义且放大轮换竞争；
- ❌ 不支持多账号同时持有多套 token（切换账号 = 吊销旧 refresh + 清本地）。

### 6. 已知限制（必须如实记录）

- **离线退出无法吊销服务端 refresh**：本地已清，但服务端 refresh 最长仍可用 30 天。可选缓解：把待吊销的 refresh 暂存 Keychain，下次启动联网时补发一次 `/revoke`（【客户端自行实现】，非 M0 必需）。
- **`/revoke` 只吊销 refresh**：已签发的 access 是否立即失效取决于服务端实现（JWT 无状态时最长再活 1h）【待确认】。
- **设备时钟偏差**会影响 `expiresAt` 判断；以服务端 401 为准，本地时间只用于提前量。
- **Keychain 在模拟器/重装后的行为与真机不同**：卸载重装后 Keychain 项可能仍在（取决于系统），不能把它当作“安装标识”。

---

## 备选方案（未采用）

| 方案 | 为什么不用 |
| --- | --- |
| Cookie 持久化（ADR-0001） | 已被用户否决；跨端不一致；无法主动吊销 |
| 只发 access、不刷新（重新登录） | 1h 一次输密码，家庭场景不可接受 |
| 并发 401 各自 refresh | 一次性轮换下必然互相作废，随机掉登录 |
| refresh 存 UserDefaults | 明文凭据，违反安全基线 |
| 长寿命 access（30d） | 泄漏后无法收敛，且无法吊销 |

---

## 后果

**正面**

- 客户端凭据可控：短期 access + 可吊销 refresh；
- 与鸿蒙端同一套认证语义，契约只维护一份；
- 不再依赖 `HTTPCookieStorage` 的持久化细节，重启保持登录的路径可测试（注入 fake `TokenStore` + `URLProtocol`）。

**负面 / 风险**

- 后端三个端点未上线前，M0 无法收尾（**当前最大阻塞**）；
- 刷新竞态是新增的正确性风险，必须用单测覆盖（并发 3 个 401 只发 1 次 refresh）；
- refresh 轮换意味着“重放旧 refresh”会被拒，客户端任何重试逻辑都不能重发 refresh；
- token 泄漏 = 账号被盗，必须配合短 access、Keychain、无日志三条底线。

---

## 验证清单（设计阶段，全部未执行）

| # | 验证项 | 方法 | 记录 |
| --- | --- | --- | --- |
| 1 | 三个端点契约与错误码 | `curl` + 后端样例 | 本文“验证记录” |
| 2 | Keychain 写入/读取/清除 | 真机 + 单测（fake store） | 同上 |
| 3 | 杀进程冷启动保持登录 | 真机 | 同上 |
| 4 | access 过期自动刷新并对用户无感 | 后端临时缩短 TTL 或用 URLProtocol 桩 | 同上 |
| 5 | 并发 401 只 refresh 一次 | `URLProtocol` 桩并发 3 请求 | 同上 |
| 6 | refresh 被拒 → 清 token → 登录页 | 桩返回 401 | 同上 |
| 7 | 网络不可达时不清 token | 飞行模式冷启动 | 同上 |
| 8 | 退出后旧 refresh 再用返回 401 | `curl` | 同上 |

### 验证记录（待填）

| 日期 | 设备/后端版本 | 结论 | 备注 |
| --- | --- | --- | --- |
| — | — | **尚未验证** | token 端点尚在实现中，本文为设计阶段结论 |
