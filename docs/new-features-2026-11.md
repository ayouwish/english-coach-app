# 2026-11 新能力 · 客户端对齐清单

> 后端（web/voice）在 2026-11 已上线以下能力。**Web 端已全部实现**；原生客户端（Android / HarmonyOS / iOS）
> 按本清单逐项对齐。接口细节以 [`screens-matrix.md`](screens-matrix.md)、`english-coach/docs/api-contract.md` 为准。
> 最后更新：2026-11-08

图例：✅ 已实现（Web） · 🟡 鸿蒙已实现（见 `hos/docs/build-verification.md`/相关提交） · ⬜ 待实现

---

## 1. 多家庭账号（`bdba3e7`）

| 能力 | 接口 / 页面 | Web | 客户端要求（鸿蒙/Android 待做，iOS 后续） |
|---|---|---|---|
| **受邀加入现有家庭** | `POST /api/auth/register`（`invite_code`） | ✅ | 注册页「🔑 受邀加入家庭」：邀请码 + 昵称 + 邮箱 + 密码；码无效/已用 → 可读提示 |
| **受邀创建新家庭（名额制）** | `POST /api/auth/register`（`new_family_code`） | ✅ | 注册页「🏠 受邀创建新家庭」：邀请码 + 家庭名 + 昵称 + 邮箱 + 密码 |
| **公开注册（默认关闭）** | `ALLOW_SELF_SIGNUP=0`；`GET /api/health.features.self_signup` | ✅ | 默认隐藏「创建家庭」入口；无码建家庭 → 403 `signup_disabled`（显示"未开放，请联系管理员"） |
| **家长邀请码（加入现有家庭）** | `GET /api/family/invite`、`POST .../rotate` | ✅ | 家长面板：码 + 「家长账号 N/3」；一次性；满 3 禁用重置 |
| **新家庭邀请名额（管理员）** | `GET/POST /api/family/family-invites` | ✅ | 家长面板「🏠 邀请新家庭」：剩余名额 N / 生成码（消耗 1）/ 最近码列表（已用/未用）；非管理员 → 403 `no_family_quota`（显示"名额 0 · 联系管理员"） |
| **家庭隔离** | 所有材料/打印/成员/汇总/建议接口 | ✅ | 无需特殊处理：跨家庭后端已 404；客户端按 404 显示"找不到" |

**规则**：每家庭最多 3 个家长账号（创建者 + 受邀 2）；邀请码一次性；孩子账号仍由家长创建。

## 2. 家庭成本核算（`c2c48f4` + voice `a382959`）

| 能力 | 接口 | Web | 客户端要求 |
|---|---|---|---|
| 本月成本 | `GET /api/cost/summary?month=YYYY-MM`（仅家长） | ✅ | 家长面板新增「💰 本月成本」：总额 + LLM/图片/TTS/ASR 分项 + 成员明细 + 近 7 天 |
| 儿童访问 | 同上 | — | 儿童调用 → 403，隐藏入口 |

## 3. 插画总开关（`b47e84b`）

`users.auto_illustrate` 语义升级为**插画功能总开关**（默认关）：

| 状态 | 行为 |
|---|---|
| 关 | 保存故事不自动画；**故事详情整块不渲染**（无标题/说明/按钮/占位）；`POST /api/story/:id/illustrate` → 403 `policy_disabled` |
| 开 | 手动可画 + 保存后自动画 |
| `capabilities.image=false` | 按钮禁用 + 「图片服务未配置」提示 |

客户端：设置页文案改「插画功能」；关闭时**不要渲染任何生成入口**（不是禁用）。

## 4. 盲测取消（`1b0d86c`）

| 能力 | 接口 | Web | 鸿蒙 |
|---|---|---|---|
| 取消进行中的盲测 | **`DELETE /api/blind-tests/:id`** | ✅ | 🟡 已实现调用（`b8724b5`） |
| 行为 | 进行中→200；重复→200 幂等；已完成→409 `already_finished`；他人→404 | — | 二次确认；取消后 `in_progress` 消失、不进周报；下次为全新一轮 |

## 5. 单词音标（`a300c19` 最终版）

