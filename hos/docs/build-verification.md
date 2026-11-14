# 构建验证记录（M0）

> 本文件只记录**实际执行过**的构建，不写"应该可以"。真机行为不在本文件范围。

## HOTFIX — 2026-11-05 · 图标提交误删权限 / 对话页布局

1. **启动报「连不上家庭 NAS」**（网络正常、web 可访问）：
   图标提交（674b495）重写 `entry/src/main/module.json5` 时把整段 `requestPermissions`
   覆盖丢了 → 所有 HTTP 请求 `Permission denied` → `network_unreachable`。
   已恢复 `ohos.permission.INTERNET` + `ohos.permission.MICROPHONE`；
   `Index` 错误页新增「诊断：错误码 · baseUrl」，hilog 输出 `Bootstrap` 错误详情。
   真机验证：重装后直接进入首页（爸爸，今日 5.5/30 分钟）✅
2. **对话页布局**：`NavDestination` 系统标题与页面自带 TopBar 重复 → 对话页 `.hideTitleBar(true)`，
   只保留「返回 + 场景名 + 结束」一行。
3. **第一句没有中文**：服务端 greeting 的 `text_zh` 为 null；新增
   `core/content/ChatOpeningZh.ets`（19 个内置场景开场白中文对照，自定义场景回退为空）。
   真机验证：`Any plans for the weekend?` → 「周末有什么安排吗？」✅
4. **启动错误页不再死胡同**：原来只有「重试」，现在增加
   - 「⚙️ 修改服务器地址」：错误页内联输入 + 保存并重试（自动规范化 `http(s)://`、去尾 `/`、去 `/api`）
   - 「先去登录页」：登录页有完整的地址编辑与健康检查
   - 诊断行显示错误码与当前 baseUrl
5. **同步上游 v0.21 语义**：
   - 故事隐私：英文正文家庭可见；中文原文仅创建者；原声/复述按 `userId#materialId` 隔离；
     整段朗读缓存 `story_<id>_read_<userId>.wav`（两人读同一篇不再互相覆盖）
   - 连读默认来源：从故事「开始朗读」读完回连读 Tab → 重置为「语料」默认
   - 点词音标：支持长按（约 450ms）与点击两种方式（对齐 web 长按）

### 第 15/16 轮真机复验（2026-11-05，爸爸账号）

| 项 | 结果 |
| --- | --- |
| 跟读页「📈 历史」 | ✅ 9 次记录，首末 89→92 +2.7，逐条可回放 |
| 连读默认来源 | ✅ 进入连读显示「从语料选」+ 200 句（截图 r15_flow） |
| 连读「‹ 重新选句」 | ✅ 运行中点击后（无进度）立即回 setup |
| 对话会话 | ✅ 单层标题、开场白中文「周末有什么安排吗？」 |
| 故事隐私（爸爸看兜兜的故事） | ✅ 无中文原文入口、无整段回放；爸爸自己的故事有「🗒️ 看看你当时怎么讲的」 |
| 诊断「🧾 最近练习记录」 | ✅ 20 条列表、分数 68/88/84、▶ 回放 |
| 点词音标长按 | ✅ `learning /ˈlɜːrnɪŋ/`（截图 r25_longpress） |
| 设置 PATCH | ✅ 已保存 ✅（第 14 轮已验） |
| 跟读全屏详细结果 | ✅ 用「历史朗读 → 详情」从 `/attempts` 还原：91.9 分/雷达图居中/能力 97·100·100·81.3/F0 双曲线/点评 why-how/纠错；历史 attempt 无逐词数据，逐词区自动隐藏；真实录音后完整逐词待补测 |
| 历史朗读「详情」 | ✅ 不需要重新录音即可看历史 attempt 的完整结果（新增功能） |
| 设置页选项点选 | ✅ 性别/句子数/纠正强度等 ForEach 选项 key 带选中值后，点击「女孩」正确变紫选中 |
| 故事列表左划删除 | ✅ 左划露出正常行高「删除」按钮，二次确认后调 DELETE /materials/:id |
| 打印 A4/A5 真机 | ✅ 故事详情「🖨️ 打印」→ 选 A5 卡片 → 系统打印面板**正常预览卡片**（不再「文件格式不支持」）；设备生成的 `*_card.pdf`：pypdf 解析 1 页 A5（419.53×595.28）、内嵌 874×1240 JPEG，导出图含虚线框/编号句子/中文/姓名日期栏 || 打印 PDF（文件级验证） | ✅ 从设备拉取 App 生成的 `story_*.pdf`：pypdf 解析 1 页 A4、内嵌 1240×1754 JPEG（DCTDecode），导出图片内容正确（标题/正文/页脚） |
| 跟读「换一批」 | ✅ 根因：按钮被等级行挤到屏幕外（只剩 4px 可点）+ 重拉仍是同一顺序；已移到页面底部并加 Fisher–Yates 洗牌。真机验证：点后句子从「我学英语已经大约三年了」变为「我学抛接球已经学好几个星期了」 |
| 等级 tab | ✅ 改为按服务端语料动态生成；线上语料仍只有 A1–B2（600 句），补 C1/C2 后自动出现；账号 CEFR 映射已支持 C1/C2 |
| 新家庭邀请码（后台管理员） | ✅ 后端 `d8ed8ac` 后家庭端 `/family/family-invites` 移除；HOS 删除家长面板「邀请新家庭」卡及相关调用。真机验证：家长面板只剩「家庭邀请码（共同家长）」，无「邀请新家庭」卡；注册页仍支持「受邀创建新家庭」（码由后台管理员 `/admin` 生成） |
| 多家庭注册/邀请码（真机） | ✅ 登录页「受邀加入 / 受邀创建家庭」入口；注册页「受邀加入家庭 / 受邀创建新家庭」切换、字段正常；家长面板「家庭邀请码」显示「我家 / DEFAULT1 / 家长 2/3」，复制成功 |
| 盲测取消 | ⏳ 客户端已加「取消这轮盲测」并尝试 DELETE /blind-tests/:id → /cancel → /abandon；线上探测全部 404，需后端发布取消接口 |
| 真实录音（PC 扬声器播放 TTS 让平板麦克风拾音） | ⚠️ 服务端当前 `provider_unavailable: PA provider 不可用（azure 未配置）`，App 正确展示「评测服务暂时不可用，录音和文本已经保存，稍后可重试」+「重试评测」；逐词/音素数据待服务端恢复后补验 |



