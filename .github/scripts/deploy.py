"""GitHub runner deploy: verify the user-confirmed SSH key BEFORE password auth."""
import base64,hashlib,json,os,secrets,shlex,socket,sys,time,urllib.request
from pathlib import Path
import paramiko
HOST='109.235.119.144';DOMAIN='qazaqmetal.109.235.119.144.sslip.io'
EXPECTED='SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'
PACKAGE='https://github.com/milaniumkz/krug-club-prototype/releases/download/qazaqmetal-purple-platform-2026-11-18/QazaqMetal_full_project.zip'
SHA='a7d69870cdfbe544e0f8d8cc2db83290d92d8866f4298ebaea160bae0db0fbba'
password=os.environ.pop('DEPLOY_SSH_PASSWORD','')
key_path=os.environ.get('DEPLOY_KEY_FILE','')
if not password and not key_path:raise SystemExit('Configure a deployment SSH key or password')
transport=paramiko.Transport(socket.create_connection((HOST,22),timeout=20))
transport.get_security_options().key_types=('ssh-ed25519',)
transport.start_client(timeout=20)
fingerprint='SHA256:'+base64.b64encode(hashlib.sha256(transport.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fingerprint,EXPECTED):
    transport.close();raise SystemExit('SSH host key changed; password was NOT sent')
print('SSH key matches the fingerprint confirmed by the server owner.',flush=True)
if key_path:
    transport.auth_publickey('root',paramiko.Ed25519Key.from_private_key_file(key_path))
else:
    transport.auth_password('root',password)
password=None
sftp=paramiko.SFTPClient.from_transport(transport)
def command(value,stdin=None,timeout=2400):
    channel=transport.open_session(timeout=30);channel.settimeout(timeout);channel.exec_command(value)
    if stdin is not None:channel.sendall(stdin);channel.shutdown_write()
    out=[]
    while True:
        if channel.recv_ready():
            data=channel.recv(65536).decode(errors='replace');out.append(data);print(data,end='',flush=True)
        if channel.recv_stderr_ready():print(channel.recv_stderr(65536).decode(errors='replace'),end='',flush=True)
        if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():break
        time.sleep(.1)
    status=channel.recv_exit_status();channel.close()
    if status:raise RuntimeError(f'Remote command failed with exit code {status}')
    return ''.join(out)
try:
    command('install -d -m 700 /opt/qazaqmetal/incoming')
    local=Path('project.zip');urllib.request.urlretrieve(PACKAGE,local)
    if hashlib.sha256(local.read_bytes()).hexdigest()!=SHA:raise SystemExit('Release package SHA256 mismatch')
    sftp.put(str(local),'/opt/qazaqmetal/incoming/project.zip')
    command("echo '"+SHA+"  /opt/qazaqmetal/incoming/project.zip' | sha256sum --check --status")
    for name in ('provision.py','seed_demo.py'):
        sftp.put('.github/scripts/'+name,'/opt/qazaqmetal/incoming/'+name)
    command('python3 /opt/qazaqmetal/incoming/provision.py')
    command('install -d -m 755 /opt/qazaqmetal/incoming/demo-assets')
    for file in Path('.github/demo-assets').iterdir():sftp.put(str(file),'/opt/qazaqmetal/incoming/demo-assets/'+file.name)
    command('cd /opt/qazaqmetal/current && docker compose cp /opt/qazaqmetal/incoming/seed_demo.py api:/tmp/seed_demo.py && docker compose cp /opt/qazaqmetal/incoming/demo-assets api:/tmp/qazaqmetal-demo-assets')
    # Admin secret remains only in a root-readable host file, never in public artifacts/logs.
    credentials='/opt/qazaqmetal/shared/admin-initial.json'
    try:
        with sftp.open(credentials) as f:admin=json.load(f)
    except FileNotFoundError:
        admin={'username':'qazaqmetal-admin','password':secrets.token_urlsafe(24)}
        with sftp.open(credentials,'w') as f:f.write(json.dumps(admin))
        sftp.chmod(credentials,0o600)
    seed={'initial_password':'123456','admin_password':admin['password']}
    result=command('cd /opt/qazaqmetal/current && docker compose exec -T api python /tmp/seed_demo.py',json.dumps(seed).encode())
    state=json.loads(result.strip().splitlines()[-1]);Path('deployment-output').mkdir(exist_ok=True)
    Path('deployment-output/demo-partners.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    command('cd /opt/qazaqmetal/current && docker compose exec -T -u 0 api rm -rf /tmp/seed_demo.py /tmp/qazaqmetal-demo-assets')
    # Wait for public ACME certificate; no TLS bypass.
    for attempt in range(60):
        try:
            with urllib.request.urlopen('https://'+DOMAIN+'/api/health',timeout=15) as response:
                health=json.load(response)
            if health=={'status':'ok'}:break
        except Exception as e:
            if attempt%6==0:print('Waiting for HTTPS certificate:',type(e).__name__,flush=True)
            time.sleep(5)
    else:raise RuntimeError('Public HTTPS did not become healthy')
    # Verify requested accounts without changing their temporary passwords.
    results=[]
    for identifier in ('01','02','partner01','partner02'):
        req=urllib.request.Request('https://'+DOMAIN+'/api/auth/login',data=json.dumps({'identifier':identifier,'password':'123456','organization_code':'DEMO' if identifier in ('01','02') else ''}).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=20) as response:login=json.load(response)
        assert login['user']['must_change_password'] is True
        req=urllib.request.Request('https://'+DOMAIN+'/api/auth/me',headers={'Authorization':'Bearer '+login['token']})
        with urllib.request.urlopen(req,timeout=20) as response:assert json.load(response)['id']==login['user']['id']
        req=urllib.request.Request('https://'+DOMAIN+'/api/auth/logout',data=b'',headers={'Authorization':'Bearer '+login['token']},method='POST')
        with urllib.request.urlopen(req,timeout=20):pass
        results.append({'account':identifier,'login':'PASS','first_password_change':'required','session':'PASS'})
    Path('deployment-output/verification.json').write_text(json.dumps({'url':'https://'+DOMAIN,'https':'verified','health':health,'accounts':results},indent=2))
    print('DEPLOYMENT VERIFIED: https://'+DOMAIN,flush=True)
finally:
    sftp.close();transport.close()
