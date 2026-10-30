# english-coach-app · 家庭英语教练 · 原生客户端

iOS 与 HarmonyOS（鸿蒙）客户端。**与后端仓库 [`english-coach`](../english-coach) 分离**——本仓库只放客户端工程与设计文档。

```
english-coach-app/
├── docs/                 # 跨端共享的设计文档（先读这里）
│   ├── design-overview.md        # 总设计：架构 / 认证 / 音频 / 错误 / 离线 / 里程碑
│   ├── design-tokens.md          # 设计令牌（颜色/圆角/字号），与 Web 端对齐
│   ├── backend-contract.md       # 移动端所需的【待后端新增】接口
│   ├── screens-matrix.md         # 页面 × 接口 × 双端对齐矩阵
│   └── adr/                      # 架构决策记录
│       └── 0001-auth-strategy.md
├── ios/                  # Swift/SwiftUI 客户端
│   ├── README.md
│   └── docs/{architecture,audio,screens,design-system,roadmap,open-questions}.md
└── hos/                  # HarmonyOS（ArkTS/ArkUI）客户端
    ├── README.md
    └── docs/{architecture,audio,screens,design-system,permissions-and-privacy,roadmap,open-questions}.md
```

## 现状

| 部分 | 状态 |
|---|---|
| 后端（web + voice）| ✅ 已实现并部署（家庭 NAS，HTTPS，局域网）|
| 跨端设计文档 | ✅ 本仓库 `docs/` |
| iOS 工程 | 📋 设计文档就绪，待开工 |
| HarmonyOS 工程 | 📋 设计文档就绪，待开工 |

## 客户端不做的事（边界）

- **不直连** `voice`（8100）——所有 AI 能力经 `web`（3000）的 `/api/*` 代理，客户端只认一个 base URL
- **不存放任何 API Key**（Azure / DeepSeek / 智谱 全在服务端）
- **不本地做语音识别/评测/合成**（那是服务端的活，客户端负责录音、上传、播放）

## 快速开始（给实现者）

1. 读 `docs/design-overview.md`（10 分钟）
2. 读 `docs/design-tokens.md`（视觉一致性）
3. 读对应平台目录：`ios/README.md` 或 `hos/README.md`
4. 按 `docs/screens-matrix.md` 逐页对齐接口与状态
5. 按平台 `docs/roadmap.md` 的 M0 → M4 推进

## 后端仓库

[`english-coach`](../english-coach)：Next.js web + FastAPI voice + 部署编排 + 验收脚本。
移动端接口以该仓库的 `docs/api-contract.md` 为唯一事实来源（本仓库只做引用与补充）。
