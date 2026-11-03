# 功能索引（Feature Index）· 功能 → 接口 → 页面 → 文档

> **用途**：客户端开发时按功能查"要调哪些接口、对应哪个页面、文档在哪"。
> **维护规则**：后端每上线一个新功能/端点，**必须在同一次变更里更新本文件 + 相关文档**（见 `README.md` §0 的同步规则）。
> **按批次回溯/验收** 见 [`release-notes.md`](release-notes.md)。
> 最后更新：2026-11-03

图例：✅ 已实现（后端/Web 可用） · 🔄 进行中 · 📋 设计就绪未实现 · 📱 移动端 M0 已写代码（未编译）

---

## 1. 账号与登录

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| Bearer Token 登录 | `POST /api/auth/token` | ✅ | README §6.1、`adr/0002-bearer-token.md` |
| Token 刷新（一次性轮换） | `POST /api/auth/refresh` | ✅ | 同上（**客户端必须单飞刷新**）|
| 退出/吊销 | `POST /api/auth/revoke` | ✅ | 同上 |
| 当前用户 | `GET /api/auth/me` | ✅ | 同上 |
| 改密码（家长重置，含自己） | `POST /api/family/members/:id/password` | ✅ | `screens-matrix.md` §1 |
| 改密码（自助，需旧密码） | `POST /api/auth/password` | 📋 可选增强 | `screens-matrix.md` §1 |
| 多账号/家庭成员 | `GET/POST /api/family/members`、`PATCH` | ✅ | `screens-matrix.md` §1 |
| 账号偏好 | `GET/PATCH /api/settings` | ✅ | README §6.1、§3.3（`auto_illustrate`/`gender`/`tts_voice`/`story_sentences`）|

## 2. 跟读练习

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 语料列表（600 句 A1–B2） | `GET /api/sentences?level=` | ✅ | README §6.2 |
| 句子详情 | `GET /api/sentences/:id` | ✅ | 同上 |
| 同步评测（音素/词/语调） | `POST /api/attempts` | ✅ | README §6.2、`acceptance-checklist.md` §C |
| 重试评分 | `POST /api/attempts/:id/retry` | ✅ | 同上 |
| 录音回放 | `GET /api/audio/:id` | ✅ | 同上 |
| 示范音 | `POST /api/tts`、`GET /api/tts/voices` | ✅ | README §6.6 |
| **练习游标（继续上次）** | `GET/PUT /api/practice/cursor`、页面 `/practice` | ✅ | `design-overview.md` §5.1 |
| **单句历史 + 进步曲线** | `GET /api/sentences/:id/attempts`、页面 `/practice` 结果区 | ✅ | `design-overview.md` §5.1 |
| **点单词看音标（全页面）** | `GET /api/words/:word`、`GET /api/words?words=`（web 代理 voice `/v1/words/ipa`）| ✅ | README §6.7、`design-overview.md` §5.8、`screens-matrix.md` §9 |

## 3. 连读模式

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 异步提交 | `POST /api/attempts/async` | ✅ | README §6.2 |
| 轮询进度 | `GET /api/attempts/status?ids=` | ✅ | 同上 |
| 汇总 + 鼓励语 | 本地聚合 | ✅ | `design-overview.md` §5.2 |
| **再读一遍（汇总页）** | 页面 `/flow` 主按钮 `flow-reread` | ✅ | README §6.2、`design-overview.md` §5.2 |
| 拍照识别书页 | `POST /api/ocr` → `POST /api/materials?kind=page` | ✅ | README §6.6 |

## 4. 对话训练

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 场景列表（内置 + 自定义） | `GET /api/chat/scenarios[?include_child=1]` | ✅ | README §6.3、`screens-matrix.md` §4 |
| 自定义场景 CRUD | `POST /api/chat/scenarios`、`PATCH/DELETE /:id` | ✅ | 同上 |
| 场景随机变体（variation） | `POST /api/chat/sessions` 随机抽 + turn 带 `scenario.variation` | ✅ | 同上、`screens-matrix.md` §4 |
| 开始/结束会话 | `POST /api/chat/sessions`、`POST /:id/end` | ✅ | README §6.3 |
| 一轮对话（三步） | `/api/asr` → `POST /:id/turn` → `POST /api/tts` | ✅ | README §6.3、`design-overview.md` §5.3 |
| 消息（校正 + 发音） | `GET /api/chat/sessions/:id/messages` | ✅ | 同上 |
| 不限轮数 | `CHAT_MAX_TURNS=0` | ✅ | `screens-matrix.md` §4 |
| **整段对话回放** | `GET /:id/audio/status`、`GET /:id/audio[?force=1]` | ✅ | README §6.3、`design-overview.md` §5.3 |
| 历史会话列表/详情 | `GET /api/chat/sessions`、`/:id` | ✅ | `screens-matrix.md` §4 |
| 家长/儿童场景分离 + 「再看小朋友的场景」开关 | `?include_child=1`（仅成人生效） | ✅ | `screens-matrix.md` §4 |

