"""Publish only reviewed public HTML; preserve application and database state."""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import socket

import paramiko

HOST = '109.235.119.144'
EXPECTED = 'SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'
password = os.environ.pop('DEPLOY_SSH_PASSWORD')
transport = paramiko.Transport(socket.create_connection((HOST, 22), timeout=20))
transport.get_security_options().key_types = ('ssh-ed25519',)
transport.start_client(timeout=20)
fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(
    transport.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fingerprint, EXPECTED):
    transport.close()
    raise SystemExit('SSH identity mismatch; credentials were not sent')
transport.auth_password('root', password)
password = None

def command(value):
    channel = transport.open_session(timeout=20)
    channel.settimeout(60)
    channel.exec_command(value)
    output = channel.makefile('rb').read().decode()
    error = channel.makefile_stderr('rb').read().decode()
    if channel.recv_exit_status():
        raise RuntimeError(error)
    channel.close()
    return output

try:
    command('install -d -m 755 /opt/qazaqmetal/current/legal /opt/qazaqmetal/current/web/legal')
    with paramiko.SFTPClient.from_transport(transport) as sftp:
        for page in sorted(Path('platform/legal').glob('*.html')):
            for directory in ('legal', 'web/legal'):
                remote = '/opt/qazaqmetal/current/' + directory + '/' + page.name
                sftp.put(str(page), remote + '.new')
                sftp.chmod(remote + '.new', 0o644)
                sftp.posix_rename(remote + '.new', remote)
    command('cd /opt/qazaqmetal/current && docker compose cp web/legal api:/web/')
    patch = {'support_email': 'milaniumkz@yandex.kz', 'support_phone': '+77086362153',
             'support_url': 'https://qazaqmetal.109.235.119.144.sslip.io/legal/support.html'}
    # Lock and merge three public contact fields; preserve all owner settings.
    code = """
from app.db import SessionLocal, AppSetting, Audit, now
from app.app_config import KEY, Settings
from app import session_events
from sqlalchemy import select
import json
patch = json.loads(PATCH)
with SessionLocal() as db:
    row = db.scalar(select(AppSetting).where(AppSetting.key == KEY).with_for_update())
    if row is None:
        row = AppSetting(key=KEY, data={}, revision=0)
        db.add(row)
    changed = [k for k, v in patch.items() if row.data.get(k) != v]
    if changed:
        row.data = Settings.model_validate({**row.data, **patch}).model_dump()
        row.revision += 1
        row.updated_at = now()
        db.add(Audit(actor_id=None, action='app_settings_changed', target=KEY,
                     detail={'revision': row.revision, 'changed_fields': changed, 'source': 'public_contact_deployment'}))
        session_events.publish(db, 'catalog')
        db.commit()
print('Public support settings synchronized')
""".replace('PATCH', repr(json.dumps(patch)))
    print(command('cd /opt/qazaqmetal/current && docker compose exec -T api python -c ' + shlex.quote(code)))
    print('Published public pages; application services were not restarted.')
finally:
    transport.close()
