# ADR-0001 · 会话认证：Cookie 持久化（方案 A）而非 Bearer Token（方案 B）

- **状态**：Accepted（暂定，依赖后端确认 `Set-Cookie` 属性）
- **日期**：2026-10-31
- **决策者**：iOS 客户端（待产品/后端确认 Q1、B12）
- **相关**：`docs/architecture.md` §4.3、`docs/open-questions.md` Q1/B12、`docs/audio.md`（无关）

---

## 背景

后端是 Next.js（`web`），认证方式是**服务端 Cookie 会话**：

- `POST /auth/login` 成功后在响应头 `Set-Cookie` 写入会话 Cookie；
- 属性为 `httpOnly`，`sameSite=lax`，`Secure` 可选；
- 之后所有业务请求依赖浏览器/客户端自动回传该 Cookie；
- 没有 Bearer Token、没有 refresh token、没有公开的 token 端点。

iOS 端需要回答三个问题：

1. 用什么机制保存并回传会话？
2. Keychain 里到底存什么？
3. 是否需要推动后端加 Token？

### 约束

- **后端已完成、原则上不改**（除极小的 Cookie 属性调整）。
- App 只在家庭局域网使用，单用户单设备为主，偶有"一台 iPad 多个孩子"的场景。
- 客户端零第三方依赖。
- 必须能处理：App 重启、长时间不用、会话过期、切换服务器地址。

### 关键未知（决定本 ADR 是否成立）

会话 Cookie 是否带 `Max-Age`/`Expires`（B12）。若是**会话 Cookie**（浏览器关闭即失效的那类），`URLSession` 只持久化"持久 Cookie"，App 重启后会丢失，导致每次打开都要登录。

---

## 决策

**采用方案 A：`URLSession` + `HTTPCookieStorage` 持久化 Cookie，零后端改动（除为 Cookie 补 `Max-Age`）。**

并且：

1. 全 App **只创建一个** `URLSession`，配置为 `URLSessionConfiguration.default` + `httpCookieStorage = .shared` + `httpCookieAcceptPolicy = .always` + `httpShouldSetCookies = true`。
2. **Keychain 不存 Cookie、不存密码**；只存"上次登录标识"用于登录页预填与离线占位。
3. 会话有效性**唯一判据**是 `GET /auth/me` 返回 200；任何 401 立即清理并回登录页。
4. 后端需补一个最小改动：会话 Cookie 增加 `Max-Age`（建议 30 天），使方案 A 在重启后仍然成立。
5. 方案 B（Bearer + refresh）**不在本期实施**，作为"当出现多端/跨域/第三方调用需求时"的演进路径记录在本文末尾。

---

## 方案 A 的实现细节

### 1. 唯一 URLSession

```swift
enum HTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 90
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()
}
```

为什么必须单例：
- Cookie 存储虽在 `HTTPCookieStorage.shared`，但**每次新建 `URLSession` 都会复制一份配置**；如果不同模块各建一个 session 且配置不一致，会出现"登录成功但某些请求不带 Cookie"的幽灵 bug。
- `URLRequest` 的 `httpShouldHandleCookies` 默认 true，但可通过 per-request 关闭；团队约定**禁止**在请求层改动 Cookie 行为。

### 2. Cookie 生命周期

| 事件 | 动作 |
| --- | --- |
| 登录成功 | 无需手动处理，系统自动写入 `Set-Cookie` |
| 业务请求 | 系统自动附加（含 `httpOnly` Cookie） |
| 401 | `SessionStore.handleUnauthorized()`：删 Cookie → 清账户缓存 → 回登录页 |
| 主动退出 | `POST /auth/logout` → 删除该 baseURL 域下所有 Cookie → 清缓存 |
| 切换 baseURL | 旧域 Cookie 不删（保留以便切回）；但**必须**要求重新登录（域不同，Cookie 不通用） |
| App 启动 | `GET /auth/me`；失败即视为未登录 |

删除 Cookie 的实现要点：只删当前 baseURL 对应域，**不要**用 `removeCookies(since: .distantPast)` 全域清空（会误伤同 App 内其他服务，也掩盖问题）。

### 3. Keychain 存什么（明确清单）

| Key（`kSecAttrAccount`） | 内容 | 为什么放 Keychain | 敏感度 |
| --- | --- | --- | --- |
| `lastUser` | `{email, userId, role, baseURLHost}`（JSON） | 登录页预填邮箱、冷启动占位、切换账号列表 | 低（无凭据） |
| `installationId` | 随机 UUID（首次启动生成） | 未来设备标识/日志关联；本期只用于诊断信息 | 低 |

明确**不存**：

- ❌ 密码（任何形式，包括"记住密码"）；
- ❌ 完整 Cookie 字符串（避免把 `httpOnly` 会话降级成可被读取的明文凭据）；
- ❌ 音频、评测结果、孩子姓名等个人数据（走普通文件，退出登录即清）。

存放属性：`kSecClassGenericPassword`、`kSecAttrService = "top.dreamsearch.englishcoach.session"`、`kSecAttrAccessibleAfterFirstUnlock`（后台播放/冷启动可读，且设备锁定时不可读）。