## V1 — 2026-11-02 · DevEco Studio 6.1.1.300 · `assembleHap` 通过

### 环境（本机实测）

| 项 | 值 |
|---|---|
| OS | Windows 10/11 x64 |
| DevEco Studio | 6.1.1.300（build `DS-243.24978.46.36.611300`），安装于 `F:\Program Files\DevEco Studio` |
| hvigor | 6.24.4（DevEco 自带 `tools/hvigor`） |
| Node | v18.20.1（DevEco 自带 `tools/node`） |
| Java | DevEco 自带 JBR（`tools/../jbr`，打包任务需要 `spawn java`） |
| HarmonyOS SDK | 6.1.1 / API 24（DevEco 自带 `sdk/default`，`compileSdkVersion` 实际取 `6.1.1.125`） |
| 工程声明 | `compatibleSdkVersion` / `targetSdkVersion` = `"6.0.0(20)"`（设计文档的 API 20 基线） |
| 签名 | **无**（`signingConfigs: []`，由 DevEco 自动生成；本次产物为 unsigned） |

### 执行命令

DevEco 6.1.1 的工程**不需要**手写 `hvigorw` / `hvigorw.bat` / `hvigor/hvigor-wrapper.js`
（新建工程也不再生成它们，IDE 直接用自带 hvigor）。命令行等价调用：

```powershell
$de = "F:\Program Files\DevEco Studio"
$env:DEVECO_SDK_HOME = "$de\sdk"
$env:NODE_HOME      = "$de\tools\node"
$env:JAVA_HOME      = "$de\jbr"
$env:PATH = "$de\tools\node;$de\jbr\bin;$de\tools\ohpm\bin;$env:PATH"

# 在 hos/ 目录下
& "$de\tools\node\node.exe" "$de\tools\hvigor\bin\hvigorw.js" `
    assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

> 说明：在 GUI 里等价于 File → Sync Project with hvigor，然后 Build → Build Hap(s)。

### 结果

```text
> hvigor Finished :entry:default@CompileArkTS...
> hvigor Finished :entry:default@PackageHap...
> hvigor WARN: No signingConfig found for product default
> hvigor BUILD SUCCESSFUL in 19 s 584 ms
```

- 干净重建（删除 `entry/build`、`build`、`.hvigor` 后）通过，非增量侥幸。
- 产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（523,801 bytes）+ `pack.info`。
- ArkTS 编译：**0 error**，16 warning（见下）。
- `ohpm install`：`install completed in 0s 50ms`（零第三方依赖，不生成 `oh-package-lock.json5`）。

### 产物元数据（解包 HAP 的 `module.json` / `pack.info` 实测）

| 字段 | 实测值 | 含义 |
|---|---|---|
| `app.bundleName` | `com.family.englishcoach` | 与 `AppScope/app.json5` 一致 |
| `app.versionCode` / `versionName` | `1000000` / `0.1.0` | 与 `AppScope/app.json5` 一致 |
| `app.compileSdkType` | `HarmonyOS` | 用 HarmonyOS 6.1.1 SDK 编译 |
| `app.compileSdkVersion` | `6.1.1.125` | 编译期 SDK = DevEco 自带 API 24 |
| `app.minAPIVersion` | `60000020`（API 20） | `compatibleSdkVersion` 生效 |
| `app.targetAPIVersion` | `60000020`（API 20） | `targetSdkVersion` 生效 |
| `pack.info` `apiVersion` | `compatible: 20, target: 20` | 同上 |
| `requestPermissions` | `ohos.permission.INTERNET`、`ohos.permission.MICROPHONE`（含 reason/usedScene） | 与 `module.json5` 一致 |
| `deviceTypes` | `phone`, `tablet` | 与 `module.json5` 一致 |
| `buildMode` / `debug` | `debug` / `true` | 本次为 debug 构建 |

### 本次初始化中修掉的编译错误（5 类，10 条报错）

