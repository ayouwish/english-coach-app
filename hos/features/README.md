# features/（HAR）· 业务模块

每个 feature 是一个独立 HAR，只暴露一个 `Index.ets`；`entry` 通过 `NavigationService`/路由表装配，不直接 import feature 内部实现。

## 模块

| 模块 | 页面 | 主要 API |
|---|---|---|
| `auth` | 登录、登出、修改密码 | `/auth/token`、`/auth/refresh`、`/auth/revoke`、`/auth/me`、`/family/members/:id/password` |
| `practice` | 跟读练习 | `/sentences`、`/attempts`、`/attempts/:id/retry`、`/tts`、`/audio/:id` |
| `flow` | 连读 | `/attempts/async`、`/attempts/status`、`/materials`、`/ocr`、`/tts` |
| `chat` | 场景/会话 | `/chat/scenarios`、`/chat/sessions`、`/chat/sessions/:id/messages`（`pron` 轮询）、`/asr`、`/tts`、`/audio/:id` |
| `story` | 故事/材料/插画/复述 | `/materials`、`/story/rewrite`、`/story/retell`、`/story/:id/illustrate`、`/ocr` |
| `blindtest` | 盲测/周报 | `/blind-tests`、`/attempts/async`、`/attempts/status` |
| `diagnosis` | 诊断/错音本 | `/diagnosis`、`/review`、`/sentences?focus=` |
| `parent` | 家长面板/成员/建议 | `/parent/summary`、`/family/members`、`/suggestions`、`/health` |
| `settings` | 设置/建议 | `/settings`、`/suggestions`、`/auth/revoke` |

## 标准布局

```text
features/<x>/
├── Index.ets                    # 唯一导出：路由注册/Builder
├── oh-package.json5
├── build-profile.json5
├── hvigorfile.ts
└── src/main/
    ├── module.json5
    ├── ets/
    │   ├── pages/               # 路由页面
    │   ├── components/          # 业务组件
    │   └── viewmodel/           # 页面 VM
    └── resources/base/element/
```

## 依赖规则

```text
features/<x> ──► commons/net, commons/audio, commons/storage,
                 commons/design, commons/model, commons/util
features/<x> ──✗──► features/<y>          # 不互相 import
features/<x> ──✗──► entry                 # 不反向依赖
```

- 跨 feature 跳转：用 `Routes` 常量 + `NavigationService.push()`。
- 共享 DTO：放 `commons/model`，不要复制一份。
- 页面只调用本模块 VM；VM 只调用本模块 Service / `commons/net`。
- 不要把录音/播放逻辑写进 feature；统一 `commons/audio`。

## 交付顺序

M0：`auth` + `practice` → M1：`flow` + `chat` → M2：`story` → M3：`blindtest` + `diagnosis` + `parent` + `settings`。

详细页面设计见 [`../docs/screens.md`](../docs/screens.md)。
