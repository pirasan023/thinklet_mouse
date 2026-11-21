#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
BT="$SDK/build-tools/35.0.0"
JDK="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export JAVA_HOME="$JDK"
mkdir -p build/classes build/dex outputs
if [ "${1:-}" != '--mac-only' ]; then
"$JDK/bin/javac" -source 8 -target 8 -bootclasspath "$SDK/platforms/android-35/android.jar:$BT/core-lambda-stubs.jar" -d build/classes android/src/ai/thinklet/handmouse/MainActivity.java
"$BT/d8" --lib "$SDK/platforms/android-35/android.jar" --min-api 26 --output build/dex build/classes/ai/thinklet/handmouse/*.class
"$BT/aapt" package -f -M android/AndroidManifest.xml -I "$SDK/platforms/android-35/android.jar" -F build/unsigned.apk
(cd build/dex && "$BT/aapt" add ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 build/unsigned.apk build/aligned.apk
if [ ! -f build/debug.keystore ]; then
 "$JDK/bin/keytool" -genkeypair -keystore build/debug.keystore -storepass android -keypass android -alias androiddebugkey -dname 'CN=THINKLET Hand Mouse Development' -keyalg RSA -validity 3650 -noprompt
fi
"$BT/apksigner" sign --ks build/debug.keystore --ks-pass pass:android --out outputs/thinklet-handmouse.apk build/aligned.apk
fi
APP="build/app-stage/THINKLET Hand Mouse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/scripts" "$APP/Contents/Resources/outputs"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/build/swift-cache" -O mac/GestureEngine.swift mac/CameraCapture.swift mac/main.swift -o "$APP/Contents/MacOS/HandMouse" -framework AppKit -framework Vision -framework ApplicationServices -framework Security -framework AVFoundation
cp mac/Info.plist "$APP/Contents/Info.plist"
cp scripts/connect.sh "$APP/Contents/Resources/scripts/connect.sh"
if [ -f outputs/thinklet-handmouse.apk ]; then
  cp outputs/thinklet-handmouse.apk "$APP/Contents/Resources/outputs/thinklet-handmouse.apk"
fi
python3 scripts/sign-app.py "$APP"
ditto "$APP" 'outputs/THINKLET Hand Mouse.app'
printf 'Build complete: %s/outputs\n' "$ROOT"