| # | 文件 | 错误 | 处理 |
|---|---|---|---|
| 1 | `entry/src/main/ets/core/service/PracticeService.ets:21` | `arkts-no-untyped-obj-literals`：`Record<string, string>` 对象字面量 | 查询参数统一改为 `Map<string, string>`（`ApiClient` 的 `query` / `getJson` / `buildUrl` 一并改） |
| 2 | `entry/src/main/ets/core/net/TokenSession.ets:36,37,74,78` | `Duplicate identifier 'accessExpiresAt' / 'refreshExpiresAt'`（静态字段与静态方法同名） | 字段改名 `accessExpAt` / `refreshExpAt`，对外方法名不变 |
| 3 | `entry/src/main/ets/core/net/TokenSession.ets:158` | `asset.update` 需要 2 个参数 | 改为 `asset.update(queryMap, updateMap)`（SDK `.d.ts` 实测签名） |
| 4 | `entry/src/main/ets/components/EcButton.ets:64` | `borderWidth` 与 `CustomComponent`/`CommonAttribute` 同名成员冲突 | 私有方法改名 `ghostBorderWidth()` |
| 5 | `build-profile.json5:10-12` | `compileSdkVersion`/`compatibleSdkVersion` 在 `runtimeOS: HarmonyOS` 下必须是字符串 | 改为 `"6.0.0(20)"`，并去掉裸数字写法 |
| 6 | `oh-package.json5` / `hvigor/hvigor-config.json5` | `modelVersion: "6.0.0"` 与 hvigor 6.24.4 不匹配（schema/wrapper 版本） | 改为 `"6.1.1"`（本机 MattermostHarmony 工程同值） |

### 构建告警（不阻塞）

16 条 `ArkTS:WARN`，分两类，均不影响出包：

1. `Function may throw exceptions. Special handling is required.` —— 出现在 `FileUtil`（同步 `fileIo`）、
   `AppConfig`（Preferences 同步读）、`AudioRecorder` 的同步调用上。属于 ArkTS 对"可能抛异常的同步 API"的提示；
   现有代码用 `try/catch` 包裹的是异步调用，后续（M1）可按需把同步 IO 收进 try 或改异步 API。
2. `To use this API, you need to apply for the permissions: ohos.permission.MICROPHONE` ——
   `module.json5` 已声明该 user_grant 权限，运行时仍需在首次录音前动态申请（代码已实现）。

### 仍未验证（本次不做承诺）

- [x] 签名与安装：**2026-11-03 已完成**（见下方 V2；签名由 DevEco 自动签名生成，`hdc install` 成功）；
- [x] 真机启动：**2026-11-03 已完成**（MatePad Pro，登录页渲染成功，见 V2）；页面跳转、`Navigation` 行为仍未验证；
- [ ] AVRecorder 实际产出（16kHz/单声道/65kbps/m4a）与 AVPlayer `fd://` 播放；
- [ ] Asset Store Kit 读写与降级分支、单飞刷新的真实并发行为；
- [ ] 服务端联调（`/auth/token`、`/attempts`、`/tts` 等，见 README §2 状态标注）；
- [ ] release 构建与混淆、深色模式、平板布局、无障碍字号放大。

> 结论边界：V1 只证明"工程配置正确 + ArkTS 全量编译通过 + 能打 unsigned HAP"，
> **不等于**"App 可用"。真机可用必须以 README §0.1.7 的验收记录为准。

---

## V2 — 2026-11-03 · 自动签名 + 安装到真机 + 启动

### 设备与环境

| 项 | 值 |
|---|---|
| 设备 | **HUAWEI MatePad Pro**（`const.product.devicetype=tablet`），USB 连接，hdc target `2BD0223923005246` |
| 系统 | `OpenHarmony-6.1.1.120`，**API 24**，UDID `165C70B1…AE4B360F` |
| 签名 | DevEco **自动签名**（本机 `C:\Users\wangsimeng\.ohos\config\default_hos_82Nw…{.p12,.cer,.p7b}`）：`type=debug`，`device-ids` 含本机 UDID，有效期 2026-11-02 ~ 2027-11-02 |
| 工程声明 | `bundleName = top.dreamsearch.english.coach`；`compatibleSdkVersion` / `targetSdkVersion` = `"6.1.1(24)"`（2026-11-03 调整，见下） |

> **bundleName 与 profile 必须一致**：这份自动签名 profile 的 `bundle-name` 是
> `top.dreamsearch.english.coach`（09:27 UTC 生成，含本机 UDID），所以 `AppScope/app.json5`
> 已改为同名；换 bundleName 就必须重新让 DevEco 生成签名。
>
> **API 基线变化**：设计文档写的是最低 API 20（HarmonyOS 6.0.0），但本机只有 API 24 SDK、
> 自动签名 profile 也基于该设备；当前 `compatibleSdkVersion`/`targetSdkVersion` 已临时改为
> `"6.1.1(24)"`（HAP 内 `minAPIVersion=60101024`）。若要让 API 20 设备也能装，
> 改回 `"6.0.0(20)"` 重新构建即可（编译期仍用 SDK 24，实测可行，见 V1）。

### 命令

