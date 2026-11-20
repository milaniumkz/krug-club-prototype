"""One-time encrypted Firebase handoff over owner-verified SSH. No secrets in logs/artifacts."""
import base64, hashlib, io, json, os, secrets, shlex, socket, sys, time
from pathlib import Path
import paramiko
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
EXPECTED='SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'
t=paramiko.Transport(socket.create_connection(('109.235.119.144',22),timeout=20));t.get_security_options().key_types=('ssh-ed25519',);t.start_client(timeout=20)
fp='SHA256:'+base64.b64encode(hashlib.sha256(t.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fp,EXPECTED):raise SystemExit('SSH fingerprint mismatch before authentication')
t.auth_password('root',os.environ.pop('DEPLOY_SSH_PASSWORD'));t.set_keepalive(30)
s=paramiko.SFTPClient.from_transport(t);root='/opt/qazaqmetal/shared';handoff=root+'/firebase-handoff.pem'
def put(path,data,mode=0o600):
 with s.file(path,'wb') as f:f.write(data)
 s.chmod(path,mode)
def command(cmd):
 ch=t.open_session();ch.exec_command(cmd)
 # Drain both streams to avoid a build-log buffer deadlock; never print secret-bearing output.
 while not ch.exit_status_ready():
  if ch.recv_ready():ch.recv(65536)
  if ch.recv_stderr_ready():ch.recv_stderr(65536)
  time.sleep(.1)
 status=ch.recv_exit_status();ch.close()
 if status:raise RuntimeError('Remote setup failed (exit '+str(status)+'); no credentials logged')
try:
 mode=sys.argv[1]
 if mode=='prepare':
  try:
   with s.file(handoff,'rb') as f:key=serialization.load_pem_private_key(f.read(),None)
  except FileNotFoundError:
   key=rsa.generate_private_key(public_exponent=65537,key_size=3072)
   put(handoff,key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
  out=Path('firebase-setup-public');out.mkdir(exist_ok=True)
  (out/'handoff-public.pem').write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo))
  print('Public encryption key ready; private key retained only on authorized host')
 elif mode=='install':
  env=json.loads(Path('.github/firebase-handoff.encrypted.json').read_text())
  with s.file(handoff,'rb') as f:key=serialization.load_pem_private_key(f.read(),None)
  aes=key.decrypt(base64.b64decode(env['key']),padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
  payload=json.loads(AESGCM(aes).decrypt(base64.b64decode(env['nonce']),base64.b64decode(env['ciphertext']),b'qazaqmetal-firebase-20261120'))
  account=payload['service_account'];assert account['type']=='service_account' and account['project_id']=='qazaqmetal-8a77b'
  put(root+'/firebase_admin.json',json.dumps(account).encode(),0o400);s.chown(root+'/firebase_admin.json',10001,10001)
  with s.file(root+'/.env','rb') as f:lines=f.read().decode().splitlines()
  values={'FIREBASE_ADMIN_FILE':root+'/firebase_admin.json','FIREBASE_CLIENT_CONFIG':"'"+json.dumps(payload['client_config'],separators=(',',':'))+"'",'FIREBASE_WEB_VAPID_KEY':payload['vapid_key']}
  for k,v in values.items():
   lines=[line for line in lines if not line.startswith(k+'=')];lines.append(k+'='+v)
  # Include the push overlay on every later deployment/restart.
  for i,line in enumerate(lines):
   if line.startswith('COMPOSE_FILE=') and 'compose.push.yaml' not in line:lines[i]=line+':compose.push.yaml'
  lines=[line for line in lines if not line.startswith('COMPOSE_PROFILES=')]+['COMPOSE_PROFILES=push']
  put(root+'/.env',('\n'.join(lines)+'\n').encode())
  command('cd /opt/qazaqmetal/current && docker compose config --quiet && docker compose up -d --build --wait --wait-timeout 240')
  command('cd /opt/qazaqmetal/current && docker compose exec -T push python -c "from google.oauth2 import service_account; from google.auth.transport.requests import Request; import os; c=service_account.Credentials.from_service_account_file(os.environ[\'GOOGLE_APPLICATION_CREDENTIALS\'],scopes=[\'https://www.googleapis.com/auth/firebase.messaging\']); c.refresh(Request()); assert c.valid; print(\'Firebase OAuth ready\')"')
  s.remove(handoff)
  print('Firebase credentials installed outside repository; push worker started; Google OAuth verified')
 elif mode=='verify':
  code="import json,os,secrets,requests\nfrom pathlib import Path\nfrom types import SimpleNamespace\nfrom google.oauth2 import service_account\nfrom google.auth.transport.requests import Request\nfrom app.push_worker import message_for\nkey=os.environ['GOOGLE_APPLICATION_CREDENTIALS']\nconfig=json.loads(Path(key).read_text())\nc=service_account.Credentials.from_service_account_file(key,scopes=['https://www.googleapis.com/auth/firebase.messaging']);c.refresh(Request())\nfor role in ['member','partner']:\n n=SimpleNamespace(id='11111111-2222-3333-4444-555555555555',venue_id='11111111-2222-3333-4444-555555555555',kind='new_venue' if role=='member' else 'moderation_approved',title='QAZAQMETAL validation',title_kk='QAZAQMETAL validation',body='Validation only; no delivery',body_kk='Validation only; no delivery')\n message=message_for(n,SimpleNamespace(token='unused',language='ru'),SimpleNamespace(role=role));del message['token'];message['topic']='qa-validation-'+secrets.token_hex(16)\n r=requests.post('https://fcm.googleapis.com/v1/projects/'+config['project_id']+'/messages:send',headers={'Authorization':'Bearer '+c.token},json={'validate_only':True,'message':message},timeout=30)\n assert r.status_code==200, 'FCM production validation status '+str(r.status_code)\n"
  command('cd /opt/qazaqmetal/current && docker compose exec -T push python -c '+shlex.quote(code))
  print('Production FCM HTTPv1 accepted member and partner payloads, including Android/Web/iOS fields; validation only, no message sent')
 else:raise SystemExit('Unknown mode')
finally:s.close();t.close()
