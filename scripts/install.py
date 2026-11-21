#!/usr/bin/env python3
"""User-run installer: preserve signer, install atomically, launch one fixed path."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import uuid
from installer_core import replace_app

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = Path('/Applications/THINKLET Hand Mouse.app')

def run(args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)

def install():
    # Do not replace a running executable or terminate a user's app by force.
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'HandMouse'], capture_output=True, text=True)
    for pid in result.stdout.split():
        command = subprocess.run(['/bin/ps', '-p', pid, '-o', 'comm='], capture_output=True, text=True).stdout.strip()
        if 'THINKLET Hand Mouse.app/Contents/MacOS/HandMouse' in command:
            raise RuntimeError('THINKLET Hand Mouseを⌘Qで終了してから、Install.commandを開き直してください。')
    run([sys.executable, ROOT / 'scripts/sign-app.py', '--setup'])
    run(['/bin/bash', ROOT / 'scripts/build.sh', '--mac-only'])
    source = ROOT / 'outputs/THINKLET Hand Mouse.app'
    staging = DESTINATION.parent / f'.thinklet-install-{uuid.uuid4().hex}.app'
    previous = DESTINATION.parent / f'.thinklet-previous-{uuid.uuid4().hex}.app'
    backup = ROOT / 'build/previous-installed-app.app'
    try:
        run(['/usr/bin/ditto', source, staging])
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', staging])
        old = replace_app(staging, DESTINATION, previous)
        if old:
            try:
                if backup.exists():
                    shutil.rmtree(backup)
                run(['/usr/bin/ditto', old, backup])
                shutil.rmtree(old)
            except (OSError, subprocess.CalledProcessError):
                print(f'旧版は次の場所に保持しました：{old}', file=sys.stderr)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print('\nインストール完了：/Applications/THINKLET Hand Mouse.app')
    print('起動後に「操作開始」を押してください。今回の署名を一度だけ許可する必要があります。')
    print('次回以降の更新でも、この鍵・アプリID・インストール先を維持します。')
    run(['/usr/bin/open', '-R', DESTINATION])
    run(['/usr/bin/open', '-n', DESTINATION])

if __name__ == '__main__':
    try:
        install()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f'\nインストールを完了できませんでした：{error}', file=sys.stderr)
        sys.exit(1)
