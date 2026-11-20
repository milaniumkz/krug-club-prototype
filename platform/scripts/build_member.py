"""Explicit, checked production API binding for the member app."""
import argparse,subprocess
from pathlib import Path
from urllib.parse import urlsplit
p=argparse.ArgumentParser()
p.add_argument('--platform',choices=['android','ios'],default='android')
p.add_argument('--mode',choices=['debug','profile','release'],default='debug')
p.add_argument('--api-base-url',default='https://qazaqmetal.109.235.119.144.sslip.io')
p.add_argument('--bundle',action='store_true',help='Build signed Android App Bundle (requires private android/key.properties)')
p.add_argument('--no-codesign',action='store_true')
p.add_argument('--ipa',action='store_true',help='Build signed App Store archive')
a=p.parse_args();url=urlsplit(a.api_base_url)
if a.bundle and a.platform != 'android':p.error('--bundle requires Android')
if a.ipa and (a.platform != 'ios' or a.no_codesign):p.error('--ipa requires iOS signing')
if url.scheme!='https' or not url.hostname or url.hostname in ('localhost','10.0.2.2','127.0.0.1') or url.username or url.password or url.path not in ('','/'):
    raise SystemExit('A public HTTPS API origin is required; emulator/local addresses are forbidden')
command=['flutter','build','appbundle' if a.bundle else 'apk' if a.platform=='android' else 'ipa' if a.ipa else 'ios','--'+a.mode,'--dart-define=PORTAL=member','--dart-define=API_BASE_URL='+a.api_base_url.rstrip('/')]
if a.platform=='ios' and a.no_codesign:command.append('--no-codesign')
subprocess.run(command,cwd=Path(__file__).resolve().parents[1]/'client',check=True)
