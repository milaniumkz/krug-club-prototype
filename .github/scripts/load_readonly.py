"""Owner-authorized single read-only burst. Does not create discount visits or touch real members."""
import asyncio,base64,collections,hashlib,json,os,secrets,shlex,socket,time,uuid
from pathlib import Path
import aiohttp,httpx,paramiko
BASE='https://qazaqmetal.109.235.119.144.sslip.io';COUNT=5000
password=os.environ.pop('DEPLOY_SSH_PASSWORD','');ssh=paramiko.Transport(socket.create_connection(('109.235.119.144',22),timeout=20));ssh.get_security_options().key_types=('ssh-ed25519',);ssh.start_client(timeout=20)
fp='SHA256:'+base64.b64encode(hashlib.sha256(ssh.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fp,'SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'):raise SystemExit('Host identity mismatch')
ssh.auth_password('root',password);password=None

def remote(code,payload):
 c=ssh.open_session();c.exec_command('cd /opt/qazaqmetal/current && docker compose exec -T api python -c '+shlex.quote(code));c.sendall(json.dumps(payload).encode());c.shutdown_write();data=c.makefile('r').read();c.makefile_stderr('r').read()
 if c.recv_exit_status():raise RuntimeError('Private QA operation failed')
 return json.loads(data) if data.strip() else None
qa='qa-load-'+uuid.uuid4().hex[:12];personal=secrets.token_urlsafe(24);uid=None
try:
 info=remote("""import json,sys,os
from sqlalchemy import select
from app.db import SessionLocal,Organization,User
from app.security import hash_password
p=json.load(sys.stdin)
with SessionLocal() as db:
 org=db.scalar(select(Organization).where(Organization.code=='DEMO'))
 assert org and org.active
 user=User(organization_id=org.id,employee_number=p['qa'],name='QA · нагрузочная проверка',role='member',must_change_password=False,password_hash=hash_password(p['password']))
 db.add(user);db.commit();print(json.dumps({'id':user.id,'cpu_cores':os.cpu_count()}))
""",{'qa':qa,'password':personal});uid=info['id']
 login=httpx.post(BASE+'/api/auth/login',json={'identifier':qa,'password':personal},timeout=30);assert login.status_code==200;token=login.json()['token']
 async def measure():
  connector=aiohttp.TCPConnector(limit=COUNT,limit_per_host=COUNT,ttl_dns_cache=300)
  timeout=aiohttp.ClientTimeout(total=120,sock_connect=60,sock_read=90)
  async with aiohttp.ClientSession(connector=connector,timeout=timeout,headers={'Authorization':'Bearer '+token}) as client:
   async with client.get(BASE+'/api/catalog?limit=30') as r:assert r.status==200;await r.read()
   ready=asyncio.Event();latencies=[];statuses=[];starts=[];inflight=0;peak=0
   async def hit():
    nonlocal inflight,peak
    await ready.wait();start=time.perf_counter();starts.append(start);inflight+=1;peak=max(peak,inflight)
    try:
     async with client.get(BASE+'/api/catalog?limit=30') as response:await response.read();statuses.append(str(response.status))
    except Exception as error:statuses.append(type(error).__name__)
    finally:latencies.append(time.perf_counter()-start);inflight-=1
   tasks=[asyncio.create_task(hit()) for _ in range(COUNT)];began=time.perf_counter();ready.set();await asyncio.gather(*tasks);elapsed=time.perf_counter()-began
   ordered=sorted(latencies)
   return {'requests':COUNT,'requested_concurrency':COUNT,'peak_client_inflight':peak,'endpoint':'GET /api/catalog?limit=30','read_only':True,'statuses':dict(collections.Counter(statuses)),'all_requests_200':statuses.count('200')==COUNT,'duration_seconds':round(elapsed,3),'dispatch_span_ms':round((max(starts)-min(starts))*1000,2),'latency_p50_seconds':round(ordered[len(ordered)//2],3),'latency_p95_seconds':round(ordered[int(len(ordered)*.95)-1],3),'latency_max_seconds':round(max(ordered),3),'observed_average_rps':round(COUNT/elapsed,2),'cpu_cores':info['cpu_cores']}
 report=asyncio.run(measure());health=httpx.get(BASE+'/api/health',timeout=30);report['health_after']=health.status_code;assert health.status_code==200
 Path('load-verification').mkdir(exist_ok=True);Path('load-verification/results.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
finally:
 if uid:
  remote("""import sys,json
from sqlalchemy import select,delete
from app.db import SessionLocal,User,Audit,Session
p=json.load(sys.stdin)
with SessionLocal() as db:
 user=db.get(User,p['id']);assert user and user.employee_number==p['qa']
 db.execute(delete(Audit).where(Audit.actor_id==user.id));db.execute(delete(Session).where(Session.user_id==user.id));db.delete(user);db.commit()
""",{'id':uid,'qa':qa})
 ssh.close()
