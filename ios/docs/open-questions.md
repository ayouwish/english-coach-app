# 开放问题与待决事项

> 本文档是**唯一的问题登记处**。拍板后：更新对应文档 + 在 `docs/adr/` 留决策记录，然后把该条状态改为"已决"（保留记录，不删除）。
> 状态：`待决` / `待实测` / `已决`。影响标注：`阻塞 M0` 等。

---

## 0. 已拍板的三件事（2026-10-31）

| # | 问题 | 结论 | 记录位置 |
| --- | --- | --- | --- |
| **Q1** | 登录态怎么持久化？ | **Bearer Token**：access 1h / refresh 30d（一次性轮换）、Keychain 存储、网络层单飞刷新、退出 `/revoke`。Web 端继续用 Cookie，双模式并存。 | [ADR-0003](adr/0003-bearer-token.md)（取代 [ADR-0001](adr/0001-cookie-session-vs-bearer-token.md)） |
| **Q2** | 最低支持哪个 iOS？ | **iOS 26.0**。用户设备可控、长期维护，不做 17/16 兼容分支。 | [ADR-0002](adr/0002-min-ios-version-and-observation.md) |
| **Q3** | 如何分发？ | **TestFlight 内部测试**（≤100 名内部测试员，无需 Beta 审核；构建 90 天过期）。不上 App Store、不做免费自签。 | `README.md` §6.6、`roadmap.md` M0/M4 |

> **当前唯一的硬阻塞**：后端 token 三接口（`/auth/token`、`/auth/refresh`、`/auth/revoke`）尚未上线，见 B17。其余 M0 事项（最低版本、分发、录音参数）已定。
>
> Q4（共用设备/儿童 PIN）与 Q7（推送）会影响 M1/M4 的交互设计，仍建议尽早拍板。

---

## 1. 产品 / 体验决策（Q）

### Q1 · 登录态持久化方案（已决 · 2026-10-31）

| 项 | 内容 |
| --- | --- |
| 结论 | **Bearer Token**（不是 Cookie）。后端新增 `/auth/token`、`/auth/refresh`、`/auth/revoke`（P0）；所有接口接受 `Authorization: Bearer`，Web 仍用 Cookie。 |
| 客户端 | access 1h / refresh 30d；两个 token 存 **Keychain**；网络层**单飞刷新**（并发 401 只 refresh 一次，其余等待后重放）；refresh 被服务端拒绝 → 清 token 跳登录；退出 → `/revoke` + 清本地。 |
| 关键约束 | refresh **一次性轮换**，所以客户端**不得并发/重试** refresh；网络错误不清 token（只对 401/403 生效）。 |
| 记录 | [ADR-0003](adr/0003-bearer-token.md)；原 Cookie 方案 [ADR-0001](adr/0001-cookie-session-vs-bearer-token.md) 标记 Superseded |
| 归属 | 后端（实现三接口）/ 客户端（刷新与存储） |
| 剩余验证 | B17；见 C3、C5 |

### Q2 · 最低 iOS 版本（已决 · 2026-10-31）

| 项 | 内容 |
| --- | --- |
| 结论 | **iOS 26.0** |
| 理由 | 用户设备可控、长期维护；避免 17/16 双套状态写法与 `#available` 分支；TestFlight 内部测试员的设备也统一升级。 |
| 影响 | 低于 iPhone 11 / SE(第二代) 的设备无法安装（以 Apple 官方兼容列表为准）；Xcode 需 26+。 |
| 记录 | [ADR-0002](adr/0002-min-ios-version-and-observation.md) |
| 剩余验证 | 家庭实际设备清单与 Xcode 就绪情况（未在仓库记录） |

### Q3 · 分发方式与签名（已决 · 2026-10-31）

| 项 | 内容 |
| --- | --- |
| 结论 | **TestFlight 内部测试** |
| 细节 | 内部测试员最多 100 名、**无需 Beta App Review**；构建 **90 天过期**，需定期重传；Bundle ID `top.dreamsearch.englishcoach`（待确认唯一性）；需 Apple Developer Program 付费账号、App Store Connect 记录、`PrivacyInfo.xcprivacy`。 |
| 不再评估 | 免费账号自签（7 天重签）；App Store 上架（需解释“服务器仅家庭内网可达”，无收益）。 |
| 记录 | `README.md` §6.6；`roadmap.md` M0（通道）/ M4（Beta 运维） |

