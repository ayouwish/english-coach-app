# 移动端所需的【待后端新增】接口

> 现状：后端 `english-coach` 已提供 Web 端所需的全部接口（`docs/api-contract.md`）。
> 原生客户端**首版可以完全复用 Cookie 会话 + 现有接口**（见 ADR-0001）。
> 本文列出**第二版**建议新增/调整的接口，全部需在 `english-coach` 仓库实现，并升契约版本。

---

## 1. Bearer Token 认证【待后端新增】

**动机**：原生 HTTP 栈的 Cookie 持久化在两端行为不一致（尤其鸿蒙 `request.agent`），且未来多设备/推送需要更清晰的会话管理。

```
POST /api/auth/token
  body {email, password}
  200 {access_token, refresh_token, expires_in: 3600, user:{id,email,displayName,role,cefrLevel}}
  401 {error:{code:"bad_request", message:"邮箱或密码不正确"}}

POST /api/auth/refresh
  body {refresh_token}
  200 {access_token, expires_in, refresh_token}   # 轮换
  401 → 客户端清会话跳登录

POST /api/auth/revoke
  body {refresh_token} → 204
```
- 所有现有接口同时接受 `Authorization: Bearer <access_token>` 与 Cookie（**双模式并存**，Web 不受影响）
- access token 有效期 1h；refresh 30 天、可轮换、服务端可吊销
- 客户端存 Keychain / Asset Store

**兼容要求**：Web 端继续用 Cookie；两套身份解析必须落到同一个 `userId`。

## 2. 版本与兼容性【待后端新增】

```
GET /api/version
  200 {web: "0.1.0", contract: "1.10", min_client: {"ios": "0.1.0", "hos": "0.1.0"}, features: {...}}
```
- 客户端启动校验 `contract`，过低/过高时提示更新
- `features` 用于灰度：如 `{chat_prons: true, story_illustrate: true}`

## 3. 音频格式声明【待后端新增】

服务端 PyAV 已能解 m4a/AAC，但错误信息不明确。建议：

```
POST /api/attempts（等）新增可选字段：client_audio = {container:"m4a", codec:"aac", sample_rate:16000, channels:1}
```
- 服务端仅用于**日志与错误提示**（"不支持的音频格式：<container>"）
- 仍保留服务端自行探测（不信任客户端声明）

## 4. 对话轮次发音信息【已实现·后端现有】（`/api/chat/sessions/:id/messages`）

发音评分是**后台异步**的：`turn` 接口在 `after()` 里跑 unscripted 评测并写入 `chat_messages.pron_json`，
客户端需要**轮询** messages 接口获取：

```
GET /api/chat/sessions/:id/messages
  { messages: [ { id, role, text, pron: {pron, accuracy, fluency, completeness,
                  weak_phonemes:[{label, score}], words:[{word, score}]} | null } ] }
```
- **注意**：`GET /api/chat/sessions/:id` **不返回** `messages[].pron`；客户端不要指望它
- 儿童视角由**客户端**决定不显示分数（服务端已把 IPA 剥离；分数照常返回）
- 这正是"三步对话"链路的第 3 步之后要补的数据（见 `design-overview.md` §5.3）

## 5. 上传断点/幂等【待后端新增（可选）】

原生端弱网重试更常见，建议：
```
POST /api/attempts/async 支持 header: Idempotency-Key: <client-uuid>
  → 同一 key 重复提交返回同一 attempt id（不重复计费/计分）
```

## 6. 推送（M4，可选）

- iOS：APNs；鸿蒙：Push Kit
- 用途：家长每日摘要、故事集提醒
- 服务端需：设备 token 注册表 + 发送任务（`POST /api/push/register`）

---

## 优先级

| 项 | 何时做 | 阻塞客户端吗 |
|---|---|---|
| Bearer Token | 第二版（M2 前后）| 不阻塞（首版用 Cookie）|
| `/api/version` | M0 之后尽快 | 不阻塞，但建议早做 |
| 音频格式字段 | 可与 M0 同期 | 不阻塞（仅改善错误提示）|
| 对话轮次发音 | 已实现（web）| 不阻塞 |
| Idempotency-Key | M1 连读重试时 | 不阻塞（客户端先去重）|
| 推送 | M4 | 不阻塞 |
