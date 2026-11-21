#!/bin/bash
cd "$(dirname "$0")" || exit 1
python3 scripts/diagnose.py
result=$?
echo 'Enterで閉じます。'
read -r
exit "$result"
