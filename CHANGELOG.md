# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0] - 2026-08-13

### Changed

- 正式版：移除全部诊断弹窗/计数（HOOK HIT 等）
- 保留「NoBrandSplash Injected OK」注入确认弹窗（UIAlertView + NSTimer 1 秒自动消失，QSNoAds v25 同款方案）
- 弹窗通知机制改用 NSNotificationCenter block 观察者（主线程回调，弹窗可靠显示）
- 设备验证通过：冷启动 / 热启动均无 Splash 广告，`handleAdInfo:` 单点 Hook 完整覆盖品牌 + 第三方聚合

## [2.0.0] - 2026-08-13

### Changed

- Splash Hook 点从 `handleBrandAd:` 迁移到 `handleAdInfo:`
- 覆盖品牌 Splash 与第三方聚合 Splash（CSJ / GDT / OCT / BeiZi / CJMobile / Sigmob）
- 同时覆盖冷启动与热启动
- 使用 `closeController:YES` 正常结束 Splash 生命周期
- 避免写入 `saveFailSplashADDate`

## [1.0.0] - 2026-08-12

### Added

- **MVP: 阻断 5EPlay 品牌开屏广告**
  - Hook `-[SADSplashAdViewController handleBrandAd:]`，品牌 Splash 唯一入口
  - 阻断后调用 `closeController:YES` 保证启动流程正常（不卡启动页、不污染服务端频控）
- 三级日志（`hook OK` / `hook MISS` / `BLOCKED`）+ 注入成功弹窗验证
- `build.cmd`（clang 20.1.8 + ld64.lld + iPhoneOS16.5.sdk）
- `tools/check_macho.py` Mach-O 结构自检
- GitHub Actions：macOS runner 自动构建 + 结构校验 + artifact 上传
- README / LICENSE / SECURITY / CODE_OF_CONDUCT
