#!/bin/bash
# 로그인 키체인에 Mixer 전용 자체 서명 코드서명 인증서를 한 번 만든다.
# 시스템 오디오 녹음 권한(TCC)이 서명 ID에 묶이므로, 다시 빌드해도 같은 인증서로 서명해야 권한이 유지된다.
set -euo pipefail

NAME="${MIXER_SIGN_IDENTITY:-Mixer Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS security import는 OpenSSL 3+의 기본 PKCS#12 암호화를 읽지 못해 시스템 LibreSSL을 쓴다.
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "이미 있습니다: $NAME"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS="mixer-$RANDOM$RANDOM"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/id.p12" -passout "pass:$PASS"

security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "생성했습니다: $NAME"
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
