#!/usr/bin/env python3
"""Sign with a persistent project identity. Never fall back to ad-hoc signing."""
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / '.local-signing'
KEYCHAIN = LOCAL / 'signing.keychain-db'
LABEL = 'THINKLET Hand Mouse Local Development'

def run(args, *, secret=False):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    if result.returncode:
        # Do not expose a command line containing a keychain password.
        raise RuntimeError(f'{Path(str(args[0])).name} failed ({result.returncode}):\n{result.stderr.strip()}')
    return result.stdout + result.stderr

def setup():
    run([sys.executable, ROOT / 'scripts/ensure-signing.py'])
    password = (LOCAL / 'password').read_text().strip()
    if not KEYCHAIN.exists():
        run(['/usr/bin/security', 'create-keychain', '-p', password, KEYCHAIN], secret=True)
    run(['/usr/bin/security', 'unlock-keychain', '-p', password, KEYCHAIN], secret=True)
    certificates = subprocess.run(['/usr/bin/security', 'find-certificate', '-c', LABEL, str(KEYCHAIN)], capture_output=True)
    if certificates.returncode:
        run(['/usr/bin/security', 'import', LOCAL / 'identity.p12', '-k', KEYCHAIN,
             '-P', password, '-T', '/usr/bin/codesign'], secret=True)
        run(['/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
             '-s', '-k', password, KEYCHAIN], secret=True)
    print('Persistent project signing identity ready. Global certificate trust was not changed.')

def sign(app):
    if not KEYCHAIN.exists():
        raise RuntimeError('Persistent signing keychain is not configured. Run Install.command in Finder first. Ad-hoc signing is disabled.')
    password = (LOCAL / 'password').read_text().strip()
    run(['/usr/bin/security', 'unlock-keychain', '-p', password, KEYCHAIN], secret=True)
    certificate = run(['/usr/bin/security', 'find-certificate', '-c', LABEL, '-Z', KEYCHAIN])
    match = re.search(r'SHA-1 hash:\s*([0-9A-Fa-f]{40})', certificate)
    if not match:
        raise RuntimeError('The original signing certificate was not found. Restore .local-signing; do not create a replacement key.')
    pinned = f'designated => identifier "ai.thinklet.handmouse.mac" and certificate leaf = H"{match.group(1)}"'
    run(['/usr/bin/codesign', '--force', '--timestamp=none', '--keychain', KEYCHAIN,
         '--sign', match.group(1), '--requirements', '=' + pinned, app])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
    requirement = run(['/usr/bin/codesign', '-d', '-r-', app])
    normalized = [line.lstrip('# ').strip() for line in requirement.splitlines()]
    designated = next((line for line in normalized if line.startswith('designated =>')), None)
    if not designated or 'cdhash ' in designated or match.group(1).lower() not in designated.lower():
        raise RuntimeError('Signing did not produce a certificate-based designated requirement.')
    recorded = LOCAL / 'designated-requirement.txt'
    if recorded.exists() and recorded.read_text().strip() != designated:
        raise RuntimeError('Signing identity changed. Installation stopped to preserve existing privacy permissions.')
    recorded.write_text(designated + '\n')
    print('Certificate signature verified; designated requirement unchanged across project updates.')

if __name__ == '__main__':
    try:
        if len(sys.argv) == 2 and sys.argv[1] == '--setup':
            setup()
        elif len(sys.argv) == 2:
            sign(Path(sys.argv[1]).resolve())
        else:
            raise RuntimeError('Usage: sign-app.py --setup | App.app')
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
