# 权限与隐私

> 范围：HarmonyOS 客户端 + 家庭 NAS 服务端的数据边界。
> 本文不是法律意见；上架/合规前需按应用市场与所在地法规复核。
> **最重要的结论先说**：客户端只把数据传到家庭 NAS，但当前部署 `PROVIDER_MODE=hybrid` 会把**音频发给 Azure、文本发给 DeepSeek、书页图片/插画提示发给 DeepSeek/智谱**；这些内容**会离开家庭网络**。因此不能承诺音频/文本/图片留在家庭网络。完全本地需要切 `local` 模式并备好本地模型，**当前未部署**。详见第 5 节。

---

## 1. 权限清单

| 权限 | 类型 | 何时申请 | 用途 | 拒绝后果 |
|---|---|---|---|---|
| `ohos.permission.INTERNET` | system_grant（normal） | 安装时声明 | 访问家庭 NAS `/api/*` | 无法使用任何在线功能 |
| `ohos.permission.MICROPHONE` | **user_grant** | 首次点“开始说”/“跟我读” | 录制口语练习 | 不能录音；仍可看语料/听示范/看历史 |
| `ohos.permission.CAMERA` | user_grant | **默认不申请** | 仅自绘相机预览才需要 | 不影响系统拍照识别 |
| `ohos.permission.READ_IMAGEVIDEO` | user_grant/受限 | **默认不申请** | 仅直接读媒体库才需要 | 不影响系统图片选择器 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 受限 | **不申请** | 后台录音/播放 | 不支持后台，符合产品设计 |
| `ohos.permission.VIBRATE` | system_grant | 可选 | 录音开始/结束触感反馈 | 无影响 |

**最小权限原则**：首发只声明 `INTERNET` + `MICROPHONE`。

- 拍照识别使用系统 `cameraPicker`：官方说明应用**无需申请相机权限**（由系统相机完成拍摄与确认）。
- 选择相册使用系统 `PhotoViewPicker`：由系统选择器授权单张/多张，应用不直接拿媒体库权限。
- 如果未来做“自绘相机取景框/连拍”，才需要 `CAMERA`，并重新走隐私评审。

---

## 2. `module.json5` 声明

```json5
{
  "module": {
    "name": "entry",
    "type": "entry",
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET"
      },
      {
        "name": "ohos.permission.MICROPHONE",
        "reason": "$string:reason_microphone",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      }
      // 默认不声明 CAMERA / READ_IMAGEVIDEO；使用系统 picker 不需要。
      // 若未来加自绘相机：
      // {
      //   "name": "ohos.permission.CAMERA",
      //   "reason": "$string:reason_camera",
      //   "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
      // }
    ]
  }
}
```

`resources/base/element/string.json`：

```json
{
  "string": [
    {
      "name": "reason_microphone",
      "value": "用来录下你读的句子，帮你练发音。录音只在你点击录音时开始，停止后立即关闭麦克风。"
    },
    {
      "name": "reason_camera",
      "value": "用来拍下书页，识别成可以跟读的句子。照片会上传到你家 NAS。"
    }
  ]
}
```

> `reason` 会出现在系统权限弹窗里；文案要短、具体、不夸大。儿童版可另用 `reason_microphone_child`，但系统弹窗只取一个字符串，建议用中性表述。

---

## 3. 运行时权限流程

### 3.1 麦克风

```text
点击录音
  → checkAccessToken(MICROPHONE)
      ├─ GRANTED → 开录
      └─ DENIED
           → 应用内说明卡（为什么需要/录音何时开始/何时释放）
           → requestPermissionsFromUser([MICROPHONE])
               ├─ 授权 → 开录
               └─ 拒绝 → 不重复弹窗
                    → “需要麦克风才能练习”
                    → [去设置] requestPermissionOnSetting
                    → 或提示手动路径
```

- 每次录音前都检查（用户可能在设置里撤销）。
- 拒绝后不循环弹系统框；系统不会再次显示，重复调用只会立即返回拒绝。
- 儿童文案：“要听到你的声音，才能帮你看看读得准不准。点‘去打开’就可以啦。”
- 不申请麦克风也能：看语料、听示范、看历史报告、看家长面板。