### Q4 · 共用设备与账号切换（影响 M1）

| 项 | 内容 |
| --- | --- |
| 现状 | 只有邮箱+密码登录；无 PIN、无头像点选、无"切换孩子" |
| 场景 | 家里一台 iPad 给两个孩子用；家长想快速切到孩子账号看数据 |
| 选项 | ① 每次输密码（现状）；② 本地"最近账号"列表 + 一键切换（仍需密码）；③ 儿童 PIN 快速登录【待后端新增】；④ 家长代持会话 + 选择"以孩子身份练习"【待后端新增】 |
| 建议 | 先做 ②（客户端即可：Keychain 存最近 2 个账号邮箱，密码仍要输）；③④ 需要后端，列为 M4 候选 |
| 归属 | 产品 + 后端 |

### Q5 · 界面语言（影响 M2 文案量）

| 项 | 内容 |
| --- | --- |
| 选项 | 仅简体中文 UI（英文只出现在学习内容里） / 中英双语 UI |
| 影响 | 若双语，所有文案要走 String Catalog 并准备英文；孩子可能误触语言切换 |
| 建议 | **本期仅简体中文 UI**，但所有字符串走 `Localizable.xcstrings`，为未来留路 |
| 归属 | 产品 |

### Q6 · 家长修改自己的密码（影响 M3）

| 项 | 内容 |
| --- | --- |
| 现状 | 只有 `POST /family/members/:id/password`（家长重置孩子的），**没有"改自己密码"的接口** |
| 选项 | ① 显示说明页，让家长去 NAS 操作（本期）；② 【待后端新增】`POST /auth/password {old,new}` |
| 建议 | 本期做 ①，同时提 ② 的需求（改动很小）；孩子账号不受影响（走家长重置） |
| 归属 | 后端 + 产品 |

### Q7 · 推送/提醒（影响 M4）

| 项 | 内容 |
| --- | --- |
| 需求 | "今天还没练"提醒、家长收到孩子完成通知 |
| 约束 | APNs 需要 NAS **出网**到 Apple；且需要服务端保存 device token【待后端新增】；本地通知只能做"定时提醒"，不能做"家长收孩子完成" |
| 选项 | ① 仅本地通知（零后端）；② APNs（需后端 + 出网） |
| 建议 | M4 先做 ①；② 列入后端待办，等家庭实际需要 |
| 归属 | 产品 + 后端 |

### Q8 · iPad / 横屏（影响 M0 布局与 M4）

| 项 | 内容 |
| --- | --- |
| 选项 | 仅 iPhone 竖屏（本期） / iPhone + iPad 自适应 |
| 影响 | iPad 需要分栏（`NavigationSplitView`）、更大的句卡、横屏键盘处理；但家庭场景 iPad 很常见 |
| 建议 | M0–M3 只做 iPhone 竖屏（工程上仍用自适应布局，避免写死宽度）；M4 再正式支持 iPad |
| 归属 | 产品 |

### Q9 · 数据保留与隐私（影响 M4、也影响文案）

| 项 | 内容 |
| --- | --- |
| 问题 | 录音在服务端保留多久？家长能否删除孩子录音？本机缓存保留多久？ |
| 现状 | 无删除接口；客户端默认录音缓存 7 天 |
| 建议 | 客户端 7 天自动清理 + 设置页"清除本机数据"；服务端保留策略请后端明确（涉及家长知情） |
| 归属 | 产品 + 后端 |

### Q10 · 可接受的评分等待时间（影响同步/异步选择）

| 项 | 内容 |
| --- | --- |
| 问题 | 单句跟读时，用户愿意等多久？超过多少秒必须改成"后台评分 + 通知"？ |
| 建议 | ≤4s 用同步；4–8s 显示进度文案；>8s 改为 async 轮询并把结果异步呈现（M1 状态机已具备） |
| 依据 | 需 C2 实测 |
| 归属 | 产品 |

### Q11 · 是否做"离线先录、联网补评"（影响 M4）

