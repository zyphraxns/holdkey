#!/bin/bash
# HoldKey 构建脚本 —— 不依赖 SwiftPM
# 原因：本机只有 Command Line Tools（无 Xcode.app），而 SwiftPM 构建 manifest 时会调用
# sandbox-exec，在当前环境里被拒（sandbox_apply: Operation not permitted）。
# 直接用 swiftc 编所有源文件更简单，也顺便绕过了 ModuleCache 不可写的问题。
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
APP="$ROOT/dist/HoldKey.app"
CONFIG="${1:-release}"

CACHE="$ROOT/.build-cache"
mkdir -p "$CACHE/module" "$CACHE/bin"
export CLANG_MODULE_CACHE_PATH="$CACHE/module"

SRCS=$(find Sources/HoldKey -name '*.swift' | sort)
[ -n "$SRCS" ] || { echo "找不到源文件"; exit 1; }

OPT_FLAGS=(-O)
[ "$CONFIG" = "debug" ] && OPT_FLAGS=(-Onone -g)

echo "==> 编译 ($CONFIG)"
# shellcheck disable=SC2086
swiftc \
  "${OPT_FLAGS[@]}" \
  -target arm64-apple-macosx14.0 \
  -module-name HoldKey \
  -module-cache-path "$CACHE/module" \
  -parse-as-library \
  -framework SwiftUI -framework AppKit -framework CoreGraphics -framework Carbon \
  -o "$CACHE/bin/HoldKey" \
  $SRCS

echo "==> 组装 .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$CACHE/bin/HoldKey" "$APP/Contents/MacOS/HoldKey"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HoldKey</string>
  <key>CFBundleDisplayName</key><string>HoldKey</string>
  <key>CFBundleIdentifier</key><string>com.liamqiu.holdkey</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>HoldKey</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "==> 签名"
"$ROOT/scripts/sign.sh" "$APP"

echo "BUILD OK: $APP"