```powershell
# 1) 构建签名包（signingConfigs 由 DevEco 自动写入 build-profile.json5，product 引用 signingConfig: "default"）
& "$de\tools\node\node.exe" "$de\tools\hvigor\bin\hvigorw.js" assembleHap `
    --mode module -p product=default -p buildMode=debug --no-daemon

# 2) 安装
& "$de\sdk\default\openharmony\toolchains\hdc.exe" -t 2BD0223923005246 `
    install -r entry\build\default\outputs\default\entry-default-signed.hap

# 3) 启动
& hdc -t 2BD0223923005246 shell "aa start -a EntryAbility -b top.dreamsearch.english.coach"
```

### 结果

- `:entry:default@SignHap` 通过 → `entry-default-signed.hap`（**561,417 bytes**）；
- `hdc install -r` → `install bundle successfully`（`bm dump` 可见 `appProvisionType: "debug"`，
  `apiCompatibleVersion/apiTargetVersion = 60101024`）；
- `aa start` → `start ability successfully`，`ps -ef` 可见进程 `top.dreamsearch.english.coach`（pid 28651）；
- `uitest dumpLayout` 导出的界面树包含：`English Coach`、`家庭英语口语教练`、`服务器地址`、
  `https://english.dreamsearch.top`、**`家庭 NAS 已连接`**、`重试`、`dad@example.com`、`安全键盘`
  → **登录页已真实渲染**，且启动时 `/api/health` 请求成功（连通家庭 NAS）；
- 屏幕截图（2880×1920，`snapshot_display` 导出）见本机 `F:\code\dsh-workspace\ec-home.jpeg`。

### V2 仍未验证

- [ ] 登录提交（未输入账号密码）、登录后语料列表/跟读/设置页的跳转；
- [ ] 录音权限弹窗、录音、上传评测、TTS 播放；
- [ ] Asset Store 读写与降级、单飞刷新并发行为；
- [ ] release 构建、深色模式、系统字体放大、冷启动耗时。

---

## V3 — 2026-11-03 · v0.6 全功能扩展 + 播放修复（真机）

### 构建

- 干净重建（删除 `entry/build`、`build`、`.hvigor` 后）：**BUILD SUCCESSFUL in 28 s**；
  产物 `entry-default-signed.hap` **3,229,586 bytes**（debug、未混淆）。
- 工程结构升级为 `HomeTabs`（跟读 / 连读 / 对话 / 故事 / 我的）+ `Navigation` 二级页，
  新增 6 个 service、5 个 DTO 文件、5 个 VM、20 个页面；4 个模块由并行子代理实现，
  各自在合并前跑过 `assembleHap` BUILD SUCCESSFUL，集成后 Lead 全量 clean build 再次通过。

### 播放修复（用户反馈「没办法播放」）

`AudioPlayer` 从「`url` 赋值后立刻同步 `prepare()`」改为**状态机**：

```
url='fd://'+fd → stateChange(initialized) → 设置 audioRendererInfo → prepare()
→ stateChange(prepared) → play() → stateChange(completed) → release()
```

- 真机实测：点「🔊 听示范」→ 按钮变「播放中…」→ 约 3 秒后自动恢复「🔊 听示范」，
  证明下载 TTS → prepare → play → completed → 释放 fd 全链路走通；每步打 hilog（tag=Audio）。
- **待人工确认**：音量与音频路由（扬声器/蓝牙）需人耳复核。

### 结果页丰富度（对齐 web）

真机实测一条评测（总分 91.2 / 准确 97 / 流利 100 / 完整 100 / 语调 80）渲染出：
总分圆环、四项子分条、逐词评分（低分置顶）、issues 前 2 条、语调 F0 双条带 + DTW 差距 0.42、
「我听到的是…」、「这一句的进步（最近 2 次）」柱状、回放录音 / 重试评测 / 下一句。

### 其它真机验证

- `hdc install -r` → `install bundle successfully`；`aa start` → 进程存活。
- 登录失败分支：错误密码 → 401 `bad_request`，页面正确显示「邮箱或密码不正确」。

### 记住密码（用户 2026-11-03 要求的基础能力）

- 登录页新增「记住密码」开关（默认开），登录成功后把邮箱+密码写入 **Asset Store**
  （`core/session/CredentialStore.ets`，alias `ec_saved_login`，`SYNC_TYPE=NEVER`）；
- 冷启动无 token 时自动用记住的账号**静默登录**一次；密码失效（401 `bad_request`）会清掉记住的密码并停在表单；
- 主动退出登录**保留**记住的密码，但本次进程内不再自动登录（`CredentialStore.markLoggedOut()`）；
- Asset Store 不可用时不降级为明文：`save()` 返回 false，页面提示「本机安全存储不可用，密码没有保存」；
- 构建：BUILD SUCCESSFUL in 24 s 190 ms，已 `hdc install -r` 安装到平板。

### 故事插画显示修复（2026-11-03，用户反馈「故事页面的插图显示不对」）

- 线上插画实测：`GET /api/materials/:id/image` → 200 `image/png`，**1280×1280 正方形**（1.03MB）；
- 客户端原用 `ImageFit.Cover` + 固定高度 230 渲染 → 正方形图只露出中间一条横带；
  改为 `ImageFit.Contain` + 高度 340 + 浅色留边，完整显示；
