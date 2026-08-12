<div align="center">

# 🚫 NoBrandSplash

**5EPlay 去开屏品牌广告插件 · TrollFools dylib**

Block 5EPlay's brand splash ads via a single Objective-C runtime hook.

[![GitHub release](https://img.shields.io/github/v/release/antisali996-dot/5eplay-noads?include_prereleases&style=flat-square)](https://github.com/antisali996-dot/5eplay-noads/releases)
[![License](https://img.shields.io/github/license/antisali996-dot/5eplay-noads?style=flat-square)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/antisali996-dot/5eplay-noads/build.yml?branch=main&style=flat-square&logo=github)](https://github.com/antisali996-dot/5eplay-noads/actions)
[![Platform](https://img.shields.io/badge/platform-iOS%2014-17-blue?style=flat-square&logo=apple)]()

*用于学习 iOS 逆向与 TrollFools 注入技术研究。请仅用于你自己拥有或已获授权的设备。*

</div>

---

## 📋 目录

- [功能特性](#-功能特性)
- [逆向分析](#-逆向分析)
- [Hook 设计](#-hook-设计)
- [构建](#-构建)
- [安装与验证](#-安装与验证)
- [排错指南](#-排错指南)
- [开发踩坑记录](#-开发踩坑记录)
- [Roadmap](#-roadmap)
- [FAQ](#-faq)
- [License](#-license)

---

## ✨ 功能特性

- 🎯 **单点阻断**：Hook `-[SADSplashAdViewController handleBrandAd:]` —— 品牌开屏广告唯一入口
- 🔒 **不破坏启动流程**：阻断后自动调用 `closeController:YES`，保证 App 正常进入主界面
- 🧪 **可观测**：`hook OK` / `hook MISS` / `BLOCKED` 三级日志 + 注入成功弹窗
- 📦 **纯源码可审计**：Hook 逻辑只在一个 `.m` 文件里，结构自检脚本验证产物
- 🛠 **clang + ld64.lld 构建**：产物带 `LC_DYLD_CHAINED_FIXUPS`，TrollFools 可注入

**目标环境**

| 项 | 值 |
|---|---|
| 目标 App | 5EPlay 对战平台（CS:GO / CS2 社区） |
| App 版本 | 7.2.1 |
| Bundle ID | `com.5e.5eplay` |
| 产物架构 | arm64（thin） |
| iOS | 14 – 17（TrollStore / TrollFools） |

---

## 🔬 逆向分析

> 基于解密版 5EPlay 7.2.1（IDA 反编译）确认的完整广告触发链路。

### 品牌开屏广告触发链路

```mermaid
flowchart TD
    A["GET /v1/home/adv_slot/list"] --> B{"adv_display == 1?"}
    B -- "No" --> X["不进广告流程"]
    B -- "Yes" --> C{"adv_brand != nil?"}
    C -- "No" --> D["handleAdList: 广告位列表分支"]
    C -- "Yes" --> E["handleAdInfo:"]
    E --> F["⭐ handleBrandAd: ← Hook 点"]
    F --> G["loadAdData:"]
    G --> H["SADBrandConnection (platform=1)"]
    H --> I["SADBrandSplashAd.showAd"]
```

### 关键函数（已确认存在）

| 方法 | 分析地址 | ObjC 类型签名 |
|---|---|---|
| `-[SADSplashAdViewController handleBrandAd:]` | `0x1022F7998` | `v24@0:8@16` |
| `-[SADSplashAdViewController closeController:]` | `0x1022F759C` | `v20@0:8B16` |

> ⚠️ 地址仅供分析定位使用，插件本身通过 **Class + Selector** 定位，不依赖地址。

### 为什么选这个 Hook 点

- `handleBrandAd:` 是品牌广告的**唯一入口**（XREF 仅 1 个调用者 `handleAdInfo:`）
- 它位于**业务层**，而非 GDT/CSJ/WindMill 等 SDK 层 —— SDK 更新不失效、覆盖面完整
- 它的上游由服务端 `adv_display` + `adv_brand` 双重控制，Hook 它等价于同时覆盖「服务端开关」与「内容分支」

---

## 🪝 Hook 设计

```objc
// 替换 -[SADSplashAdViewController handleBrandAd:]
static void hook_handleBrandAd(id self, SEL _cmd, id brand) {
    LOG("BLOCKED: handleBrandAd:");           // ① 执行日志
    [self closeController:YES];                // ② 生命周期收尾
}
```

**为什么不能只 `return`？**

`handleBrandAd:` 被调用时，`SADSplashAdViewController` 的视图**已经挂在启动窗口上**。若直接置空，原流程里的 `checkTimeout`（3 秒自动关闭）和 `closeController:` 都不会被触发 → **启动页永久卡死**。

因此阻断后必须显式调用 `closeController:YES`：
- 触发 `closeHandle` block → `afterADShowFinished` → 发 `Notif_AfterADShowFinished` → App 继续初始化 ✅
- `YES` = 正常关闭，不写入 `saveFailSplashADDate`，**不污染服务端频控数据** ✅

**Hook 时机**：`constructor` 只做 `dlsym` 符号解析 + 注册 `UIApplicationDidFinishLaunchingNotification`；真正的 `method_setImplementation` 推迟到启动完成回调 —— 避免早期调用 ObjC runtime API 触发 SIGILL。

---

## 🛠 构建

### 前置依赖

| 依赖 | 版本 | 获取方式 |
|---|---|---|
| clang | ≥ 16 | LLVM 官方 Windows 发行版 |
| ld64.lld | 与 clang 配套 | 同上 |
| iPhoneOS SDK | iOS 16.5+ | Theos / Xcode |

### Windows

```
build.cmd
```

产物：`out/NoBrandSplash.dylib`（arm64 thin）

### macOS / Linux

```bash
clang -target arm64-apple-ios16.5 \
  -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -fobjc-arc -fno-stack-protector -fvisibility=hidden \
  -fuse-ld=lld -dynamiclib -undefined dynamic_lookup \
  -o out/NoBrandSplash.dylib src/hook.m
```

> 💡 任何工具链构建后，**必须**运行 `python tools/check_macho.py out/NoBrandSplash.dylib` 验证结构，否则 dyld 可能静默拒绝加载。

### CI 自动构建

本仓库配置了 [GitHub Actions](../../actions)，每次推送/打 tag 都会在 macOS runner 上自动构建并校验产物，可下载 workflow artifact 或直接使用 [Release](../../releases) 中的 dylib。

---

## 📲 安装与验证

### 安装

1. 从 [Releases](../../releases) 下载 `NoBrandSplash.dylib`，传到 iPhone（AirDrop / 网盘均可）
2. 用 **TrollFools** 打开 dylib：
   - iOS 14–15：TrollFools 选择 dylib → 选择 5EPlay 注入
   - iOS 16+：TrollFools 的「导入应用」→ 选择已安装的 5EPlay → 注入
3. **杀掉 5EPlay 进程后冷启动**（注入不重启不生效）

### 验证注入生效（3 个信号）

| 信号 | 说明 |
|---|---|
| ① 弹窗 | 启动约 1–2 秒弹出 `NoBrandSplash Injected OK`，2 秒自动消失 |
| ② 无品牌开屏广告 | 冷启动不再出现品牌广告 Splash |
| ③ 启动不卡 | 能正常进入主界面 |

### 确认日志（可选）

设备端 `log stream` 过滤 `NoBrandSplash`：

```
[NoBrandSplash] plugin loaded, resolving symbols...
[NoBrandSplash] constructor done, waiting for app launch
[NoBrandSplash] app did finish launching, begin hooking
[NoBrandSplash] hook OK: -[SADSplashAdViewController handleBrandAd:]
[NoBrandSplash] BLOCKED: -[SADSplashAdViewController handleBrandAd:]
```

- `hook OK` = Hook 方法命中
- `BLOCKED` = 品牌广告被成功拦截

---

## 🔧 排错指南

| 现象 | 原因 | 处理 |
|---|---|---|
| 无弹窗、无日志 | dylib 未加载（weak 加载静默失败） | 确认已注入 TrollFools；确认 5EPlay 是 TrollStore 安装（非 App Store 版） |
| 弹窗出现但仍有广告 | Hook MISS（版本差异） | 检查日志 `hook MISS` → 重新逆向确认方法名 |
| 启动页卡死 | `closeController:` 未生效 | 确认日志有 `BLOCKED`；若仍卡，逆向确认 closeHandle 链路 |
| 注入后崩溃 | 版本不匹配 / 工具链问题 | 查 `.ips`；确认 dylib 有 `CHAINED_FIXUPS` |

---

## 🐞 开发踩坑记录

1. **工具链必须 clang + ld64.lld**：zig 产物缺 `LC_DYLD_CHAINED_FIXUPS` + `__init_offsets`，dyld 静默拒绝（weak 加载失败无提示）。
2. **lld 20 用 `__init_offsets` 替代 `__mod_init_func`**：check 脚本报 `no __mod_init_func` WARN 属正常，不影响注入。
3. **PowerShell 调 clang 时 `-o` 被误解析**：改用 `cmd /c build.cmd`。
4. **constructor 禁止调 objc runtime API**：早期调 `class_getInstanceMethod` 会 SIGILL，必须等启动完成通知。
5. **阻断后必须调 `closeController:`**：否则 splash 视图常驻、启动卡死；传 `YES` 避免污染频控。
6. **`@"..."` 字面量需要 `.m` 编译**：`.c` 编译会报 `@` 语法错误。

---

## 🗺 Roadmap

- [x] MVP：阻断品牌开屏广告（`handleBrandAd:`）
- [ ] 阻断普通 Splash 广告（`handleAdList:`）
- [ ] SDK 出口兜底（`SADBrandSplashAd.showAd`）
- [ ] 插屏 / 激励视频去广告（可配置开关）

---

## ❓ FAQ

**Q: 为什么不去 Hook 穿山甲 / 优量汇 SDK？**
A: 品牌广告根本不经过这些 SDK；且 Hook SDK 层在版本更新后极易失效。业务层唯一入口更稳定、覆盖面更完整。

**Q: 会不会被服务端反制？**
A: 插件主动关闭广告时传 `YES`，不会写入"展示失败"频控数据，避免影响服务端对账号的判断。

**Q: App 升级后失效怎么办？**
A: 先看日志是 `hook MISS` 还是 `target class NOT FOUND`，再决定重新逆向方法名或整条链路。

---

## 📄 License

[MIT](LICENSE)

---

*仅供学习 iOS 逆向与 TrollFools 注入技术研究使用。请仅在你自己拥有、或已获授权修改的设备/应用上使用。使用本插件造成的任何后果由使用者自行承担。*