### 3.2 相机/相册

- 拍照：`cameraPicker.pick(context, [PHOTO], profile)`；结果 URI → 读取 → 上传 `/api/ocr`。
- 相册：`photoAccessHelper.PhotoViewPicker` 选择图片；不需要媒体库权限。
- HEIC：先看 `GET /health` 的 `voice.capabilities.heic`；`false` 时上传前拦截，提示“这张是 HEIC，换一张 JPG 或用相机拍”。
- 图片上传上限 10MB；客户端先压缩/缩放（长边 2048px、JPEG 85%）再传；不保留原图。
- 拍照/选图只用于 OCR，不用于人脸/身份识别。

### 3.3 网络

- `INTERNET` 无需运行时申请；但要在隐私说明中写明“访问家庭 NAS”。
- 启动时 `GET /api/health` 只用于连通性/能力判断，不采集设备信息。
- 不允许用户输入任意公网地址（release）；baseUrl 固定为家庭域名。

---

## 4. 网络与传输安全

| 项 | 要求 |
|---|---|
| 协议 | 生产 **HTTPS only**；release 禁止明文 HTTP |
| 域名 | `english.dreamsearch.top`，仅家庭网络/VPN 可达 |
| 证书 | 使用系统默认 CA 校验；**不提供“忽略证书错误”开关** |
| Pinning | MVP 不做；M4 评估证书 pinning（家庭自签/换证书会导致失联） |
| 代理 | 不主动配置代理；遵循系统网络；不使用第三方中转 |
| 凭据传输 | `Authorization: Bearer <access>` 只走 HTTPS；refresh 只发给 `/auth/refresh`；不写 URL/日志 |
| Token 存储 | Asset Store Kit（`@ohos.security.asset`）的两个别名；不进 Preferences/日志/备份 |
| 明文例外 | debug 包可临时用 `http://192.168.x.x:3000`；release 不允许 |

> 【待真机验证】HarmonyOS 对明文 HTTP 的拦截行为与网络配置项；以目标 SDK/机型实测为准。若被拦截，不要绕过，改用 HTTPS。

---

## 5. 数据流与出网边界

### 5.1 两条链路

```text
客户端 ──HTTPS/Bearer──► web (Next.js :3000) ──HTTP──► voice (FastAPI :8100)
                              │                           │
                              │ SQLite + data/audio       ├─ 本地模型（faster-whisper / piper / 本地 OCR）
                              │ data/materials            └─ 云 API（Azure Speech / DeepSeek / 智谱 GLM）
```

- **客户端只与 web 通信**；不直连 voice，不持有任何云 provider 密钥。
- web 是否把音频/文本/图片转发到云，取决于 **voice 的 `PROVIDER_MODE` 与分项 provider 配置**。

### 5.2 当前部署事实（`PROVIDER_MODE=hybrid`）

仓库 `deploy/.env` 当前为：

```text
PROVIDER_MODE=hybrid
```

（仅核对模式行，未读取任何密钥。）

当前数据去向：

| 数据类型 | 处理方 | 用途 |
|---|---|---|
| 录音音频 | **Azure AI Speech** | ASR、发音评测、TTS |
| 文本（对话/改写/复述） | **DeepSeek** | LLM 对话、故事改写、复述评估 |
| 书页图片 / 插画提示 | **DeepSeek / 智谱 GLM** | 多模态 OCR、文生图 |

- 具体以 `/v1/health` 的 `providers_effective` 为准（该字段只在 voice 侧；web 的 `/api/health` 目前只暴露 `mode` 与 `capabilities`）。
- 这意味着：**音频、文本、图片都会离开家庭网络**，由 NAS 转发给上述服务商；客户端无法阻止或保证云端不留存。

### 5.3 结论表

| voice 模式 | 数据路径 | 数据是否离开家庭网络 |
|---|---|---|
| `mock` | 不调用外部；假数据 | 否（但没有真实评分） |
| `local` | NAS 本地模型 | 否（前提：所有分项都是 local，且无云 OCR/LLM/插画） |
| `cloud` | NAS → 云 provider | **是** |
| `hybrid`（当前） | 部分云、部分本地 | **是**（音频→Azure、文本→DeepSeek、图片→DeepSeek/智谱） |

