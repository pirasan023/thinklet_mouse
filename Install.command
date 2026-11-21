#!/bin/bash
cd "$(dirname "$0")" || exit 1
python3 scripts/install.py
result=$?
if [ "$result" -ne 0 ]; then
  echo '処理を中止しました。上のエラーを確認してください。Enterで閉じます。'
  read -r
fi
exit "$result"
