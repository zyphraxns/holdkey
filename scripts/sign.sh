#!/bin/bash
# 给 .app 签名。
#
# 有本地自签证书就用它（DR = identifier + 证书 hash，授权跨重建保留）；
# 没有就退回 ad-hoc 并明确警告 —— 那种情况每次重建都要重新授权一次。
# 首次使用请先跑 scripts/setup-signing.sh。
set -euo pipefail

APP="${1:?用法: sign.sh <path/to/App.app>}"
CERT_NAME="HoldKey Local Signing"
BUNDLE_ID="com.liamqiu.holdkey"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    # errSecInternalComponent 是偶发的：私钥在 login 钥匙串里，访问授权偶尔拿不到。
    # 直接重试通常第二次就成功，所以这里重试 5 次，别让整个构建随机失败。
    ok=0
    for i in 1 2 3 4 5; do
        if codesign --force --deep --options runtime \
            --sign "$CERT_NAME" --identifier "$BUNDLE_ID" "$APP" 2>/tmp/holdkey-sign.err; then
            ok=1
            break
        fi
        sleep 0.4
    done
    if [ "$ok" -ne 1 ]; then
        echo "    ✗ 签名失败（试了 5 次）:" >&2
        sed 's/^/      /' /tmp/holdkey-sign.err >&2
        echo "      常见原因：login 钥匙串里私钥的访问需要用户确认，但当前没有可弹窗的界面。" >&2
        echo "      在「终端」里手动跑一次下面这条，勾选「始终允许」，之后就不会再问：" >&2
        echo "      codesign --force --deep --options runtime --sign \"$CERT_NAME\" --identifier $BUNDLE_ID \"$APP\"" >&2
        exit 1
    fi
    echo "    SIGNED: $CERT_NAME"
    echo "    DR: $(codesign -d -r- "$APP" 2>&1 | grep designated | sed 's/^.*designated => //')"
else
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null
    echo "    SIGNED: ad-hoc" >&2
    echo "    ⚠️  没有找到 '$CERT_NAME'。ad-hoc 签名的副作用：" >&2
    echo "        每次重新编译后，系统设置里的辅助功能授权会失效（勾还显示开着）。" >&2
    echo "        跑一次 ./scripts/setup-signing.sh 可以一劳永逸。" >&2
fi
