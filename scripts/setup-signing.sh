#!/bin/bash
# 一次性设置：在 login keychain 里创建一张本地自签证书，用于给 HoldKey 签名。
#
# 为什么非做不可：
#   TCC 记的不是「哪个 App 被允许」，而是「哪份代码身份被允许」。
#   ad-hoc 签名（codesign -s -）会把 designated requirement 钉在这份二进制的 cdhash 上，
#   重新编译一次 cdhash 就变，辅助功能授权就掉一次 —— 而系统设置里的勾还显示是开的。
#   换成固定证书后，DR 变成 identifier + certificate leaf hash，跨重建稳定。
#
# 只需要跑一次。之后 scripts/build.sh 会自动用这张证书签名。
# 完全本机操作：证书只进你的 login keychain，不上传，也不需要 Apple 开发者账号。
set -euo pipefail

CERT_NAME="HoldKey Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "✓ 证书已存在：$CERT_NAME"
    security find-identity -v -p codesigning | grep -F "$CERT_NAME"
    exit 0
fi

echo "==> 生成自签证书"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = ext
[ dn ]
CN = HoldKey Local Signing
[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:holdkey >/dev/null 2>&1 \
|| openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:holdkey >/dev/null 2>&1

echo "==> 导入 login keychain（可能会弹一次钥匙串密码框，允许即可）"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P holdkey \
    -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null

echo "==> 标记为信任根"
security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$TMP/cert.pem"

echo "==> 验证"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    security find-identity -v -p codesigning | grep -F "$CERT_NAME"
    echo "✓ 完成。现在跑 ./scripts/build.sh，签名会自动使用这张证书。"
else
    echo "✗ 失败：证书导入后仍找不到可用身份。" >&2
    echo "  可能是 keychain 需要解锁，试：security unlock-keychain ~/Library/Keychains/login.keychain-db" >&2
    exit 1
fi
