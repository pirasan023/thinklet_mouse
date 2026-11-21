#!/usr/bin/env python3
"""Create the project's persistent local signing key; never import it into a keychain."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
directory = root / '.local-signing'
directory.mkdir(mode=0o700, exist_ok=True)
os.chmod(directory, 0o700)
identity = directory / 'identity.p12'
password = directory / 'password'
if identity.exists():
    if not password.exists():
        raise SystemExit('Signing password is missing. Restore .local-signing; do not generate a new identity.')
    raise SystemExit(0)
if any(directory.iterdir()):
    raise SystemExit('Incomplete signing identity. Restore .local-signing before building; identity will not be replaced automatically.')
os.umask(0o077)
password.write_text(os.urandom(32).hex() + '\n')
configuration = directory / 'certificate.cnf'
configuration.write_text('''[req]
prompt = no
distinguished_name = name
x509_extensions = signing
[name]
CN = THINKLET Hand Mouse Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
''')
def run(*args, env=None):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if result.returncode:
        raise SystemExit(result.stderr.decode(errors='replace'))
run('/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:3072', '-sha256', '-days', '3650',
    '-config', str(configuration), '-keyout', str(directory / 'private.key'),
    '-out', str(directory / 'certificate.pem'), '-passout', f'file:{password}')
run('/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(directory / 'private.key'),
    '-in', str(directory / 'certificate.pem'), '-out', str(identity),
    '-passin', f'file:{password}', '-passout', 'env:THINKLET_SIGNING_PASSWORD',
    env={**os.environ, 'THINKLET_SIGNING_PASSWORD': password.read_text().strip()})
print('Created persistent local signing identity. Keep .local-signing private and retain it across builds.')