**因此：**

- 对用户的隐私文案**必须如实写“会离开家庭网络”**，不能写“绝不离开”“本地处理”。
- 当前 `hybrid` 部署下，应明确告知“录音会由家庭 NAS 转发给云端语音服务商（Azure）用于识别/评分/合成；对话文本会发给 DeepSeek；书页图片/插画提示会发给 DeepSeek/智谱”。
- 若产品必须做到完全本地，需要把 voice 切成 `local`（或分项 local）并关闭云 OCR/LLM/插画；这是**部署配置变更**，不是客户端能控制的，**当前未部署**。
- 建议后端在 `/api/health` 增加一个面向客户端的 `privacy` 摘要（如 `{cloud_audio:true, providers:["azure"], ...}`），供隐私文案动态展示【待后端新增】。

### 5.4 各类数据的去向

| 数据 | 客户端 | 家庭 NAS | 是否可能到云 |
|---|---|---|---|
| 邮箱、密码 | 不存密码；邮箱可选记住 | SQLite（密码 bcrypt hash） | 否 |
| access/refresh token | Asset Store | 服务端会话表（refresh 哈希/记录） | 否 |
| 录音 | pending/cache，登出清理 | `data/audio/` | **是**（Azure：ASR/PA/TTS） |
| 评测分数/错音 | 结果缓存 | SQLite | 否（结果可能由云算出） |
| 对话文本/回复 | 页面内存 | SQLite chat_messages | **是**（DeepSeek；TTS 走 Azure） |
| 书页/故事/插画 | 临时图/缓存 | SQLite + `data/materials/` | **是**（OCR/LLM/文生图：DeepSeek/智谱） |
| 建议内容 | 草稿本地 | SQLite suggestions | 否 |
| 用量统计 | 本地计数 | SQLite practice_sessions | 否 |
| 设备信息 | 不采集 | web 日志可能有 IP/UA | 视日志配置 |

> “到云”不等于“被用于训练”。是否用于训练取决于 provider 的 API 条款；家庭自用应选择不用于训练的 API/区域，并在隐私说明中写明。需要部署方核对 Azure/DeepSeek/智谱的条款。

---

## 6. 客户端可以承诺什么

可以写进隐私说明的**客户端侧**承诺：

1. App 不接入任何第三方广告、统计、推送、崩溃上报 SDK。
2. App 不读取通讯录、短信、位置、剪贴板、已安装应用列表。
3. App 不后台录音；只在用户点击录音/“跟我读”时打开麦克风，停止后立即释放。
4. App 只与 `https://english.dreamsearch.top` 通信，不直连第三方 AI 服务。
5. 录音/图片只写入应用沙箱，不上传系统相册/公共目录。
6. 退出登录会清除本机 token、待上传录音和音频/图片缓存。
7. 儿童界面不显示 IPA、不显示低分；不基于儿童数据做广告画像。

**不能**由客户端承诺：

- “录音/文本/图片只在家庭网络内处理”（当前 hybrid 会发给 Azure/DeepSeek/智谱）。
- “NAS 上的数据会被自动删除”（当前没有自动保留期/用户删除入口）。
- “云端 provider 不会记录数据”（取决于其条款）。
- “家长可以随时远程注销所有设备”（当前没有 logout-all 接口）。

---

## 7. 服务端责任（需部署方确认）

