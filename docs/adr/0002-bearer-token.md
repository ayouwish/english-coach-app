# ADR-0002 · 认证采用 Bearer Token（取代 ADR-0001 的 Cookie 方案）

- 状态：**已接受**（2026-10-31）
- 取代：[ADR-0001](0001-auth-strategy.md)（Cookie 先行）
- 决策人：项目负责人
- 影响范围：iOS、HarmonyOS 客户端 + 后端（`english-coach` web）**需新增接口**

## 背景

ADR-0001 曾决定"首版用 Cookie 会话、二版再上 Token"，理由是零后端改动、落地快。
但用户明确要求 **直接上 Bearer Token**，理由充分：

- 原生客户端（尤其鸿蒙 API 20）对 Cookie 的自动管理不可靠，手写 `Set-Cookie` 解析易错
- 多设备登录、会话吊销、未来推送/公网访问都更需要 Token
- 现在改，比"先 Cookie 再迁移"少一次返工（客户端网络层不用写两套）

## 决策

**移动端全部使用 Bearer Token；Web 端继续用 Cookie（双模式并存）。**

```
POST /api/auth/token    {email, password}
  → 200 {access_token, refresh_token, expires_in, user:{...}}
POST /api/auth/refresh  {refresh_token}
  → 200 {access_token, refresh_token, expires_in}     # 轮换
POST /api/auth/revoke   {refresh_token} → 204
```
- `access_token`：短期（默认 1h），JWT（HS256）或不可猜的随机 token（服务端存哈希），两种实现均可，需在实现文档里写明选型
- `refresh_token`：长期（默认 30d），**一次性轮换**（用旧换新，旧的立即失效），服务端可吊销
- 所有现有接口同时接受 `Authorization: Bearer <access_token>` 与 Cookie（Web 不受影响）
- 401 语义：access 过期 → 客户端 refresh 一次 → 仍失败则跳登录

## 客户端要点

- `access_token` 与 `refresh_token` 存 **Keychain（iOS）/ Asset Store Kit（鸿蒙）**，不写日志、不进 UserDefaults/preferences 明文
- 网络层做**单飞刷新**（并发请求同时 401 时，只发一次 refresh，其余等待结果重放）
- 退出登录 = 调 `/revoke` + 清本地 token

## 后果

- ✅ 两端行为一致、可吊销、可多设备
- ⚠️ 后端必须先实现（阻塞 M0），见 `docs/backend-contract.md` §1
- ⚠️ Web 端与移动端是两套凭据路径，**必须共用同一个 userId 解析**，避免出现"Web 能看到、App 看不到"的权限分叉
- 📌 安全：Token 泄漏 = 账号被盗；因此 access 短、refresh 轮换、服务端记 `sessions` 便于吊销

## 验证点（M0）

| 平台 | 验证内容 |
|---|---|
| 后端 | token/refresh/revoke 三接口 + 双模式中间件 + 单测；过期/吊销/重放行为 |
| iOS | Keychain 存取、杀掉重开仍登录、单飞刷新、退出清 token |
| 鸿蒙 | Asset Store 存取、同上 |
