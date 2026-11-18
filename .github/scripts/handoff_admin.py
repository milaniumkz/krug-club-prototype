"""Encrypt the owner-requested administrator login to the local handoff public key."""
import base64,hashlib,os,secrets,socket
from pathlib import Path
import paramiko
from cryptography.hazmat.primitives import serialization,hashes
from cryptography.hazmat.primitives.asymmetric import padding
password=os.environ.pop('DEPLOY_SSH_PASSWORD','')
t=paramiko.Transport(socket.create_connection(('109.235.119.144',22),timeout=15));t.get_security_options().key_types=('ssh-ed25519',);t.start_client(timeout=15)
fp='SHA256:'+base64.b64encode(hashlib.sha256(t.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fp,'SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'):raise SystemExit('Host identity mismatch')
t.auth_password('root',password);password=None
sftp=paramiko.SFTPClient.from_transport(t);sftp.get_channel().settimeout(30)
with sftp.open('/opt/qazaqmetal/shared/admin-initial.json') as f:payload=f.read()
public=serialization.load_pem_public_key(Path('.github/handoff-public.pem').read_bytes())
Path('encrypted-handoff').mkdir(exist_ok=True)
Path('encrypted-handoff/admin-access.enc').write_bytes(public.encrypt(payload,padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None)))
sftp.close();t.close();print('Administrator handoff encrypted; no credentials logged.')
