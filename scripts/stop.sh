#!/bin/bash
set -euo pipefail
# Stop Mac first so an in-progress drag is released.
osascript -e 'tell application id "ai.thinklet.handmouse.mac" to quit' || true
export PATH="/opt/homebrew/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
if [ -n "${THINKLET_SERIAL:-}" ]; then
 adb -s "$THINKLET_SERIAL" shell am force-stop ai.thinklet.handmouse
 adb -s "$THINKLET_SERIAL" forward --remove tcp:18765
else
 echo 'THINKLET側のカメラ終了: THINKLET_SERIAL=端末ID ./scripts/stop.sh'
fi