- 原实现「无图故事进详情自动画一张」（每张约 ¥0.1、10–30s）已移除，
  改为必须用户点「🖼️ 给我画一张」——与 Web 行为一致，也避免打开即扣费；
- 构建：BUILD SUCCESSFUL（18 s 333 ms），已安装；真机截图待解锁后补。

### 跟读卡片手势修复（2026-11-03，用户反馈「上滑下滑划不动」）

- 原因：卡片内容外面套了纵向 `Scroll`，垂直手势被内层 Scroll 全部消费，外层 `Swiper(vertical)` 收不到；
- 修复：卡片改为**不滚动**的固定布局（句子 + 三个按钮 + 紧凑结果 + 3 个操作按钮），
  逐词评分/音素问题/语调曲线/进步历史/重试评测移到 `bindSheet` 底部弹层「详细结果」；
- 构建：BUILD SUCCESSFUL（17 s 686 ms），已 `hdc install -r`；
- 真机验证：需解锁后手动上滑/下滑确认（当前平板锁屏，脚本无法自动验证手势）。

### 故事「重新生成整段朗读」加固（2026-11-04）

服务端对**没有任何朗读录音**的故事也返回 `status:"failed"` + error（`attempt_count:0`），
App 之前会照常渲染「🔄 重新生成整段朗读」；点它会对空故事触发强制拼接，体验差且用户反馈闪退。

修复：

- `checkAudio`：`failed && attempt_count===0` → 按 `no_audio` 处理，不再显示「重新生成」按钮，
  文案改为「先读一遍这个故事，才能听整段朗读哦」；
- `retryAudio`：入口校验 storyId、清空错误、全程 try/catch + hilog，避免任何异常逃逸；
- 真机验证（儿童账号 兜兜）：打开未读过故事的详情 → 朗读卡只显示「先读一遍这个故事…」，无「重新生成」按钮 ✅

### 真机验证（2026-11-04 凌晨，v0.19/v0.20 功能）

1. **故事朗读**：故事详情点「开始朗读」→ 连读 Tab 显示 `📖 My Morning Story`、`第 1 / 12 句`，可逐句录音 ✅
2. **点词音标**：故事正文点 `Hello` → 弹窗 `Hello /həˈləʊ/ 其它读音：/həˈləʊ/ ［知道了］`（截图 `verify/ipa_shot.jpeg`）✅
3. **设置 PATCH**：设置页「保存设置」→ `已保存 ✅`（HarmonyOS http 支持 PATCH，无需兜底）✅
4. **单词显示音标开关**：设置页已显示「🔤 单词显示音标」+ 说明 ✅
5. **练习游标横幅**：「上次练到第 2 句（共 200 句）· ▶ 继续上次 / 从头开始」✅
6. 故事插画：详情页 Image 渲染正常（1:1，不再被裁成横条）✅

**仍需真人操作验证**：跟读评分后的全屏详细结果（雷达/F0/逐词/纠错卡）需要真实录音数据。

### 故事「开始朗读」跳回问题修复（2026-11-04）

现象：故事详情点「开始朗读」后只是返回/停在故事页，没有进入连读 reading。

根因：`readAloud()` 只做了 `tab_index=1 + NavigationService.clear()`，但：

1. `HomeTabs` 重建时没有按 `tab_index` 初始化（Tabs 初始 index 恒为 0）；
2. `FlowPage` 重建时 `aboutToAppear` 先 `vm.init()` 把状态重置回 setup，即使已有故事朗读请求/正在运行。

修复：

- `HomeTabs`：`aboutToAppear` 按 `pendingTab` 初始化 `current`，`Tabs` 显式传 `index: this.current`；
- `FlowPage`：`aboutToAppear` 先消费 `StoryReadRequest`（有请求就直接进入 running，不再 init）；
  若 `FlowPhase.RUNNING` 且已有 items，则 `resume()` 而不是重置；
- 真机验证：故事详情点「开始朗读」→ 切到连读 Tab，显示 `📖 My Morning Story`、`第 1 / 12 句` ✅

另外本轮同步/补齐的 v0.19–v0.20 功能：

- **点单词看音标**（跟读/连读/故事正文）：`GET /api/words/:word`，浮层只显示 `/ipa/`（无发音按钮），
  设置新增「单词显示音标」开关（`show_word_ipa`，默认开）；实测接口 `think → θɪŋk`、未知词 404；
- **故事时态修正**：`/story/rewrite` 带 `tense=auto`，`warnings:["tense_mismatch"]` 显示可读提示；
- **故事预览直接「讲给我听」**：生成后自动保存并跳复述页（不用先进详情页）；
- **练习游标横幅**：进入跟读显示「上次练到第 N 句」+「▶ 继续上次 / 从头开始」。

### 真机验证（2026-11-03 晚，MatePad Pro 2BD0223923005246，含两个真实 bug 修复）

**已验证通过：**

1. **自动登录/安全存储修复**：登录页曾显示「本机安全存储不可用」（Asset Store 降级），根因是
   **读失败被误判为降级 → 之后所有写操作直接跳过**，导致 token/密码永远存不住。
   修复：读失败不再降级；写依次 `update → add(完整) → add(最小属性)`，仅真正写失败才降级；
   错误码显示在登录页；新增 `AssetProbe` add→query→remove 自检。
   真机结果：登录一次后 **杀进程重开直接进首页**，重装（install -r）后也直接进入首页 ✅
