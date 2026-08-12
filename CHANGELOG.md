# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