## 5. 故事模式

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 中文语音转文字 | `POST /api/asr?language=zh-CN[&provider=]`（默认智谱 GLM-ASR） | ✅ | README §6.4、§3.3 |
| **原始录音留存（先落盘再转录）** | `POST /api/story/recordings`、`POST /:id/transcribe`、`GET /`、`GET /:id/audio` | ✅ | README §6.4、`design-overview.md` §5.4 |
| 中文 → 分级英文改写 | `POST /api/story/rewrite`（`level` A1–C1、`max_sentences` 3–12） | ✅ | README §6.4、§3.3 |
| 人性化句子数默认 | 页面 `/story` + `/api/settings.story_sentences` | ✅ | 同上 |
| 保存故事（回填 recording_id） | `POST /api/materials`（`kind=story`） | ✅ | README §6.4 |
| 故事集列表/筛选 | `GET /api/materials?kind=story` | ✅ | 同上 |
| **原声回顾（我当时讲的原话）** | 页面 `/story/[id]`、`GET /api/materials/:id` | ✅ | `design-overview.md` §5.4 |
| **整段朗读回放** | `GET /api/story/:id/audio/status`、`/audio` | ✅ | 同上 |
| 复述评估（覆盖度，不评发音分） | `POST /api/story/retell` | ✅ | README §6.4 |
| 插画（默认关，可在设置开自动） | `POST /api/story/:id/illustrate`、`/api/settings.auto_illustrate` | ✅ | README §6.4、§1.3 |
| 提示词可见 + 反馈 | 页面 `/story/[id]`（`prompt_used` + 提建议） | ✅ | `design-overview.md` §5.5 |
| **打印（单篇）** | 页面 `/story/[id]/print[?zh=1&lines=1]` | ✅ | README §6.4、`design-overview.md` §5.7 |
| **打印（多选故事集）** | 页面 `/story/print?ids=…[&zh=1&lines=1]` | ✅ | 同上 |

## 6. 虚拟形象 / 音色

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 预置形象库（12 角色 × 5 风格） | `GET /api/avatar/presets` | ✅ | README §6.6、`design-overview.md` §5.5 |
| 选择/编辑/清空形象 | `GET/POST/PATCH/DELETE /api/avatar` | ✅ | 同上 |
| 形象图片 | `GET /api/avatar/image` | ✅ | 同上 |
| 性别与形象推荐 | `PATCH /api/settings {gender}` | ✅ | `screens-matrix.md` §7 |
| 音色（9 种，含试听） | `GET /api/tts/voices`、`POST /api/tts` | ✅ | README §6.6 |
| **单词音标开关**（成人默认开/儿童默认关）| `PATCH /api/settings {show_word_ipa}` | ✅ | `screens-matrix.md` §7 |
| 照片生成形象（隐私策略关闭） | `POST /api/avatar`（照片）→ 403 `policy_disabled` | ✅ | README §1.4 |

## 7. 诊断 / 盲测 / 复习

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 分层诊断（单句/批次/最近/全部） | `GET /api/diagnosis?scope=…` | ✅ | README §6.5、`design-overview.md` §5.6 |
| 对子去重（a→b / b→a 合并） | 同上（`contrasts` 已去重） | ✅ | 同上 |
| 错音本（SRS） | `GET /api/review` | ✅ | README §6.5 |
| 盲测（异步） | `POST /api/blind-tests`、`/api/attempts/async`、`POST /:id/finish` | ✅ | README §6.5 |

## 8. 家长 / 运维

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 家长汇总 | `GET /api/parent/summary` | ✅ | README §6.6 |
| 提建议 / 导出 | `POST /api/suggestions`、`GET /api/suggestions`、`/export` | ✅ | 同上 |
| 部署自查 | `GET /api/health`（features）、`GET /v1/health`（capabilities） | ✅ | README §2.4、§3 |
| 清理某账号测试数据 | `web/scripts/cleanup-user-data.mjs` | ✅ | `english-coach/docs/deployment.md` §6.5 |

---

## 9. 变更同步清单（每次新功能必须过一遍）

新增/修改功能时，按顺序检查：

1. **接口**：`english-coach/docs/api-contract.md`（voice/契约）+ 若涉及 web 层，更新本仓库 `README.md` §6 与本文件
2. **页面/交互**：`docs/screens-matrix.md`（页面 × 接口 × 儿童差异）
3. **流程说明**：`docs/design-overview.md` §5（若新增业务流）
4. **迁移**：`english-coach/web/migrations/`（幂等；更新 README §3.2 迁移清单）
5. **配置**：`english-coach/deploy/.env.example` + 本仓库 README §3.3 变量表
6. **验收**：`english-coach/web/scripts/check-*.mjs` 加断言；必要时更新 `docs/acceptance-checklist.md`
7. **两端提示**：若影响移动端，更新 `ios/docs/*`、`hos/docs/*` 中对应页面/接口章节
8. **本文件**：把新功能登记到对应分组（状态 ✅/🔄/📋）