2. **盲测周报 JS 崩溃修复**：`BlindTestPage.dateText()` 对 null 调 `.length` →
   `TypeError: Cannot read property length of null`（jscrash 日志确认）。修复后页面正常打开 ✅
3. 5 个 Tab 全部真实数据：跟读 1/200、连读 setup、对话 8 场景、故事 8 篇、我的入口正常 ✅
4. 二级页：设置 / 音色 / 我的形象 / 发音诊断 / 错音本 / 盲测 / 家长面板 / 家庭成员 / 建议箱 / 服务状态 均正常打开 ✅
5. **故事详情**：插画生成成功（✅ 已生成 + Image 渲染）、改名/删除/复制全文/朗读本故事/复述入口齐全 ✅
6. **故事朗读**：点「开始朗读」→ 切到连读 Tab，标题 `📖 My Morning Story`，12 句逐句 running ✅
7. **跟读上下滑动**：fling 后 `1/200 → 2/200`，句子切换正常 ✅

**待补测（设备掉线中断）：** 设置页 PATCH 保存（滚到底部找保存按钮）、跟读录音后的全屏详细结果
（需要真人录一句才能出结果页）、数据库/缓存清理、退出登录。

### 复制全文/一键复制 + 能力开关隐藏入口（2026-11-03）

- 新增 `core/util/ClipboardUtil.ets`（pasteboard 纯文本复制）：
  故事详情「复制全文」（替代 Web 的打印/分享）、建议导出「一键复制 Markdown」；
- 新增 `core/content/CapabilityCache.ets`（`GET /api/health` 能力缓存）：
  `voice.capabilities.image=false` 时隐藏「给我画一张/换一张」并显示「插画服务未启用」；
  `auto_illustrate` 自动画图也会先检查该能力；
- 补齐 `HealthCapabilitiesDto` 的 image/avatar_presets/audio_concat 等字段；
- 构建：BUILD SUCCESSFUL（22.5s）；设备 USB 离线，未安装验证。

### 故事改名/删除 + 历史列表顺序（2026-11-03）

- 故事详情页新增「改名 / 删除」（仅成人可见；儿童不显示，服务端也会 403）：
  改名走 `PATCH /materials/:id {title}`（行内输入 + 保存/取消），删除走 `DELETE /materials/:id`（二次确认后返回故事集）；
- 跟读详细结果的「这一句的历史」列表改为**新→旧**（与 Web 一致；折线仍按旧→新）；
- 构建：BUILD SUCCESSFUL（17 s 457 ms）；设备 USB 离线，未安装验证。

### 连读汇总「听鼓励」+ 书页编辑保存面板（2026-11-03）

- 连读汇总页鼓励语支持 **中→英顺序播放**（`POST /tts` zh-CN 慢速 → en-US 正常，`AudioController` 顺序播放；
  语音不可用时只提示「文字照常看」，不影响文字展示）；对应 Web 的「有声音就播、被拦截就显示听鼓励按钮」；
- 修复「我的书页 → 编辑」时保存面板不显示的问题（编辑态在「自己输入」Tab 内显示保存/取消面板，
  保存走 `PATCH /materials/:id`）；
- 把 `AlertDialog.show`（API 24 已标记 deprecated）换成 `this.getUIContext().showAlertDialog(...)`；
- 构建：BUILD SUCCESSFUL（17s）。

### 账号偏好接入（2026-11-03）

新增 `core/content/AccountPrefs.ets`（进程内缓存一次 `GET /api/settings`）：

- 跟读示范音/「跟我读」优先使用账号偏好 `ttsVoice`，语速用 `ttsRate`（儿童仍默认 slow）；
- 故事改写默认句数优先用账号偏好 `story_sentences`（3–12），否则儿童 5 / 成人 8；
- `auto_illustrate=true` 时保存故事后按 Web 行为自动画一张（失败静默，详情页仍可手动重画）；
- 设置页/音色页保存成功后 `AccountPrefs.reload()`，无需重启 App 生效；
- 干净重建：BUILD SUCCESSFUL（26.5s），HAP 3,594,247 bytes。

### 书页编辑/删除 + 练习游标 + 故事读完可复述（2026-11-03，设备离线时的补齐）

- **我的书页**：列表每行新增「编辑 / 删除」，编辑会读 `GET /materials/:id` 把文本灌进「自己输入」，
  保存走 `PATCH /materials/:id`（标题+正文），删除走 `DELETE /materials/:id`（`AlertDialog` 二次确认）；
- **练习游标**：服务端 `/api/practice/cursor` 未部署，客户端用 Preferences 记 `practice_cursor_<level>`
  （上次读到哪一句），进跟读页自动定位，符合 Web「继续上次」的体验；
- **故事读完可复述**：连读汇总页若本批来自故事（`runMaterialId` 非空）会显示「📝 复述这个故事」，
  跳转故事复述页，形成「生成→朗读→复述」闭环；
