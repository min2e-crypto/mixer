#!/bin/bash
# SwiftPM 산출물을 .app으로 감싸 서명한다. 고정 자체 서명 인증서가 있으면 그것으로, 없으면 ad-hoc으로 서명한다.
# ad-hoc이면 다시 빌드할 때마다 시스템 오디오 녹음 권한을 다시 묻는다(개발 중이면 scripts/setup-signing.sh).
# 사용법: scripts/build-app.sh [mixer|tapspike]
#   mixer(기본): ~/Applications/Mixer.app 에 설치
#   tapspike:    dist/Tapspike.app (0단계 스파이크)
set -euo pipefail

TARGET="${1:-mixer}"
IDENTITY="${MIXER_SIGN_IDENTITY:-Mixer Local Signing}"
cd "$(dirname "$0")/.."

case "$TARGET" in
  mixer)    PRODUCT=Mixer;    PLIST=Resources/Info.plist;          APP="$HOME/Applications/Mixer.app" ;;
  tapspike) PRODUCT=tapspike; PLIST=Resources/tapspike-Info.plist; APP="dist/Tapspike.app" ;;
  *) echo "알 수 없는 대상: $TARGET" >&2; exit 2 ;;
esac

security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY=-

swift build -c release --product "$PRODUCT"
BIN="$(swift build -c release --show-bin-path)/$PRODUCT"

[[ "$TARGET" == mixer ]] && pkill -x Mixer || true
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
install -m 755 "$BIN" "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST" "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify "$APP"
echo "완료: $APP"
[[ "$TARGET" == mixer ]] && open "$APP" || true
