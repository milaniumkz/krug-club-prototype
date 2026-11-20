"""Run interactively by the owner to choose or create the Android upload key."""
import getpass
import os
from pathlib import Path
import secrets
import subprocess
import sys

if not sys.stdin.isatty():
    raise SystemExit('Run this script yourself in Terminal; an interactive owner action is required.')
private = Path.home() / '.codex/private/qmet-store'
private.mkdir(parents=True, exist_ok=True, mode=0o700)
keytool = '/opt/homebrew/opt/openjdk@17/bin/keytool'
existing = private / 'key.properties'
print('1 — Select the existing private QMET upload key\n2 — Create a separate new upload key')
choice = input('Your choice: ').strip()
if choice == '1':
    if not existing.is_file():
        raise SystemExit('No existing key configuration found.')
    values = dict(line.split('=',1) for line in existing.read_text().splitlines() if '=' in line)
    result = subprocess.run([keytool, '-list', '-v', '-keystore', values['storeFile'], '-alias', values['keyAlias'], '-storepass:env', 'QMET_SIGN_PASSWORD'],
                            env={**os.environ, 'QMET_SIGN_PASSWORD': values['storePassword']}, capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines():
        if 'SHA256:' in line:
            print(line.strip())
    if input('Type USE to select this existing key: ').strip() != 'USE':
        raise SystemExit('No signing configuration changed.')
elif choice == '2':
    alias = input('Key alias [qmet-upload]: ').strip() or 'qmet-upload'
    password = getpass.getpass('New private keystore password (minimum 6 characters): ')
    if len(password) < 6 or password != getpass.getpass('Confirm password: '):
        raise SystemExit('Password confirmation failed; no key created.')
    key_password = getpass.getpass('Key password (Enter to use the keystore password): ') or password
    store = private / ('qmet-upload-' + secrets.token_hex(4) + '.jks')
    subprocess.run([keytool, '-genkeypair', '-keystore', str(store), '-alias', alias,
                    '-storepass:env', 'QMET_STORE_PASSWORD', '-keypass:env', 'QMET_KEY_PASSWORD',
                    '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000', '-storetype', 'JKS', '-dname', 'CN=QMET upload key'],
                   env={**os.environ, 'QMET_STORE_PASSWORD': password, 'QMET_KEY_PASSWORD': key_password}, check=True)
    store.chmod(0o600)
    values = dict(storeFile=str(store), storePassword=password, keyPassword=key_password, keyAlias=alias)
    existing.write_text('\n'.join(f'{k}={v}' for k,v in values.items()) + '\n')
    existing.chmod(0o600)
else:
    raise SystemExit('No signing configuration changed.')
client_file = Path(__file__).resolve().parents[1] / 'client/android/key.properties'
client_file.write_bytes(existing.read_bytes())
client_file.chmod(0o600)
(private / 'owner-selected-signing').write_text('Selected interactively by the owner.\n')
print('Private signing configured. Passwords and the keystore remain outside Git.')
