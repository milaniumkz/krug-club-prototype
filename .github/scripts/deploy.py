"""GitHub runner deploy: verify the user-confirmed SSH key BEFORE password auth."""
import base64,hashlib,json,os,secrets,shlex,socket,sys,time,urllib.request
from pathlib import Path
import paramiko
HOST='109.235.119.144';DOMAIN='qazaqmetal.109.235.119.144.sslip.io'
EXPECTED='SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'
PACKAGE='https://github.com/milaniumkz/krug-club-prototype/releases/download/qmetplus-2.4.0-2026-11-20/QMETplus_full_project.zip'
SHA='eb55b3e3355b48e067df98bc31917c741b7b09e8104ad3d605354e6ea7f1ddb1'
ASSETS_PACKAGE='https://github.com/milaniumkz/krug-club-prototype/releases/download/qazaqmetal-2.2.1-2026-11-18/QazaqMetal_demo_assets.zip'
ASSETS_SHA='f182e31a8f08045d9b4074cc87c08a33d013992e0e0afbcd3e975f2c7cbe6941'
password=os.environ.pop('DEPLOY_SSH_PASSWORD','')
key_path=os.environ.get('DEPLOY_KEY_FILE','')
if not password and not key_path:raise SystemExit('Configure a deployment SSH key or password')
transport=paramiko.Transport(socket.create_connection((HOST,22),timeout=20))
transport.get_security_options().key_types=('ssh-ed25519',)
transport.start_client(timeout=20)
transport.set_keepalive(30)
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
sftp.get_channel().settimeout(45)
def command(value,stdin=None,timeout=2400):
    channel=transport.open_session(timeout=30);channel.settimeout(timeout);channel.exec_command(value)
    if stdin is not None:channel.sendall(stdin)
    channel.shutdown_write()
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
    command('curl -fL --retry 3 --connect-timeout 15 --max-time 180 '+shlex.quote(PACKAGE)+' -o /opt/qazaqmetal/incoming/project.zip')
    command("echo '"+SHA+"  /opt/qazaqmetal/incoming/project.zip' | sha256sum --check --status")
    for name in ('provision.py','seed_demo.py'):
        sftp.put('.github/scripts/'+name,'/opt/qazaqmetal/incoming/'+name)
    command('python3 /opt/qazaqmetal/incoming/provision.py')
    command('curl -fL --retry 3 --connect-timeout 15 --max-time 120 '+shlex.quote(ASSETS_PACKAGE)+' -o /opt/qazaqmetal/incoming/demo-assets.zip')
    command("echo '"+ASSETS_SHA+"  /opt/qazaqmetal/incoming/demo-assets.zip' | sha256sum --check --status")
    command("python3 -c \"import zipfile; zipfile.ZipFile('/opt/qazaqmetal/incoming/demo-assets.zip').extractall('/opt/qazaqmetal/incoming/demo-assets')\"")
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
    for portal in ('qazaqmetalpartners.109.235.119.144.sslip.io','qazaqmetaladmin.109.235.119.144.sslip.io'):
        for attempt in range(40):
            try:
                with urllib.request.urlopen('https://'+portal+'/api/health',timeout=15) as response:
                    assert json.load(response)=={'status':'ok'}
                break
            except Exception:
                time.sleep(3)
        else:raise RuntimeError('Role portal HTTPS not healthy: '+portal)
    # Read only first-login flags; existing personal passwords stay unchanged.
    flags_code = "from app.db import SessionLocal,User,Organization; from sqlalchemy import select; import json; db=SessionLocal(); org=db.scalar(select(Organization).where(Organization.code=='DEMO')); rows=db.scalars(select(User).where(((User.employee_number.in_(['01','02'])) & (User.organization_id==org.id)) | User.username.in_(['partner01','partner02']))).all(); print(json.dumps({(u.employee_number if u.role=='member' else u.username):u.must_change_password for u in rows})); db.close()"
    flags = json.loads(command('cd /opt/qazaqmetal/current && docker compose exec -T api python -c '+shlex.quote(flags_code)).strip().splitlines()[-1])
    results=[]
    created_sessions=[]
    for identifier in ('01','02','partner01','partner02'):
        if not flags[identifier]:
            results.append({'account':identifier,'existing_personal_password':'preserved'})
            continue
        origin='https://'+(DOMAIN if identifier in ('01','02') else 'qazaqmetalpartners.109.235.119.144.sslip.io')
        req=urllib.request.Request(origin+'/api/auth/login',data=json.dumps({'identifier':identifier,'password':'123456'}).encode(),headers={'Content-Type':'application/json','X-QM-Client':'web'})
        with urllib.request.urlopen(req,timeout=20) as response:login=json.load(response)
        assert login['user']['must_change_password'] is True
        created_sessions.append(hashlib.sha256(login['token'].encode()).hexdigest())
        req=urllib.request.Request(origin+'/api/auth/me',headers={'Authorization':'Bearer '+login['token']})
        with urllib.request.urlopen(req,timeout=20) as response:assert json.load(response)['id']==login['user']['id']
        results.append({'account':identifier,'login':'PASS','first_password_change':'required','session':'PASS'})
    if created_sessions:
        cleanup_code="from app.db import SessionLocal,Session; from sqlalchemy import delete; import json,sys; db=SessionLocal(); db.execute(delete(Session).where(Session.id.in_(json.load(sys.stdin)))); db.commit(); db.close(); print('Only verification sessions removed')"
        command('cd /opt/qazaqmetal/current && docker compose exec -T api python -c '+shlex.quote(cleanup_code),json.dumps(created_sessions).encode())
    Path('deployment-output/verification.json').write_text(json.dumps({'url':'https://'+DOMAIN,'https':'verified','health':health,'accounts':results},indent=2))
    print('DEPLOYMENT VERIFIED: https://'+DOMAIN,flush=True)
finally:
    sftp.close();transport.close()
