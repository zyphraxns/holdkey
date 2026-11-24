# HoldKey（中文）

<p align="right"><sub><a href="README.md">English README</a></sub></p>

**一个热键按住某键 N 秒——四个预设各有独立热键，切走应用的瞬间就松键。**

<sub>macOS 14+ · Apple 芯片（arm64）· 纯本地，无网络与遥测</sub>

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

HoldKey 面向游戏或串流会话（比如 GeForce NOW）：有时需要把移动键按住一会儿——攀爬、向前走、上马。手按很无聊，粗糙的宏又可能把键按死。HoldKey 会在到时间、以及你离开应用的瞬间松键。

| 预设 | 热键 | 按住 | 时长 |
| --- | --- | --- | --- |
| 1 · 前进 | `⌥⌘H` | W | 30 秒 |
| 2 · 左移 | `⌥⌘J` | A | 30 秒 |
| 3 · 后退 | `⌥⌘K` | S | 30 秒 |
| 4 · 跳跃 | `⌥⌘L` | 空格 | 30 秒 |

默认热键都不含 Ctrl（原神的走/跑切换），四个都能在面板里重新录制。按住时菜单栏显示「预设名 · 剩余秒数」，待命时只显示键盘图标。

## 安装

要求：macOS 14+、仅 Apple 芯片（`arm64-apple-macosx14.0`）、编译需 Xcode Command Line Tools（不需完整 Xcode），以及辅助功能权限。

### 预编译包

从[最新 Release](https://github.com/zyphraxns/holdkey/releases/latest)下载 `HoldKey.app.zip`，解压后把 `HoldKey.app` 移入「应用程序」。首次打开请右键 →「打开」（本地签名，未公证）。

### 从源码构建

```bash
git clone https://github.com/zyphraxns/holdkey.git
cd holdkey
./scripts/setup-signing.sh   # 一次性：创建本地自签证书
./scripts/build.sh           # 产出 dist/HoldKey.app
open dist/HoldKey.app
```

项目没有 SwiftPM 包：`build.sh` 直接用 `swiftc` 编译 `Sources/HoldKey/*.swift`，所以只需要 Command Line Tools。

<details>
<summary>为什么要跑签名脚本</summary>

TCC 记的是「代码身份」而不只是「哪个 App」。ad-hoc 签名（`codesign -s -`）每次重建都会变，辅助功能授权会悄悄失效；`setup-signing.sh` 创建固定证书，让 designated requirement 跨重建稳定。两个脚本都只在本机操作，不上传任何东西，也不需要 Apple 开发者账号。

</details>

## 快速开始

1. 启动 HoldKey，授予辅助功能权限，等面板出现绿点。
2. 点菜单栏键盘图标，选预设 1–4，可按需改名称、按键或时长。
3. 让游戏保持前台，按对应热键（或点「开始按住…」）。
4. 再按一次同一个热键、或切到其他应用即可停止。

完整说明见 [使用说明.md](使用说明.md)。

## 配置

预设保存在本地偏好里：`hold.presets.v1`（四个预设的 JSON）和 `hold.selectedPreset`。面板可改名称、按键、时长并录制热键。录制的热键必须包含 ⌥/⌘/⇧ 中至少一个，且不能含 Ctrl。

## 安全与范围

HoldKey 通过 CGEvent 注入**全局**键盘事件：按住期间会占用键盘，机器不能同时自由使用。它只负责按键——不读屏、不点击、不做决策。设有 30 分钟上限；退出、休眠、注销、关机都会松键，下次启动会清理残留按键。

<details>
<summary>服务条款提示</summary>

请自行判断并遵守游戏与串流平台的条款。部分游戏厂商将第三方输入工具视为违规。

</details>

## 日志

每次开火写一行到 `~/Library/Logs/HoldKey.log`（写不进去时退到临时目录）。`systemKeyState=up` 表示系统确认键已松开；`WARNING` 表示松键被自动补发过。

<details>
<summary>日志示例</summary>

```
[2026-11-23T18:26:49Z] [pid 337] fire key=W vk=13 secs=2.0 focus=Safari
[2026-11-23T18:26:51Z] [pid 337] hold done vk=13 fired=53 cancelled=false held=0 systemKeyState=up
```

</details>

## 开发

见 [CONTRIBUTING.md](CONTRIBUTING.md) 了解构建与贡献方式。

## 许可证

MIT — 见 [LICENSE](LICENSE)。
