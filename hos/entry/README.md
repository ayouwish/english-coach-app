# entry（HAP）· 应用壳

> 这是 DevEco Studio 的 **entry HAP** 模块占位目录；M0 才创建 `module.json5`、`oh-package.json5`、`build-profile.json5` 等可编译文件。
> 职责：启动、登录门禁、导航壳、全局状态/错误、把各 feature 的 `NavDestination` 装配进根 `Navigation`。

## 目录

```text
entry/
├── src/main/
│   ├── module.json5                 # M0 创建：abilities + requestPermissions
│   ├── ets/
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets     # 启动、窗口、隐私首启
│   │   ├── pages/
│   │   │   ├── Index.ets            # Navigation 根 + 底部 tab
│   │   │   ├── LaunchPage.ets       # 启动/恢复会话/健康检查
│   │   │   └── NotFoundPage.ets
│   │   ├── components/
│   │   │   ├── AppShell.ets
│   │   │   ├── BottomNav.ets
│   │   │   ├── GlobalErrorBanner.ets
│   │   │   └── ChildModeFrame.ets
│   │   ├── viewmodel/
│   │   │   ├── AppVM.ets            # 启动态/健康检查
│   │   │   ├── SessionVM.ets        # 当前用户/角色/儿童模式
│   │   │   └── UsageVM.ets          # 今日用量
│   │   ├── service/
│   │   │   ├── BootstrapService.ets
│   │   │   ├── NavigationService.ets
│   │   │   └── DeeplinkService.ets
│   │   └── utils/
│   └── resources/
│       ├── base/element/            # color.json / string.json / float.json
│       ├── dark/element/            # M4 深色 token
│       └── rawfile/
└── ...
```

## 约束

- 不承载具体业务页面；业务页面在 `features/<x>`。
- 不直接 `http.createHttp()`；HTTP 在 `commons/net`。
- 不直接 `createAVRecorder/createAVPlayer`；音频在 `commons/audio`。
- `Index.ets` 只做装配：登录态检查 → 首页/登录；tab 切换；全局错误横幅。
- 所有全局状态放 `AppStorage`，但只放小对象（Session/Usage/AppConfig）。

## M0 要创建的最小文件

1. `AppScope/app.json5`（bundleName、versionCode/Name、icon、label）
2. `build-profile.json5`（signingConfigs、products、compileSdk 20）
3. `hvigorfile.ts`、`oh-package.json5`
4. `entry/build-profile.json5`、`entry/hvigorfile.ts`、`entry/oh-package.json5`
5. `entry/src/main/module.json5`（`EntryAbility` + `INTERNET`/`MICROPHONE`）
6. `entry/src/main/ets/entryability/EntryAbility.ets`
7. `entry/src/main/ets/pages/Index.ets`（空壳可启动）

详细结构见 [`../README.md`](../README.md) 第 3 节。
