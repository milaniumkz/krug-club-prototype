"""Verify final signed artifacts, identifiers, APNs entitlements and checksums."""
import hashlib
import re
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[2]
out = root / 'output/releases'
report = []
version, build = re.search(r'^version: (\S+)\+(\d+)', (root / 'platform/client/pubspec.yaml').read_text(), re.M).groups()
for role, prefix in [('member', 'QMETplus'), ('partner', 'QMETplus_Partner')]:
    filename = f'{prefix}_{version}_{build}.ipa'
    with tempfile.TemporaryDirectory(prefix='qmet-verify-') as directory:
        with zipfile.ZipFile(out / filename) as archive:
            archive.extractall(directory)
        app = next((Path(directory) / 'Payload').glob('*.app'))
        check = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
        if check.returncode:
            raise SystemExit('Invalid iOS signature: ' + filename)
        signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True)
        entitlements = plistlib.loads(signed.stdout)
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        expected = 'kz.qazaqmetal.qazaqmetal' + ('.partner' if role == 'partner' else '')
        assert info['CFBundleIdentifier'] == expected
        assert info['CFBundleShortVersionString'] == version
        assert str(info['CFBundleVersion']) == build
        assert entitlements['aps-environment'] == 'production'
        assert entitlements['com.apple.developer.team-identifier'] == 'Z3NZN92Y7P'
        report.append({'file': filename, 'bundle_id': expected, 'version': version, 'build': int(build),
                       'apns_environment': 'production', 'signature_verified': True})
for path in sorted(out.glob(f'*_{version}_{build}.aab')):
    java = Path('/opt/homebrew/opt/openjdk@17/bin/jarsigner')
    check = subprocess.run([str(java) if java.exists() else 'jarsigner', '-verify', str(path)], capture_output=True)
    assert check.returncode == 0, 'Invalid AAB signature: ' + path.name
    with zipfile.ZipFile(path) as archive:
        manifest = archive.read('base/manifest/AndroidManifest.xml')
        expected = b'kz.qazaqmetal.qazaqmetal' + (b'.partner' if 'Partner' in path.name else b'')
        assert expected in manifest
        if 'Partner' not in path.name:
            assert b'kz.qazaqmetal.qazaqmetal.partner' not in manifest
    report.append({'file': path.name, 'signature_verified': True})
for path in sorted(out.iterdir()):
    if path.suffix in ('.ipa', '.aab') and path.stem.endswith(f'_{version}_{build}'):
        report.append({'file': path.name, 'bytes': path.stat().st_size,
                       'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(out / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print('Verified four final signatures, bundle IDs, iOS production APNs and SHA-256 checksums.')