| 项 | 现状 | 建议 |
|---|---|---|
| 传输 | HTTPS（Caddy） | 保持；证书自动续期 |
| 账号 | bcrypt hash；Token（access 1h / refresh 30d，可轮换/吊销） | 保持；补“本人改密 + 注销全部设备”【待后端新增】 |
| 录音存储 | `data/audio/`，按用户/尝试 | 明确保留期；提供家长删除入口【待后端新增】 |
| 聊天/评测 | SQLite | 明确保留期；备份加密 |
| 材料/插画 | `data/materials/` | 删除材料时同步删图（已有） |
| 日志 | 容器日志 | 不记录音频/文本全文；脱敏 |
| 备份 | VACUUM INTO / tar | 加密；限制访问；不包含 `.env` 密钥的明文备份 |
| 云 provider | hybrid/cloud | 核对数据处理条款/区域；是否出境 |
| 清理 | 运维脚本 `cleanup-user-data.mjs`（按账号+时间点，需 `--yes`，删前备份） | 不是 App 功能；可作为家长申请删除的内部流程 |
| 删除权 | App 无删除账号/数据入口 | 产品需明确“联系家长/管理员”流程 |

> 当前代码没有面向用户的“删除我的数据”接口；只有运维脚本可按账号+时间点清理。若面向应用市场上架，这通常是一个合规缺口，需要产品/后端补齐。

---

## 8. 儿童隐私

- **账号由家长创建**；儿童不自行注册、不填写邮箱/手机号。
- 首次使用儿童账号：展示“家长须知 + 儿童版说明”，由家长确认；儿童版用一句话说明“你的声音用来帮你练英语”。
- 不收集：真实姓名（昵称即可）、学校、住址、位置、通讯录、照片（除主动拍书页）、设备唯一标识。
- 不投放广告、不做用户画像、不做社交/排行/公开分享。
- 家长可查看孩子的练习数据（`/parent/summary`）；这是产品设计的一部分，需在家长须知中说明。
- 儿童提交的建议会剥 IPA，但仍是文本；家长可在收件箱看到。需告知儿童“你写的建议家长能看到”。
- 儿童模式不显示低分/IPA 是**教学策略**，不是隐私措施；不要混淆。

---

## 9. 本地存储安全

| 数据 | 位置 | 保护 |
|---|---|---|
| access/refresh token | Asset Store Kit（`Tag.SECRET`，别名 `ec_access_token` / `ec_refresh_token`） | 系统加密；显式设置 `SYNC_TYPE.NEVER`（不同步）；`IS_PERSISTENT=false`（卸载即删） |
| 邮箱（可选） | Preferences | 明文；仅用于登录预填；可关闭 |
| 用户资料缓存 | Preferences | 只存 `displayName/role/ageBand/cefrLevel/avatar`；不存邮箱 |
| baseUrl/lastLevel/ttsRate | Preferences | 非敏感 |
| 录音 pending | `filesDir/pending` | 应用沙箱；登出/24h 清理 |
| 音频/图片缓存 | `cacheDir` | 应用沙箱；LRU；登出清理 |
| 日志 | 应用沙箱 | 脱敏；不写 token/文本 |

- 不使用 `IS_PERSISTENT=true`（避免卸载后残留）。
- 不把 token 写入 `preferences`、`AppStorage` 持久化、剪贴板、通知。
- 设备丢失：只能吊销该设备的 refresh token（`/auth/revoke`），**没有 logout-all**；短期靠 refresh 30 天过期；建议后端补“注销全部会话”。

---

## 10. 隐私说明文案

### 10.1 完整版（设置页/首次启动，成人）

> **我们收集什么**
> 为了帮你练口语，App 会在你点击录音时录下你的声音，并上传到你家自己的 NAS（`english.dreamsearch.top`）。同时会上传你选择的句子、练习结果、对话文字、你拍的书页/故事和提交的建议。
>
> **数据放在哪里**
> 账号、练习记录、录音、书页/故事都保存在你家 NAS 上（云端处理见下一节）。App 不接入广告、统计或推送 SDK，不读取通讯录、位置或相册以外的文件；照片只在你主动拍照/选图时读取。
>
> **会不会用到云端**
> 当前语音服务模式为「{mode}」。{cloud_note}
> 若当前为 hybrid/cloud：录音会由 NAS 转发给 Azure（识别/评分/合成），对话与故事文本会发给 DeepSeek，书页图片/插画提示会发给 DeepSeek/智谱。**这些内容会离开家庭网络**；具体以部署配置为准。
>
> **保留多久 / 怎么删除**
> 登录状态最长 30 天（refresh token 到期后需重新登录）；练习记录和录音的保留期由家庭 NAS 管理。你可以在设置里清除本机缓存；如需删除 NAS 上的数据，请联系家庭管理员。
>
> **儿童**
> 儿童账号由家长创建；家长可以查看孩子的练习记录。儿童界面不显示音素符号和低分，不使用儿童数据做广告画像。
>
> **联系**
> 家庭管理员：家长账号（可在家长面板中查看，不在儿童界面展示邮箱）。

