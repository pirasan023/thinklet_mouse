#!/bin/bash
cd "$(dirname "$0")" || exit 1
APP='/Applications/THINKLET Hand Mouse.app'
if [ ! -d "$APP" ]; then
  exec ./Install.command
fi
installed=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null)
latest=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' mac/Info.plist)
if [ "$installed" != "$latest" ]; then
  exec ./Install.command
fi
echo "固定の起動先: $APP"
/usr/bin/open "$APP"
result=$?
if [ "$result" -ne 0 ]; then
  echo '起動できませんでした。上のエラーを確認してください。Enterで閉じます。'
  read -r
fi
exit "$result"
