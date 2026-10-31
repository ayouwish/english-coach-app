# ADR-0002：鸿蒙客户端认证采用 Bearer Token（取代 ADR-0001）

- 状态：**已接受**（2026-10-31）
- 取代：[ADR-0001](0001-session-cookie.md)（Cookie 方案，已废弃）
- 决策人：项目负责人
- 相关：open-questions Q4、Q7
- 影响范围：HarmonyOS 客户端 + 后端 web（**需新增接口，P0**）；Web 端认证方式不变

## 背景

后端现有认证是 Web 用的 Cookie 会话。用户已拍板：**移动端直接上 Bearer Token，不再先做 Cookie 再迁移**。后端将新增三个 P0 端点，且所有现有接口同时接受 Bearer 与 Cookie（双模式并存，Web 不受影响）：

```text
POST /api/auth/token    {email,password}
  → 200 {access_token, refresh_token, token_type:"Bearer", expires_in:3600, user}
POST /api/auth/refresh  {refresh_token}
  → 200 {access_token, refresh_token, expires_in}     # 一次性轮换，旧 refresh 立即失效
POST /api/auth/revoke   {refresh_token}
  → 204
```

## 决策

**鸿蒙客户端全部使用 Bearer Token；access 1h、refresh 30d；两个 token 存 Asset Store Kit。**

- 请求头：`Authorization: Bearer <access_token>`；不再读取/保存/发送 Cookie。
- 存储：`@ohos.security.asset`（Kit 聚合导入 `@kit.AssetStoreKit`），别名 `ec_access_token` / `ec_refresh_token`；过期时间戳放 Preferences（非敏感）。
- 刷新：`commons/net` 内**单飞刷新**——并发 401 只发一次 `/auth/refresh`，其余等待同一个 Promise 后重放；每个请求最多重放一次。
- 失败语义：
  - refresh 返回 401/400（失效/被吊销/被轮换）→ 清两个 token → 跳登录；
  - refresh 网络错误/5xx → **不清 token**，让用户重试；
  - 重放仍 401 → 清 token，只跳一次登录。
- 退出：`POST /auth/revoke {refresh_token}` → 无论成功失败都清本地 token、页面缓存、`cacheDir` 音频。
- 不把 refresh 放在 URL/query、不写日志、不进 Preferences、不进备份、不写 `AppStorage` 持久化。
- 客户端不解析 token 内容；access 用 JWT 还是不透明短 token、refresh 服务端如何存哈希、`/auth/revoke` 是否要求 access，均由后端实现文档冻结【待后端确认】。

## 为什么不继续 Cookie

| 维度 | Cookie 会话 | Bearer Token（现行） |
|---|---|---|
| 原生客户端可控性 | 依赖系统 HTTP 栈的 Cookie 行为，版本差异大 | 标准请求头，行为确定、可单测 |
| 过期/刷新 | 固定会话期，过期重登 | access 短、refresh 长，可轮换 |
| 吊销 | 粒度粗，通常只能删整条会话 | 可按 refresh token 吊销 |
| 多端 | 共用会话，难区分设备 | 每设备独立 refresh |
| 后端改动 | 无 | 新增三个端点 + 双模式中间件（**已排 P0**） |
| Web 影响 | 无 | 无（Web 继续 Cookie） |

补充复核（2026-10-31）：API 20 下 `@ohos.net.http` 的 `enableAutoCookie` 仍标注 `@since 26.0.0`（以本机 SDK 的 d.ts 为准【待确认】）。但本方案不依赖 Cookie 自动管理，该 API 的可用性**不影响**决策。

## 后果

**正面**

- 认证行为确定，客户端可对 401/刷新/吊销写稳定单测。
- 可做 refresh 轮换与按设备吊销，为后续“注销全部设备”留出接口形态。
- 与 iOS 侧（Keychain + 同一套 Token 契约）行为一致。
- 客户端不再处理任何 Cookie 字段。

**负面/风险**

- **阻塞 M0**：三个端点未落地前，客户端只能用 Fake 联调。
- refresh 一次性轮换：若“服务端已轮换、客户端还没保存”时进程被杀，下次启动会刷新失败并回登录页；按可接受失败处理，不重试旧 refresh。
- 仍没有 logout-all：`/auth/revoke` 只吊销当前 refresh；设备丢失时其他设备仍有效（open-questions Q7）。
- 修改密码不会自动吊销 refresh；需后端补策略。
- token 泄漏等同于账号被盗；靠短 access + 轮换 + 吊销降低影响。

## 实现约束（客户端）

1. `/auth/token`、`/auth/refresh`、`/auth/revoke`、`/health` 一律 `auth:false`，不参与 401 自动刷新，避免递归。
2. 刷新成功后**先原子保存新 pair，再重放原请求**；保存失败按“登录失败”处理，继续用旧 token 会产生不可预期行为。
3. 重放只允许一次；不要写成“401 → 刷新 → 401 → 再刷新”的循环。
4. 单飞锁的等待者只等待结果，不重复发 `/auth/refresh`。
5. UI 不感知 refresh；只有最终失败才发一次全局“需要重新登录”事件。
6. 日志只记录 `requestId/method/path/status/code/elapsedMs`，不记录 Authorization 头或 token 片段。

## 验证方式（M0）

- [ ] `/auth/token` 登录成功；access/refresh 写入 Asset，Preferences/日志中搜不到 token。
- [ ] 杀进程重开：access 过期时自动 refresh，仍停留在已登录状态。
- [ ] 并发 3 个请求同时 401：只发 1 次 refresh，3 个请求都重放成功。
- [ ] refresh 返回 401：清 token，只跳一次登录页。
- [ ] refresh 断网：token 保留，提示重试；恢复网络后能继续。
- [ ] 退出登录：调用 `/auth/revoke`，本地两个 token 都删除；用旧 refresh 再刷新返回 401。
- [ ] 儿童/家长账号登录后，`/auth/me` 的 role 与权限判断一致。

## 何时重新评估

- 后端无法在 M0 前提供 Token 端点（则需临时降级方案，另开 ADR）；
- 需要“注销全部设备”、设备管理、推送绑定等更细的设备级能力；
- 安全评审要求改用短期不透明 token 或其他凭据形态。
