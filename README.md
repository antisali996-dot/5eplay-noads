# NoBrandSplash — 5EPlay 去开屏品牌广告插件 (MVP)

TrollFools 注入 dylib，阻断 5EPlay 7.2.1 的「品牌开屏广告」（Brand Splash）。

## 功能

- Hook `-[SADSplashAdViewController handleBrandAd:]`，阻断品牌开屏广告流程
- 阻断后立即调用 `closeController:YES`，保证 App 启动流程正常继续（不卡启动页）
- 日志 + 弹窗双重验证注入生效

## 版本 / 目标

| 项 | 值 |
|---|---|
| 目标 App | 5EPlay 对战平台 |
| 版本 | 7.2.1 |
| Bundle ID | `com.5e.5eplay` |
| 架构 | arm64（thin） |
| iOS | 14-17（TrollStore 环境） |

## 逆向依据

品牌开屏广告唯一入口（IDA 反编译 `5EPlay_7.2.1_decrypted`）：

```
GET /v1/home/adv_slot/list
  → adv_display == 1 (NSInteger)
  → adv_brand != nil
  → handleAdInfo:
  → handleBrandAd:   ← 本插件 Hook 点
  → loadAdData:
  → SADBrandConnection (platform=1)
  → SADBrandSplashAd.showAd
```

关键函数（已确认存在，含签名）：

| 方法 | 地址 | 签名 |
|---|---|---|
| `-[SADSplashAdViewController handleBrandAd:]` | 0x1022F7998 | `v24@0:8@16` |
| `-[SADSplashAdViewController closeController:]` | 0x1022F759C | `v20@0:8B16` |

`closeController:` 内部触发 `closeHandle` block → `afterADShowFinished` → 发 `Notif_AfterADShowFinished` → App 继续初始化，因此 Hook `handleBrandAd:` 后调用它不会破坏启动流程。

## Hook 逻辑

```objc
// 替换 -[SADSplashAdViewController handleBrandAd:]
- (void)hook_handleBrandAd:(id)brand {
    LOG("BLOCKED: handleBrandAd:");
    [self closeController:YES];   // YES=正常关闭，不污染服务端频控
}
```

Hook 时机：constructor 只 `dlsym` + 注册 `UIApplicationDidFinishLaunchingNotification`；真正 Hook 在启动完成通知回调里执行（避免早期调 objc runtime API 触发 SIGILL）。

## 构建

前置：clang + ld64.lld + iPhoneOS SDK（本机路径见 `build.cmd`）。

```
build.cmd
```

产物：`out/NoBrandSplash.dylib`（arm64 thin，CHAINED_FIXUPS + __init_offsets 已验证 PASS）。

## 安装测试步骤

### 1. 安装 dylib 到设备

1. 把 `out/NoBrandSplash.dylib` 传到 iPhone（AirDrop / 网盘 / iCloud 均可）
2. 用 **TrollFools** 打开 dylib：
   - iOS 14-15：TrollFools 直接选择 dylib → 选择 5EPlay 注入
   - iOS 16+：TrollFools 提供「导入应用」→ 选择已安装的 5EPlay → 注入 dylib
3. 注入成功后重新启动 5EPlay

### 2. 验证注入生效（3 个信号）

1. **弹窗**：App 启动后约 1-2 秒弹出「NoBrandSplash Injected OK」，2 秒自动消失
2. **无品牌开屏广告**：冷启动不再出现品牌广告 Splash（服务端返回 adv_brand 时被拦截）
3. **启动不卡**：跳过广告后能正常进入主界面（若卡在启动页说明 closeController 未生效，见下方排错）

### 3. 确认日志（可选）

设备端用 `log stream`（需 Xcode）或 TrollStore 的日志查看器，过滤 `NoBrandSplash`：

```
[NoBrandSplash] plugin loaded, resolving symbols...
[NoBrandSplash] constructor done, waiting for app launch
[NoBrandSplash] app did finish launching, begin hooking
[NoBrandSplash] hook OK: -[SADSplashAdViewController handleBrandAd:]
[NoBrandSplash] BLOCKED: -[SADSplashAdViewController handleBrandAd:]
```

- `hook OK` 出现 = Hook 方法成功
- `BLOCKED` 出现 = 品牌广告被成功拦截

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| 无弹窗、无日志 | dylib 未加载（weak 加载静默失败） | 确认 dylib 已注入 TrollFools；确认 5EPlay 用 TrollStore 安装（非 App Store） |
| 弹窗出现但仍有广告 | Hook MISS | 检查日志 `hook MISS` → App 版本变了，重新逆向确认方法名 |
| 启动页卡死 | closeController 未被调用或参数不对 | 确认日志有 `BLOCKED`；若 `BLOCKED` 后仍卡，需逆向确认 `closeController:` 的 closeHandle 是否生效 |
| 注入后 App 崩溃 | 版本不匹配或工具链问题 | 检查 .ips 崩溃日志；确认 dylib 是 clang+ld64.lld 构建（CHAINED_FIXUPS 必须存在） |

## 踩坑记录（开发过程）

1. **工具链必须是 clang + ld64.lld**：zig 产物缺 `LC_DYLD_CHAINED_FIXUPS` + `__init_offsets`，dyld 会静默拒绝（weak 加载失败无提示）。本机用 `clang 20.1.8 + ld64.lld 20.1.8 + iPhoneOS16.5.sdk`。
2. **lld 20 用 `__init_offsets` 替代 `__mod_init_func`**：`check_macho.py` 会报 `no __mod_init_func` WARN，这是正常的 lld 新结构，不影响注入（已确认 `__init_offsets` 内容指向 constructor）。
3. **PowerShell 调用 clang 时 `-o` 被误解析**：`& clang @args` 在 PS 下把 `-o` 传给驱动层出错。改用 `cmd /c build.cmd` 最可靠。
4. **constructor 禁止调 objc runtime API**：早期调 `class_getInstanceMethod` 会 SIGILL。必须等 `UIApplicationDidFinishLaunchingNotification`。
5. **阻断后必须调 `closeController:`**：`handleBrandAd:` 原本会调度 `checkTimeout` 和加载广告，直接置空会导致 splash 视图常驻、启动卡死。MVP 用 `closeController:YES`（正常关闭，不写 `saveFailSplashADDate`，不污染服务端频控）。
6. **`@""` 字面量需要 .m 编译**：`.c` 文件里写 `@"..."` 会报错，hook 源码必须用 `.m` 扩展名让 clang 走 ObjC 编译。

## 后续规划（不在本 MVP 范围）

- Hook `handleAdList:`（adv_slot_items 普通 Splash 广告）
- Hook `SADBrandSplashAd.showAd` 兜底（SDK 出口层）
- 广告位列表 / 插屏 / 激励视频去广告

## Release

编译好的 dylib 通过 GitHub Release 发布（不在源码仓库中）：

- 前往 [Releases](../../releases) 下载 `NoBrandSplash.dylib`
- 或用本仓库 `build.cmd` 自行构建（需 clang + ld64.lld + iPhoneOS SDK）

## 免责声明

本插件仅供学习 iOS 逆向与 TrollFools 注入技术研究使用。请仅在你自己拥有、或已获授权修改的设备/应用上使用。使用本插件造成的任何后果由使用者自行承担。

## License

MIT
