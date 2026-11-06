# ADR-0004 · 最低 iOS 26.0 复核 & 全量移植决策（2026-11-04）

- 状态：已决
- 关联：[ADR-0002](0002-min-ios-version-and-observation.md)（最低版本与 Observation 选型）、[ADR-0003](0003-bearer-token.md)（Bearer Token）
- 记录位置：`ios/docs/port-contract.md`、`ios/README.md` §0

## 背景

ADR-0002 在 2026-10-31 拍板「最低 iOS 26.0、只用 Observation 不写兼容分支」，依据是设备可控、长期维护。
本轮开工前需要确认两件事：① 最低版本是否维持；② 这一轮的实现范围（M0 之外还要不要继续）。

## 决策

1. **最低部署版本维持 iOS 26.0**（用户 2026-11-04 明确确认）。
   - 不做 17/18 兼容分支，不使用 `#available`（`check_ios.py` 把 `#available` 记为 ERROR）。
   - 理由：与 ADR-0002 一致；本机无编译器，避免「写了 compat 分支但无法验证」的隐性风险；iOS 26 已覆盖家庭现有设备。
2. **本轮范围 = 全量对齐 HOS**（不是只做 M0）：
   - 九大功能域、22 个路由、26 个根页面一次性落地，以 `hos/` 为功能事实来源，`ios/docs/screens.md` 为交互规格。
   - 用 `ios/docs/port-contract.md` 冻结分层、类型名、Service 签名与页面装配方式，支持多路并行开发。

## 影响

- 交付形态：**代码全量、验证有限**。本机（Windows）无 macOS/Xcode，只能做静态校验（`python ios/tools/check_ios.py`）；编译、真机、音频矩阵、Keychain 行为全部留待 Xcode 26 阶段验证。任何文档不得把静态校验写成「编译通过」。
- 若将来要支持 iOS 18：主要成本在 `@Observable` 之外的 API 收敛 + 重新引入 `#available` 分支 + 真机回归；届时需新开 ADR 并撤掉 checker 的 `#available` 禁用规则。
- 若家庭测试设备普遍低于 iOS 26：与本决策冲突，需先回到本 ADR 修改再动代码。

## 验证

- [x] 最低版本：用户确认 iOS 26.0（会话内决策，2026-11-04）。
- [x] 静态校验：`python ios/tools/check_ios.py` → `errors=0 warnings=0 files=146`。
- [ ] `xcodegen generate` + Xcode 26 编译（待 macOS 环境）。
- [ ] iOS 26 真机主链路验收（清单见 `README.md` §0.6）。
