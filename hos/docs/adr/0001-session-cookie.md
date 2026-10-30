# ADR-0001: 移动端会话认证采用 Cookie（方案 A）

- 状态：**已接受（2026-10-31）**
- 决策人：客户端设计（待后端/产品确认）
- 相关：open-questions Q4

## 背景

服务端现有认证是 Cookie 会话：

- 登录成功后下发 `ec_session`（httpOnly、sameSite=lax、30 天、HTTPS 下可选 Secure）；
- 所有 API 通过 Cookie 识别用户；
- 没有 Bearer Token、刷新令牌、注销全部会话等接口。

HarmonyOS 客户端有两个方案：

- A：`@ohos.net.http` 手动管理 Cookie（解析 `HttpResponse.cookies`，持久化到 Asset Store Kit，每请求带 `Cookie` 头）。
- B：后端新增 Bearer Token（签发/刷新/吊销），客户端改用 `Authorization`。

## 选项对比

| 维度 | A. Cookie | B. Bearer Token |
|---|---|---|
| 后端改动 | 无 | 新增端点 + 双认证中间件 + 迁移 |
| 客户端复杂度 | 中（解析/持久化/401 处理） | 低（标准头） |
| 过期/刷新 | 固定 30 天，过期重登 | 可短 access + refresh |
| 吊销 | 删 sessions 行；无 logout-all | 可精细吊销 |
| 与 Web 共用 | 是 | 需并行两套 |
| 上架影响 | 无 | 无 |

## 决策

**采用 A**，理由：

1. 后端零改动，M0 可立即联调，符合“后端已完成、不要改后端”的约束。
2. Cookie 会话与 Web 共享同一套权限/过期/角色逻辑，减少行为分叉。
3. API 12 的 `http` 没有 `enableAutoCookie`（该 API 为 26），但 `HttpResponse.cookies`（API 8+）足以手动解析；实现可控、可测试。
4. 原生客户端没有浏览器 CSRF 面，`sameSite=lax` 足够。

## 后果

**正面**

- 不阻塞 M0；不需要后端排期。
- token 可存 Asset Store Kit，满足敏感信息加密存储。
- Web/App 同一会话模型，家长在网页与 App 看到一致权限。

**负面/风险**

- 需要自己处理 Cookie 解析、过期、401、登出清理；解析失败要有兜底（同时读 `set-cookie`）。
- 没有 refresh token；30 天后必须重新登录。
- 没有 logout-all；设备丢失时无法远程踢下线（open-questions Q7）。
- 若未来要短会话/多端精细吊销，仍需 B。

## 验证方式

- 登录 → 杀进程 → 重开：仍登录（30 天内）。
- 401 → 清 token → 回登录页。
- token 不出现在 Preferences/日志；Asset 中可读。
- 登出后旧 Cookie 再请求返回 401。

## 何时重新评估

- 需要“注销全部设备”/短会话/多客户端精细权限；
- 应用市场或安全评审要求 Token；
- 服务端认证中间件重构。

届时新开 ADR，不直接改本文件结论。
