# ADR-0001 · 移动端认证：先用 Cookie 会话，后续再上 Bearer Token

- 状态：**已被 [ADR-0002](0002-bearer-token.md) 取代**（2026-10-31，用户决定直接上 Bearer Token）
- 原状态：已接受（2026-10-31）
- 决策人：项目负责人
- 影响范围：iOS、HarmonyOS 客户端 + 后端（第二版）

## 背景

后端现状（`english-coach` web）：

- `POST /api/auth/login` 下发 **httpOnly Cookie** 会话，`sameSite=lax`，HTTPS 部署时 `secure`
- 所有接口靠 Cookie 识别用户；`GET /api/auth/me` 返回当前用户
- 无 Token 机制

原生客户端的两种选择：

| | A. Cookie 持久化 | B. Bearer Token |
|---|---|---|
| 后端改动 | **无** | 需新增 `/api/auth/token`、`/auth/refresh`、双模式身份解析 |
| 客户端实现 | 依赖系统 HTTP 栈的 Cookie 存储 | 标准 Authorization 头 + Keychain/Asset Store |
| 多设备/吊销 | 较弱（服务端 `sessions` 表可清）| 强（refresh 轮换、可吊销）|
| 平台风险 | iOS 稳定；**鸿蒙 `request.agent` 的 Cookie 行为需真机验证** | 两端一致，可控 |
| 首版落地速度 | **快**（零后端改动）| 慢（后端 + 契约 + 测试）|

## 决策

**首版（M0–M1）采用 A：Cookie 会话持久化。**

- iOS：`URLSessionConfiguration.default.httpCookieStorage` + `HTTPCookieStorage.shared`，登录后立即持久化
- 鸿蒙：优先 `@ohos.net.http` 的 `request.agent`（自带 Cookie 管理），若真机不可用则退回手工解析 `Set-Cookie` 并持久化到 `@ohos.security.asset`
- 401 → 清会话、跳登录

**第二版（M2 前后）迁移到 B：Bearer Token**，按 `docs/backend-contract.md` §1 实施；服务端同时支持 Cookie 与 Bearer，Web 端不受影响。

## 理由

1. 首版目标是**尽快在真机上跑通主链路**（登录→跟读→连读→对话→故事），Token 不是阻塞项
2. Cookie 方案零后端改动，减少跨仓库协同（后端仓库当前正忙于语音/故事功能）
3. 但 Cookie 在**鸿蒙原生 HTTP 栈**上的持久化存在不确定性——所以把它列为**风险**，用 M0 的真机验证做决策点：若两周内无法稳定，提前上 Token
4. 长期看 Token 更适合多设备、推送与未来可能的公网访问

## 后果

- ✅ 首版可立刻开工，不需要等后端
- ⚠️ 客户端网络层需**抽象出 `SessionStore` 协议/接口**，使 Cookie → Token 的切换只改一层实现（这是本 ADR 的硬要求）
- ⚠️ 多设备同时登录的首版行为：同一 Cookie 会话可在多设备复制（不理想但家庭场景可接受）
- 📌 迁移时需一次性登出所有客户端（Token 上线后旧 Cookie 会话自然过期）

## 验证点（M0 必须做）

| 平台 | 验证内容 |
|---|---|
| iOS | 杀进程重启后仍登录；卸载重装后需重新登录（预期）|
| 鸿蒙 | 同上；并验证 `request.agent` 或手工 Cookie 持久化在真机（HarmonyOS NEXT）上可用 |

若鸿蒙端 2 周内无法稳定持久化 → 触发 ADR 复审，直接上 Token。
