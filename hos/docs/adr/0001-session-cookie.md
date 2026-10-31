# ADR-0001：移动端会话认证曾采用 Cookie（已被取代）

- 状态：**已被 [ADR-0002](0002-bearer-token.md) 取代**（2026-10-31，用户拍板直接上 Bearer Token）
- 原状态：已接受（2026-10-31）
- 决策人：项目负责人
- 相关：open-questions Q4

> 本文件仅作为历史记录保留。**不要按本文件实现认证**；现行方案见 [ADR-0002](0002-bearer-token.md)。

## 当时的背景

服务端最初只为 Web 提供 Cookie 会话：登录成功后下发会话 Cookie，所有 API 通过 Cookie 识别用户；没有 Bearer Token、刷新令牌或吊销接口。移动端当时有两个选项：

- A：复用 Cookie 会话（后端零改动，最快联调）；
- B：后端新增 Bearer Token（签发/刷新/吊销），客户端改用 `Authorization`。

## 原决策

**采用 A：复用 Cookie 会话**。理由是后端零改动、M0 可立即联调，并先用 `SessionStore` 抽象把认证收敛在一层，避免以后迁移时改遍页面。

## 为什么被取代

用户随后明确要求**直接上 Bearer Token**，不再走 Cookie：

1. 原生客户端对 Cookie 的自动管理不可靠，自己维护会话状态容易出错；
2. refresh 轮换、按设备吊销、多端登录都更适合 Token；
3. 现在直接做 Token，比“先 Cookie 再迁移”少一次网络层返工；
4. 后端已把 `/auth/token`、`/auth/refresh`、`/auth/revoke` 列为 **P0**，与 M0 同步落地。

## 现行方案

- 移动端：Bearer Token（access 1h / refresh 30d，一次性轮换，单飞刷新），token 存 Asset Store Kit；
- Web：继续 Cookie，后端双模式并存，两套身份解析落到同一个 `userId`；
- 细节、失败语义与验证项见 [ADR-0002](0002-bearer-token.md)。

## 遗留影响

- 旧的 Web Cookie 会话按服务端既有策略自然过期，客户端不再读取/保存/发送 Cookie。
- 若未来出现“必须回到 Cookie”的新约束，应新开 ADR，不直接修改本文件结论。
