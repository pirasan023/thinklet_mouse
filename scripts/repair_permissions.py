#!/usr/bin/env python3
"""Reset only this app's stale privacy records; do not rebuild or re-sign it."""
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
APP = Path('/Applications/THINKLET Hand Mouse.app')
BUNDLE_ID = 'ai.thinklet.handmouse.mac'
report = []

def log(message):
    print(message, flush=True)
    report.append(message)

def run(args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    log(f'$ {" ".join(str(arg) for arg in args)}\n{result.stdout}{result.stderr}')
    if result.returncode:
        raise RuntimeError(f'処理を中止しました（終了コード {result.returncode}）。別のサービスや他のアプリの登録はリセットしません。')

def repair():
    if not APP.exists():
        raise RuntimeError('インストール済みアプリが見つかりません。')
    data = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    if data.get('CFBundleIdentifier') != BUNDLE_ID:
        raise RuntimeError('対象アプリのIDが違うため、リセットを中止しました。')
    processes = subprocess.run(['/usr/bin/pgrep', '-x', 'HandMouse'], capture_output=True, text=True)
    for pid in processes.stdout.split():
        command = subprocess.run(['/bin/ps', '-p', pid, '-o', 'comm='], capture_output=True, text=True).stdout
        if 'THINKLET Hand Mouse.app/Contents/MacOS/HandMouse' in command:
            raise RuntimeError('先にTHINKLET Hand Mouseを⌘Qで終了してください。その後、RepairPermissions.commandを開き直してください。')
    log('アプリの再ビルド・再署名・再インストールは行いません。')
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(APP)])
    for service in ('Accessibility', 'PostEvent', 'ListenEvent'):
        run(['/usr/bin/tccutil', 'reset', service, BUNDLE_ID])
    log('THINKLETだけの許可登録をリセットしました。')
    log('設定画面の「＋」から /Applications/THINKLET Hand Mouse.app を追加してオンにしてください。')
    log('追加後にアプリを開いて「操作開始」を押してください。入力監視の許可を求められた場合もこのアプリを選んでください。')
    run(['/usr/bin/open', '-R', APP])
    run(['/usr/bin/open', 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility'])

if __name__ == '__main__':
    try:
        repair()
    except (OSError, RuntimeError, plistlib.InvalidFileException) as error:
        log(str(error))
        result = 1
    else:
        result = 0
    destination = ROOT / 'build/permission-repair.txt'
    destination.parent.mkdir(exist_ok=True)
    destination.write_text('\n'.join(report))
    print(f'記録：{destination}')
    sys.exit(result)