- 构建：BUILD SUCCESSFUL（17 s 746 ms）；设备 USB 离线，未安装验证。

### 跟读「详细结果」全屏详情 + 故事朗读入口（2026-11-03，用户反馈「浮窗信息太少」）

按 Web 结果页（`PracticeClient`/`ResultSections`）的信息密度重做「详细结果」，从 bottom sheet 改为
`bindContentCover` 全屏页，包含 8 个区块：

1. **这一句的问题**：issues 去重后的音素 chips（/θ/ 41 这类）+「最需要练的是…」；
2. **这一句的历史**：`SparkLine` 折线 + 首末对比（80.3 → 82.4 (+2.1)）+ 逐条日期/分数/▶ 回放（`GET /audio/:attemptId`）；
3. **本次评分**：综合分圆环 + 准确/流利/完整/节奏四项条 + 识别结果/参考文本 + provider/粒度/时长/记录 id；
4. **整体点评**：summary/praise + 每条点评的「为什么/怎么改/练习词」；
5. **能力多边形**：`RadarChart`（自绘 Path，null 轴不参与并标 —）+「最需要练的是 节奏 x」；
6. **逐词得分**：需要练的词（<60 升序）+ 句子顺序进度条 + 音素明细 chips；
7. **语调对比（F0 双曲线）**：`PitchChart`（用户实线/示范虚线、Hz 轴、DTW 说明、最差区间文案）；
8. **需要纠正的地方**：issue 卡片（标题/单词/音素 expected→actual/分数/为什么/怎么改/练习词），
   hint 文案来自新增 `core/content/PhonemeHints.ets`（与 Web `lib/hints.ts` 18 个键对齐）。

新增组件：`components/Charts.ets`（RadarChart / PitchChart / SparkLine，纯 Path 自绘，无三方库）。

故事「转换成英文后要读」：

- 故事改写预览页新增「🎤 朗读这个故事（连读）」按钮（**不必先保存**）；
- 故事详情页新增「📖 朗读这个故事 / 开始朗读」卡片；
- 点击后设置 `StoryReadRequest` 并切到「连读」Tab，用故事句子逐句录音评分（提交带 `source=custom`，
  已保存故事带 `material_id`），读完后汇总页可做复述。
- 构建：BUILD SUCCESSFUL（18 s 219 ms）；设备 USB 离线，尚未安装验证。

### 录音「不要了/取消」按钮（2026-11-03，对齐 Web Recorder）

Web 的 `components/Recorder.tsx` 有「✖️ 不要了（取消这次录音）」；HarmonyOS 端补齐：

- 跟读卡片（含盲测模式）：录音中显示「⏹ 说完啦」+「✖️ 不要了」，取消会删掉本地录音、不提交评测；
- 连读模式：录音中同样出现「不要了」；
- 对话/故事录音页面原本已有「不要了」，语义一致（`AudioController.cancelRecording()` → 删除文件 + 释放麦克风）。
- 构建：BUILD SUCCESSFUL（18 s 648 ms）；设备 USB 离线，尚未安装验证。

### 自动登录与凭证持久化（2026-11-03，用户反馈「每次都要输密码」）

排查结论：**开发期反复 `hdc install -r` 会清空 App 沙箱数据**，而 access/refresh token 与「记住密码」
都存在 App 私有存储（Asset Store）里，所以每次重装都会回到登录页；正常杀进程/重启 App 不需要重新登录。

本轮加固：

- `TokenSession` / `CredentialStore` 的 `asset.add` 失败时，**去掉 `ACCESSIBILITY`/`SYNC_TYPE` 再试一次**
  （部分机型对组合属性报错会导致直接降级为内存模式 → 每次启动都要登录）；
- 即使密码无法安全保存，也会把**邮箱**记在普通 Preferences（`saved_email`），登录页至少预填邮箱；
- 登录页在存储降级时显示黄色提示「本机安全存储不可用：登录状态与密码无法持久保存…」；
- 自动登录期间显示「正在用记住的账号自动登录…」；
- 冷启动顺序：先 `SessionStore.restore()`（有 refresh token 就直接进首页）→ 没有 token 才用记住的账号静默登录。

### 盲测端到端（2026-11-03 补）

- 「我的 → 盲测周报 → 开始盲测」：`POST /blind-tests` 返回 `blind_test_id` + `sentence_ids`，
  客户端把抽题写入进程内 `BlindRuntime`，清空导航栈并切回「跟读」Tab；
- 跟读页进入**盲测模式**：只显示这批句子、不提供示范音、提交时 `POST /attempts` 带 `blind_test_id`，
  服务端只回 `{attempt_id, blind, progress}`（无分数）；提交后 400ms 自动进下一句，2000ms 轮询
  `GET /blind-tests` 只更新「已评完/待评分」计数，**绝不读分数**；
- 读完后按钮「结束盲测 · 去看周报」→ 盲测页 `POST /:id/finish` → 显示 `notice`/平均分（未评完不计 0 分）；
- 约束：盲测中 `retry` 会被服务端 409，客户端不提供「重试评测」入口。

### 真实接口核对（2026-11-03，桌面端用 dad@example.com 实测）

用真实账号从桌面调用了线上接口，确认客户端 DTO 与线上字段一致（**不是**只按源码推断）：