`{cloud_note}` 按 `voice.mode` 动态替换：

- `mock`：“当前为演示模式，不调用云端 AI。”
- `local`：“当前使用 NAS 本地模型；只有 OCR/LLM/插画等分项也全部为本地时，数据才不离开家庭网络。”
- `hybrid`：“当前为混合模式：音频会发给 Azure，文本会发给 DeepSeek，图片/插画会发给 DeepSeek/智谱；这些内容会离开家庭网络。”
- `cloud`：“当前为云端模式：录音/文字会发送到云端服务商。”
- 未知/不可达：“暂时无法确认云端使用情况，请向家庭管理员核实。”

> 若后端不提供准确的 provider 列表，文案只能写到“可能”，不能写“绝不会”。

### 10.2 儿童版（首次进入儿童账号）

> 你的声音只用来帮你练英语。
> 你的声音会先送到家里的 NAS，再交给云端服务商（Azure）帮你识别和评分；这些声音会离开家里的网络，但只用来帮你练英语，不会给广告商。
> 你说的话、拍的书页也会交给云端的大模型服务商（DeepSeek/智谱）。
> 如果不想录了，点“取消”就可以；麦克风会马上关掉。
> 你写的建议，爸爸妈妈可以看到。

### 10.3 家长须知（首次创建儿童账号）

> 你正在为孩子创建家庭英语练习账号。孩子的录音、练习分数、对话文字会保存在你家 NAS 上，你可以查看。
> 当前语音服务模式为「{mode}」。{cloud_note}
> 我们不投放广告、不做用户画像；儿童界面不显示音素符号和低分。
> 你可以随时在家长面板修改孩子的时长/自由话题，或联系管理员删除数据。
> 继续即表示你同意上述数据处理方式。

---

## 11. 合规检查清单（上架前）

- [ ] 隐私政策 URL 可公网访问（即使服务只在家庭网络，政策页也要能打开）。
- [ ] 应用市场隐私标签与实际权限一致（只声明 MICROPHONE + INTERNET）。
- [ ] 首次启动展示隐私政策，明确同意后才申请麦克风；拒绝不影响只读功能。
- [ ] 儿童账号有家长同意流程；儿童版说明可读。
- [ ] 说明数据出境风险（若使用境外云 provider）。
- [ ] 提供数据删除/更正渠道（即使只是“联系管理员”）。
- [ ] 不收集设备标识/位置/通讯录；无广告 SDK。
- [ ] 备份加密、访问受限；日志脱敏。
- [ ] 证书有效、无“忽略证书错误”开关。
- [ ] 应用市场要求的软件著作权/备案/隐私检测报告（以当期要求为准）。

---

## 12. 事件响应（简版）

| 事件 | 立即动作 | 后续 |
|---|---|---|
| 设备丢失 | 在另一台设备登录后吊销该设备 refresh token（`/auth/revoke`）；没有 logout-all，其余设备仍有效；也可等 30 天过期 | 建议后端补 logout-all；不要把“改密码”当成踢下线 |
| token 泄露 | 立即吊销对应 refresh token + 重新登录；管理员可在服务端删会话 | 审计日志；缩短 access TTL |
| 录音误上传 | 停止使用；管理员用清理脚本按账号+时间点删除 | 备份留存策略 |
| 云 provider 泄露 | 联系 provider；评估影响范围 | 告知家长；必要时切换 local |
| NAS 被入侵 | 断网、改密钥、恢复备份 | 通知家庭；轮换 provider keys |

> 当前没有“注销全部设备”的客户端/服务端接口，这是安全短板；已列入 open-questions。
