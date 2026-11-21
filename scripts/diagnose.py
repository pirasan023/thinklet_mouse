#!/usr/bin/env python3
"""Read-only permission diagnostics, run in the user's normal Terminal context."""
import datetime
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP = Path('/Applications/THINKLET Hand Mouse.app')
sections = []

def record(title, value):
    text = f'\n=== {title} ===\n{value}\n'
    print(text, flush=True)
    sections.append(text)

def command(title, args, timeout=20):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        output = result.stdout + result.stderr
        record(title, f'exit={result.returncode}\n{output[-70000:]}')
        return result
    except (OSError, subprocess.TimeoutExpired) as error:
        record(title, str(error))
        return None

record('診断環境', f'{datetime.datetime.now().astimezone().isoformat()}\nUID={os.getuid()}\nアプリや権限設定は変更しません。')
info = APP / 'Contents/Info.plist'
if info.exists():
    data = plistlib.loads(info.read_bytes())
    record('対象アプリ', f'場所={APP}\nバージョン={data.get("CFBundleShortVersionString")}\nID={data.get("CFBundleIdentifier")}')
else:
    record('対象アプリ', 'インストール先にアプリがありません。')
command('署名の検証（通常のユーザー環境）', ['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=4', str(APP)])
command('署名の識別情報', ['/usr/bin/codesign', '-d', '--verbose=4', '-r-', str(APP)])
processes = command('実行中の対象プロセス', ['/usr/bin/pgrep', '-x', 'HandMouse'])
if processes:
    for pid in processes.stdout.split():
        if pid.isdigit():
            command(f'プロセス {pid}', ['/bin/ps', '-p', pid, '-o', 'pid=,ppid=,comm='])
predicate = '(process == "tccd") AND (eventMessage CONTAINS[c] "ai.thinklet.handmouse.mac" OR eventMessage CONTAINS[c] "HandMouse")'
command('このアプリに関係する許可ログ（直近10分）', ['/usr/bin/log', 'show', '--last', '10m', '--style', 'compact', '--info', '--predicate', predicate], timeout=40)
destination = ROOT / 'build/permission-diagnostics.txt'
destination.parent.mkdir(exist_ok=True)
destination.write_text(''.join(sections))
print(f'\n診断を保存しました：{destination}')
print('キーの内容やカメラ画像は取得していません。アプリの再ビルド・権限リセットも行っていません。')