| 项 | 内容 |
| --- | --- |
| 价值 | 网络不稳时的体验兜底 |
| 成本 | 本地队列 + 冲突处理 + "补交"的语义（评分时间以谁为准）+ 可能重复扣配额 |
| 建议 | 仅在家庭网络确实不稳定时做；否则**明确告诉用户离线不能评分**更诚实 |
| 归属 | 产品 |

### Q12 · 故事模式的内容边界

| 项 | 内容 |
| --- | --- |
| 问题 | 任意书页拍照 → OCR → 改写，是否涉及版权内容？是否需要过滤敏感内容？ |
| 建议 | 定位"家庭自用、不公开分享"；在 UI 说明"仅用于家庭学习"；不做公开作品集 |
| 归属 | 产品 |

---

## 2. 后端契约确认（B）

> 未决项需要后端给一个**真实响应样例**（脱敏即可），客户端按样例写解码与测试；**已确认项（B1）可直接实现**，不要再按旧猜测写双解码分支。

### B1 · `/chat/sessions/:id/turn` 的响应形态（已确认 · 2026-10-31，不再阻塞）

| 项 | 内容 |
| --- | --- |
| 已确认 | turn **只返回助手文本与纠错**（`reply`、`reply_zh`、`correction`、`suggested_replies`、`target_words`、`done`、`turn_index`、`message_id`、`user_message_id`、`user_audio_url` 等），**不做 ASR、不返回 TTS 音频**。 |
| 客户端链路 | `POST /asr`（multipart audio → `text`）→ `POST /chat/sessions/:id/turn`（multipart，**`text` 必填** + audio）→ `POST /tts`（用 `reply` 合成音频）。 |
| 发音评分 | 后台异步写库，由 `GET /chat/sessions/:id/messages` 返回用户消息的 `pron`；`GET /chat/sessions/:id` **不含** `pron`，需轮询。 |
| 实现位置 | `screens.md` §5.3/§5.4、`audio.md` §5.1/§6.1、`architecture.md` §6.2 |

### B2 · `/attempts/status` 的状态枚举与字段（阻塞 M1）

| 项 | 内容 |
| --- | --- |
| 未知 | `pending`/`scoring`/`done`/`failed`？完成后是否与同步 `/attempts` 结构一致？失败是否带 `error.code`？ |
| 影响 | 轮询状态机与汇总页 |
| 建议 | 复用 `/attempts` 的结果结构；失败项带 `error`；`ids` 数量上限明确（建议 ≥20） |

### B3 · `/story/rewrite` 的返回（阻塞 M2）

| 项 | 内容 |
| --- | --- |
| 未知 | 是否返回 `story_sentences` 数组？是否返回 `story_id`/`material_id`？`readability` 的字段结构？是否已落库？ |
| 影响 | 复述需要 `story_sentences`；若未返回，客户端只能自己按句号切分（不可靠） |
| 建议 | 返回 `{story_id, sentences:[{en, zh}], readability:{...}}`，并同时创建 material |

### B4 · `/materials/:id/...` 的编辑/删除路径（阻塞 M2）

| 项 | 内容 |
| --- | --- |
| 未知 | 具体路径与方法（`POST /materials/:id/delete`? `PATCH /materials/:id`?）；可编辑字段（标题？句子？） |
| 影响 | 作品集滑动删除/重命名 |
| 建议 | `DELETE /materials/:id` + `PATCH /materials/:id {title}` |

### B5 · `/story/:id/illustrate` 同步还是异步（阻塞 M2）

| 项 | 内容 |
| --- | --- |
| 未知 | 是否同步等待生图（可能 10–30s）？返回的是 URL 还是二进制？URL 有效期？ |
| 影响 | 创建向导的等待设计与失败重试 |
| 建议 | 若 >10s，改为 `202 + job_id` + 轮询；返回稳定可缓存的 URL |

### B6 · `/parent/summary` 的字段（阻塞 M3）

| 项 | 内容 |
| --- | --- |
| 未知 | 按孩子聚合还是平铺？包含哪些指标（句数/时长/最弱音素/连续天数/最近时间）？是否含多个孩子？ |
| 影响 | 家长面板布局必须先看到样例，否则只能做容错骨架 |
| 建议 | `{children:[{user_id, display_name, week_sentences, week_minutes, weak_phonemes:[], last_active_at}]}` |

