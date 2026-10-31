# ADR-0001 · 会话认证：Cookie 持久化（已被取代）

- **状态**：**Superseded** —— 被 [ADR-0003](0003-bearer-token.md) 取代（2026-10-31）
- **原状态**：Accepted（2026-10-31，暂定，依赖后端确认 `Set-Cookie` 属性）
- **日期**：2026-10-31
- **决策者**：iOS 客户端 → 项目负责人改判（2026-10-31）
- **相关**：`docs/architecture.md` §4.3、`docs/open-questions.md` Q1（已决）、仓库共享决策 [`docs/adr/0002-bearer-token.md`](../../../docs/adr/0002-bearer-token.md)

---

## 一句话结论

**本 ADR 不再有效。** 移动端认证改为 **Bearer Token**（access 1h / refresh 30d、Keychain 存储、网络层单飞刷新、退出吊销），完整决策见 [ADR-0003](0003-bearer-token.md)。保留本文件仅作决策历史，**不得作为实现依据**。

---

## 原决策（历史记录，不再实施）

首版采用「`URLSession` + `HTTPCookieStorage` 持久化 Cookie、零后端改动」，并要求后端给会话 Cookie 补 `Max-Age`；Keychain 只存“上次登录标识”。

当时的理由：后端 Web 端已经在用 httpOnly Cookie；原生客户端让系统托管 Cookie 的接入成本最低；token 端点需要后端改动。

原方案的实施细节（唯一 `URLSession` 的 Cookie 配置、Cookie 生命周期表、`Set-Cookie` 属性风险、把 Cookie 快照进 Keychain 的兜底路径、与 WebView 共享 Cookie 的风险）**已随决策作废并从本文删除**，避免被误当成现行实现。

---

## 为什么被取代

1. **跨端一致性**：鸿蒙原生 HTTP 栈对 Cookie 的自动管理不可靠，两端若走不同认证路径，排障与契约都要维护两套；Bearer 两端同构。
2. **后端已接受改造**：`POST /api/auth/token`、`POST /api/auth/refresh`、`POST /api/auth/revoke` 列为 **P0（阻塞 M0）**，见 `docs/open-questions.md` B17 与共享 `docs/backend-contract.md` §1。
3. **可控的过期与吊销**：access 短期 + refresh 一次性轮换，退出/换机时能真正失效；Cookie 的过期完全由服务端控制，客户端无法主动吊销。
4. **避免二次返工**：现在直接上 token，比“先 Cookie、上线后再迁移”少一次网络层重写；Web 端继续用 Cookie，双模式并存。
5. **产品决策**：用户已拍板（2026-10-31）直接上 Bearer Token，不再讨论 Cookie 方案。

---

## 对现有文档的影响（已落实）

- README、`architecture.md`、`audio.md`、`screens.md`、`roadmap.md`、`open-questions.md` 中所有 `HTTPCookieStorage`、Cookie 持久化、`Set-Cookie`、`Max-Age` 段落已删除或改写为 Bearer Token。
- 原开放问题 **B12（`Set-Cookie` 属性）** 作废，由 **B17（token 端点细节）** 替代；原实测项 **C3（重启后 Cookie 是否保留）** 改为 token 持久化，**C5（SameSite 行为）** 改为单飞刷新验证。
- **Web 端不受影响**：Web 继续使用 Cookie 会话；两套凭据在服务端必须解析到同一个 `userId`。

---

## 验证记录

| 日期 | 结论 | 备注 |
| --- | --- | --- |
| 2026-10-31 | **未实施** | Cookie 方案在编码前被 Bearer Token 决策取代，无实测数据 |
