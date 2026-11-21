#!/bin/bash
cd "$(dirname "$0")" || exit 1
python3 scripts/repair_permissions.py
result=$?
echo 'Enterで閉じます。'
read -r
exit "$result"