### 4. 与 WebView 的关系

本期没有内嵌 WebView。若未来加入（如帮助页），共享 `HTTPCookieStorage.shared` 会让 WebView 与原生请求共用会话——这既是便利也是风险（XSS 可拿到会话），届时需要重新评估。

### 5. `sameSite=lax` 与 `Secure` 的影响

- `sameSite=lax` 是浏览器跨站策略；`URLSession` 不实现浏览器的 SameSite 判定（**【待实测 C5】**）。若实测发现 Cookie 未被回传，优先检查 `Secure` 与域匹配，而不是 SameSite。
- `Secure` 要求 https。**若用户在设置里填了 `http://192.168.x.x:3000/api`，登录会表现为"200 但随后 401"**。因此：
  - 默认且推荐 https；
  - 允许 http 仅用于排障，且在设置页明确警告"可能无法保持登录"。

### 6. 会话 Cookie 的兜底（仅在后端不改时启用）

若后端短期无法加 `Max-Age`，可选兜底：登录成功时把 Cookie 序列化进 Keychain（`HTTPCookie` → `properties` → JSON），冷启动时反序列化并 `setCookie` 回 `HTTPCookieStorage`。

**不推荐作为长期方案**，原因：
- 把 `httpOnly` 会话变成"客户端可长期持有的凭据"，等于自建 Token 但更不安全；
- Cookie 的 `expiresDate` 若本就为空，回写后语义混乱；
- 增加了一个可能静默失效的路径（域/路径属性需精确还原）。

采用兜底必须在 `docs/architecture.md` 记录，并在后端支持后**删除**该代码路径。

---

## 方案 B（Bearer + Refresh）为什么现在不做

| 维度 | 方案 A（Cookie） | 方案 B（Bearer） |
| --- | --- | --- |
| 后端改动 | 仅 Cookie 属性 | 新增登录发 token、refresh 端点、鉴权中间件、撤销机制、迁移现有 Cookie 逻辑 |
| 客户端复杂度 | 低（系统托管） | 中（存 Keychain、刷新竞态、并发请求排队） |
| 多端/第三方 | 弱 | 强 |
| 移动端体验 | 依赖 Cookie 持久化属性 | 可控的过期与刷新 |
| 安全面 | `httpOnly` 降低 XSS 窃取风险 | token 在客户端，需自行防护 |
| 本期需求匹配 | ✅ 单家庭、单端为主 | ❌ 过度设计 |

结论：**当前收益不足以抵消后端改动与刷新逻辑的复杂度**。Cookie 方案在"家庭内网、自家 App"场景下是合理选择。

### 演进路径（当触发条件出现时）

1. 后端新增 `POST /auth/token`（返回 `access_token` + `refresh_token`），保留 Cookie 端点兼容；
2. 客户端 `AuthStore` 增加 token 分支，`APIClient` 统一注入 `Authorization: Bearer`；
3. 401 + `token_expired` → 单飞刷新（一个任务刷新，其余等待），失败才登出；
4. 迁移期双写：Cookie 仍由系统保存，token 优先；
5. 迁移完成后删除 Cookie 依赖。

触发条件（任一）：
- 出现 Web 之外的第三个客户端（如 HarmonyOS/桌面），需要统一鉴权；
- 需要公网访问（NAS 暴露到公网时必须上 token + 短期过期）；
- 需要"家长在办公室看孩子数据"这类跨网络场景；
- 会话时长需求超过 Cookie 的合理 `Max-Age`。

---

## 后果

**正面**
- 零后端改动（理想情况下）即可完成登录与持久化；
- 不需要在客户端处理 token 刷新竞态；
- 与 Web 端的会话模型一致，排障时可以用同一套 curl 验证。

**负面 / 风险**
- 若后端不补 `Max-Age`，重启掉登录（**本 ADR 的核心前提**）；
- `httpOnly` Cookie 的过期时间由服务端控制，客户端无法主动延长；
- 切换服务器地址必然重新登录；
- 无"刷新令牌"概念，长期不用后只能重新登录（家庭场景可接受）。

**必须验证的事项（未验证前不得宣称已解决）**

| # | 验证项 | 方法 | 记录位置 |
| --- | --- | --- | --- |
| 1 | `Set-Cookie` 是否带 `Max-Age`/`Expires` | `curl -i` 登录接口 | 本文"验证记录" |
| 2 | 杀进程冷启动后是否保持登录 | 真机 | 同上 |
| 3 | 切换 http 地址时是否必然 401 | 真机 | 同上 |
| 4 | 登出后服务端会话是否真的失效 | curl 复用旧 Cookie 请求 `/auth/me` | 同上 |

### 验证记录（待填）

| 日期 | 设备/系统 | 结论 | 备注 |
| --- | --- | --- | --- |
| — | — | **尚未验证** | 本文档为设计阶段，未执行上述验证 |

---

## 相关决策

- 最低 iOS 版本：ADR-0002（决定 `@Observable`，不影响认证）。
- 若 Q1 最终选择"先上 Bearer"，本 ADR 状态改为 `Superseded`，并新建 `0003-bearer-token.md`。