| 接口 | 关键字段（实测） |
|---|---|
| `POST /auth/token` | `user` 仅 7 字段（id/email/displayName/role/ageBand/cefrLevel/avatar），无 `isChild`/`dailyLimitMinutes`（儿童判定靠 `role/ageBand`）|
| `GET /settings` | `{user, prefs{correctionLevel,ttsVoice,ttsRate,showWordIpa}, usage}` |
| `GET /sentences?level=` | `{level, focus, count, sentences[]}`；`focus_phonemes` 儿童为空数组 |
| `POST /tts` | 200 `audio/wav`（RIFF 头）、`x-audio-duration-ms`、`x-tts-provider`；错误分支才是 JSON |
| `GET /attempts?limit=` | `{attempts:[{id,sentence_id,scores,issues,intonation{user_f0,reference_f0},audio_url,...}]}` |
| `POST /chat/sessions` | `{session_id, scenario{...,variation}, age, turn_count, messages[]}`（注意是 `session_id` 不是 `id`）|
| `POST /chat/sessions/:id/turn` | `{session_id, reply, reply_zh, correction, suggested_replies, target_words, flag, done, turn_index, message_id, user_message_id}` |
| `GET /chat/sessions/:id/messages` | `{session_id, messages[{id,role,text,text_zh,audio_url,pron,correction,flag}]}` |
| `GET /chat/scenarios` | `{scenarios[{id,audience,is_custom,title,title_zh,setting_zh,opening_line,level,min_age,tags,variation_count}]}` |
| `POST /story/rewrite` | `{title_en, sentences:[string], text_en, level, readability{sentence_count,avg_words,max_words,unknown_words,ok}, warnings, provider, weak_phonemes_used}` |
| `POST /materials`（kind=story）| 返回**扁平**对象 `{id,title,...}`（不是 `{created}` 包装）；DELETE 可用 |
| `GET /materials?kind=story` | `{items:[{id,title,created_by_name,sentence_count,has_image,source,kind,level,has_source_zh,has_recording,recording_id,...}]}` |
| `GET /materials/:id` | `{id,title,text,sentence_count,has_image,source,kind,level,source_zh,image_url,image_prompt,image_character_used,...}` |
| `GET /story/:id/audio/status` | `{status:"building"|"ready"|"failed"|"no_audio", attempt_count?}` |
| `GET /diagnosis?scope=recent&days=7` | `{generated_at,min_samples,counts{weak,watch,ok},summary_zh,focus_phonemes,items[{phoneme,child_label,focus_token,status,attempts,avg_score,last_score,best_score,trend,error_words,practice_count,tip_zh,tip_child_zh,hint_key}]}` |
| `GET /review` | `{now, stats{total_cards,due_cards,phoneme_rows,phoneme_level,voice_reachable}, due_cards[{id,kind,ref,due_at,ease,interval_days,reps,lapses,last_grade,phoneme,hint_key,label,why_zh,how_zh}]}` |
| `POST /blind-tests` | `{blind_test_id, sentence_ids[10], total, resumed}`（同用户抽题固定）|
| `GET /blind-tests` | `{user_id,tests[],in_progress,pending_total,trend{...},series[]}` |
| `GET /parent/summary` | `{generated_at, family{members,minutes_today,minutes_7d,sentence_count,scenario_count,children[]}, members[{...today/week...}]}`（snake_case）|
| `GET /family/members` | `{items:[...snake_case...]}` |
| `GET /avatar/presets` | `{styles:[{id,label_zh}], characters:[{id,label_zh,desc_en,gender,audience,images{5风格→站内路径}}], placeholder}` |
| `GET /avatar` | `{avatar_url,preset_id,style,character_desc,prompt_used,styles{...}}` |
| `PATCH /settings` | 服务端 200（`{tts_rate:"normal"}`）；HarmonyOS 端 PATCH 方法是否被 http 接受待真机验证 |
| `GET /suggestions` | `{items,counts,total,generated_at,max_length}` |
| 线上缺失 | `/api/tts/voices`、`/api/story/recordings`、`/api/practice/cursor`、`/api/sentences/:id/attempts` → 客户端均已降级 |

> 注意：桌面端调 `POST /blind-tests` 已为 dad 账号创建了一个进行中批次（10 句，A1+B1），
> 真机登录后可验证「继续盲测」流程。

### V3 未验证（阻塞项）

- [ ] **登录后接口联调被阻塞**：线上部署用 `BOOTSTRAP_*` 覆盖了种子账号密码，
      `dad@example.com / Dad12345!` 已 401；需要可用测试账号后才能验证
      连读/对话/故事/诊断/复习/盲测/家长/成员/建议/形象/音色/设置的真实数据链路。
- [ ] 录音→上传→评测全链路（用户已在旧版实测「录音正常、评分正常」；录音代码未改）。
- [ ] 语音对话三步（ASR→turn→TTS）、故事中文 ASR、整段回放、插画生成。
- [ ] `PATCH` 请求（设置/形象/成员/建议）：HarmonyOS `http.RequestMethod` 无 PATCH 枚举，
      客户端用字符串方法名下发，真机未验证；失败时页面提示「该设置暂不可用」。