| 能力 | 接口 | Web | 说明 |
|---|---|---|---|
| 点词看音标 | `GET /api/words/:word`、`GET /api/words?words=` | ✅ | **长按 450ms** 触发；浮层（词 + /音标/，**无发音按钮**）；无音标显示「暂无音标」；儿童同样可见；设置「单词显示音标」可关 |
| 服务能力 | `capabilities.word_ipa` | ✅ | — |

## 6. 跟读进步（`89f256a`）

| 能力 | 接口 | Web |
|---|---|---|
| 练习游标「继续上次」 | `GET/PUT /api/practice/cursor?scope=` | ✅ |
| 单句历史 + 进步曲线 | `GET /api/sentences/:id/attempts?limit=20` | ✅ 折线 + 首末对比 + 回放；儿童不显示数字分 |

## 7. 故事增强（`b815664`、`b03c759`、`b47e84b` 等）

| 能力 | 接口 / 页面 | Web |
|---|---|---|
| 原始输入回顾（中文原文 + 原声） | 故事详情；`/api/story/recordings/*` | ✅ **仅创建者可见**（英文正文家庭可见） |
| 故事句子数 | `POST /api/story/rewrite` 的 `max_sentences`（3–12，默认儿童 5/家长 8） | ✅ |
| 叙事时态 | `POST /api/story/rewrite` 的 `tense`（auto/past/present） | ✅ 默认过去时；`warnings:["tense_mismatch"]` |
| 整段朗读回放 | `GET /api/story/:id/audio/status` \\| `/audio` | ✅ 异步预生成 |
| 打印（整页 / A5 卡片 / 多选故事集） | `/story/[id]/print`、`/story/print?ids=` | ✅ 打印页仅在 Web（客户端可打开 URL 或后续自绘） |
| 场景随机性 / 自定义场景 | `POST /api/chat/sessions`、`/api/chat/scenarios` CRUD | ✅ |
| 连读汇总「再读一遍」 | 页面 `/flow` | ✅ |
| 对话整段回放 / 不限轮数 / 历史详情 | 见 screens-matrix §4 | ✅ |

## 8. 隐私模型（`84a9d20`，重要）

| 数据 | 可见范围 |
|---|---|
| 英文正文（故事） | **同家庭**可见 |
| 中文原文 / 原声 / 朗读记录 / 复述 / 整段回放 | **仅本人** |
| 对话 / 诊断 / 复习 / 练习游标 | 仅本人 |
| 成本 / 家庭成员 / 建议 | 本家庭（家长） |

客户端 **不要缓存其他家庭成员的原声/原文**；跨家庭一律 404。

---

## 8.5 自助修改密码（`3e5f0a1`-系列，2026-11-08）

| 能力 | 接口 / 页面 | Web |
|---|---|---|
| 修改我的密码 | `POST /api/auth/password` `{current_password,new_password}`；错误 401/400；成功后当前会话保留、其他会话失效 | ✅ 设置页「🔒 修改密码」 |
| 家长重置成员密码 | `POST /api/family/members/:id/password`（不要求旧密码） | ✅ 保留 |

客户端：设置页加「修改密码」（需当前密码）；儿童文案口语化但一样要当前密码；改完提示其他设备需重新登录。

## 9. 各端进度

| 端 | 状态 | 待办 |
|---|---|---|
| **Web** | ✅ 全部实现 | — |
| **HarmonyOS** | 大部分已实现；盲测取消已对接 | **新增**：注册页（受邀加入 / 受邀创建新家庭）、家长面板「新家庭邀请名额」卡、错误码 403 `signup_disabled`/`no_family_quota`；沿用：成本卡、插画总开关、隐私模型 |
| **Android** | 首版已落地（未编译验证） | 同鸿蒙：注册页两模式、家长面板邀请新家庭、错误码；并增补 `docs/android-feature-list.md` |
| **iOS** | M0 骨架 | 按本清单规划 M1+；注册/邀请码、成本、插画开关、盲测取消、音标长按 |

> 客户端接入时优先看 [`screens-matrix.md`](screens-matrix.md) 的「页面 × 接口」矩阵与本节接口；后端字段以
> `english-coach/docs/api-contract.md`（v1.20）为准。
