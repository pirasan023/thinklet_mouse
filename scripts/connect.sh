#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != '--prepare' ]; then
  exec /bin/bash ./Start.command
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
command -v adb >/dev/null || { echo 'adb が必要です'; exit 1; }
adb start-server
# Refuse ambiguous targets. Never install on an arbitrary attached phone.
SERIAL="${THINKLET_SERIAL:-}"
if [ -z "$SERIAL" ]; then
  SERIALS=()
  while IFS= read -r line; do
    id="${line%% *}"
    if [[ "$line" == *' device '* ]] && [[ "$line" == *'THINKLET'* ]]; then SERIALS+=("$id"); fi
  done < <(adb devices -l)
  if [ "${#SERIALS[@]}" -ne 1 ]; then
    adb devices -l
    echo 'THINKLETが1台だけ接続されている必要があります。未承認ならUSBデバッグを許可してください。'
    echo '認識されない場合: THINKLET_SERIAL=端末ID ./scripts/connect.sh'
    exit 1
  fi
  SERIAL="${SERIALS[0]}"
fi
adb -s "$SERIAL" install -r outputs/thinklet-handmouse.apk
adb -s "$SERIAL" shell pm grant ai.thinklet.handmouse android.permission.CAMERA
adb -s "$SERIAL" forward tcp:18765 tcp:8765
adb -s "$SERIAL" shell am start -n ai.thinklet.handmouse/.MainActivity
ready=0
for attempt in {1..20}; do
  if curl --fail --silent --max-time 1 http://127.0.0.1:18765/frame -o /dev/null; then ready=1; break; fi
  sleep 0.3
done
if [ "$ready" -ne 1 ]; then
  echo '映像を取得できません。他のカメラアプリを終了して再実行してください。'
  exit 1
fi
echo 'THINKLETに接続しました。'