### B7 · `/suggestions` 的字段与状态（阻塞 M3）

| 项 | 内容 |
| --- | --- |
| 未知 | 提交字段（type/content/sentence_id?）、列表字段、状态枚举（pending/resolved?）、是否家长专属 |
| 影响 | 建议箱表单与列表 |
| 建议 | 明确 `POST` 也仅家长可用；返回创建时间与状态 |

### B8 · 家长自助改密接口（阻塞 M3 的"改密"完整度）

| 项 | 内容 |
| --- | --- |
| 现状 | 无 `POST /auth/password` |
| 影响 | 设置 → 修改密码只能显示说明页 |
| 建议 | `POST /auth/password {old_password,new_password}`，成功后可要求重新登录（客户端统一重新登录） |

### B9 · `/attempts` 响应结构与 `unscripted` 语义（阻塞 M0/M3）

| 项 | 内容 |
| --- | --- |
| 未知 | 音素级/词级/语调曲线的确切 JSON；`score` 范围（0–100?）；`mode=unscripted` 时 `reference_text` 是否必填；盲测用它是否合适 |
| 影响 | 结果页、图表、盲测 B |
| 建议 | 给出完整样例（含 `issues`、`feedback`、`pitch` 数组与采样点定义） |

### B10 · `/sentences` 的分页与缓存头（影响 M0）

| 项 | 内容 |
| --- | --- |
| 未知 | 一次返回 600 句还是分页？有无 `page/limit`？有无 `ETag`/`Last-Modified`？ |
| 影响 | 客户端缓存策略与列表性能 |
| 建议 | 支持 `?level=&page=&limit=` + `ETag`；600 句一次性返回也可接受 |

### B11 · `/diagnosis` 是否含历史趋势（影响 M3）

| 项 | 内容 |
| --- | --- |
| 未知 | 只有当前快照，还是含时间序列？ |
| 影响 | 成长页趋势图：无历史则用客户端本地统计 |
| 建议 | 返回 `history:[{date, mastery}]` 更好；否则客户端自算 |

### B12 · ~~Cookie 会话属性~~（作废）

原 B12（Cookie 会话属性与会话时长）只服务于 ADR-0001 的 Cookie 方案；该方案已被 **Bearer Token** 取代（Q1 / ADR-0003），本问题**作废**，由 **B17** 替代。不要再按 Cookie 方案写客户端。

### B13 · 并发与限流（影响 M1/M2）

| 项 | 内容 |
| --- | --- |
| 未知 | 同时最多几个评分/生图任务？超限返回什么错误？ |
| 影响 | 连读并发上传数、生图重试策略 |
| 建议 | 明确返回 429 或 `provider_unavailable`，客户端据此退避 |

### B14 · `/audio/:id` 是否支持 Range（影响回放体验）

| 项 | 内容 |
| --- | --- |
| 未知 | 是否支持 `Range`、`Content-Type` 是否 `audio/mp4`、是否 `Content-Disposition` |
| 影响 | 目前策略是"下载完整文件再播"，若支持 Range 可流式起播 |
| 建议 | 加 `Accept-Ranges: bytes`；否则客户端继续全量下载（会话短音频可接受） |

### B15 · `/health` 的 `voice.mode` 与能力语义

| 项 | 内容 |
| --- | --- |
| 未知 | `mode` 的取值含义（真实/模拟？）、`capabilities` 字段是否稳定 |
| 影响 | 设置页服务器体检的文案与"生成插画/OCR 是否可用"的判断 |
| 建议 | 明确 `mode` 枚举；`capabilities` 保持布尔语义 |

### B16 · 跨用户访问规则

| 项 | 内容 |
| --- | --- |
| 未知 | 家长能否通过 `/audio/:id`、`/attempts/status` 访问孩子的数据？孩子能否访问他人的 attempt id？ |
| 影响 | 家长面板未来做"查看孩子录音"的可行性；也是安全边界 |
| 建议 | 服务端按 family 关系鉴权，并在文档中写明 |

