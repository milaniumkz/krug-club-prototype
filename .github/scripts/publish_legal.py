"""Publish only reviewed public HTML; preserve application and database state."""
import base64
import hashlib
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
    print('Published public pages; application services were not restarted.')
finally:
    transport.close()