### B17 · Bearer Token 三端点细节（阻塞 M0，替代 B12）

| 项 | 内容 |
| --- | --- |
| 已定契约 | `POST /auth/token {email,password}` → `{access_token, refresh_token, token_type:"Bearer", expires_in:3600, user}`；`POST /auth/refresh {refresh_token}` → 新一对（**一次性轮换**）；`POST /auth/revoke {refresh_token}` → 204；所有接口接受 `Authorization: Bearer`，Web 继续用 Cookie。 |
| 仍需后端确认 | ① 各失败场景的 `error.code`（密码错误、refresh 过期/已吊销/已轮换、revoke 重复调用）；② 轮换是否做**重放检测/宽限期**（旧 refresh 被第二次使用时是 401 还是短暂容忍）；③ `/revoke` 后已签发的 access 是否立即失效（JWT 无状态时最长再活 1h）；④ 是否有登录/刷新限流（429）。 |
| 影响 | 客户端单飞刷新与登出语义、错误文案；ADR-0003 的“失败即清 token”只在**服务端拒绝**时生效。 |
| 建议 | 轮换严格一次性 + 重放直接 401；`/revoke` 同时记入吊销表让 access 也尽快失效；错误统一 `{error:{code,message}}`。 |
| 归属 | 后端（P0） |
| 验证 | `README.md` §6.4 的 curl 自检 + ADR-0003 验证清单 |

---

## 3. 客户端待实测（C）

> 这些不影响"做什么"，只影响"怎么调参"。每条都要有实测记录（设备、系统、结果），写回对应文档。

| # | 待实测 | 影响 | 方法 |
| --- | --- | --- | --- |
| C1 | **16kHz / 单声道 / AAC 65kbps** 的 m4a 在服务端解码与评分是否正常 | 录音参数定稿（已定 16k/65k，不再做码率 A/B） | 真机录 10s/60s → `afinfo` 复核参数 → `/attempts` 看是否 `unsupported_audio` 与分数是否合理 |
| C2 | 同步 `/attempts` 的真实耗时分布 | 同步 vs 异步选择（Q10） | 20 次请求记录 P50/P90 |
| C3 | 杀进程重开是否保持登录（Keychain token + access 过期刷新） | 认证持久化（Q1） | 登录 → 杀进程 → 冷启动 → `/auth/me`；再把 access 置为过期看是否单飞刷新 |
| C4 | `AVAudioRecorder.currentTime` 在 `stop()` 后的行为 | `duration_ms` 取值 | 打印对比文件真实时长 |
| C5 | 并发 401 时是否只发一次 refresh（单飞刷新） | 是否会因轮换竞争掉登录 | `URLProtocol` 桩并发 3 个 401；真机抓包复核 |
| C6 | TTS 缓存命中率与首次/二次起播延迟 | 预取策略、体验预算 | 打点统计 |
| C7 | HEIC 原始体积与转 JPEG 后的体积/清晰度 | 故事模式上传 | iPhone 实拍多张对比 |
| C8 | 局域网内 NAS 域名与证书情况（是否受信任） | ATS 配置、是否要自签例外 | 真机 Safari 访问；`nscurl --ats-diagnostics` |
| C9 | AirPods 连接下录音输入是否可用（HFP 切换） | 蓝牙体验 | 真机按 `audio.md` §10 矩阵 |
| C10 | 60s 录音的实际文件体积（16k/65k） | 12MB 预检 | 实测并核对 ≈0.49MB/分钟 |

---

## 4. 决策记录方式

1. 任何 Q 拍板后：
   - 若是**技术选型**（认证、最低版本、依赖）→ 在 `docs/adr/` 新增或更新 ADR；
   - 若是**产品规则**（儿童模式、分发、语言）→ 更新 `screens.md` / `roadmap.md` 对应小节；
   - 若是**接口契约**（B 系列）→ 用样例更新 `architecture.md` 的 DTO 说明与单测 fixture。
2. 本文档保留问题与结论（不删除），状态改 `已决` 并附日期与决策人。
3. 未决项不得"先猜着实现"：契约类问题（B2–B17 中未决者）明确阻塞对应里程碑，宁可延后一天，不要写两套解析。
