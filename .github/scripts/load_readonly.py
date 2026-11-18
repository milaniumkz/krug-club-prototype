"""Owner-authorized bounded staged read-only capacity test. Does not create discount visits or touch real members."""
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
  stages=[];stop_reason='maximum configured concurrency reached';total_budget=60000
  connector=aiohttp.TCPConnector(limit=5000,limit_per_host=5000,ttl_dns_cache=300)
  timeout=aiohttp.ClientTimeout(total=15,sock_connect=10,sock_read=12)
  async with aiohttp.ClientSession(connector=connector,timeout=timeout,headers={'Authorization':'Bearer '+token}) as client:
   async with client.get(BASE+'/api/catalog?limit=30') as r:assert r.status==200;await r.read()
   for concurrency in [1,10,25,50,100,250,500,1000,2500,5000]:
    latencies=[];statuses=[];active=0;peak=0;issued=0;abort=asyncio.Event();health_checks=[]
    began=time.perf_counter();deadline=began+15;stage_budget=min(10000,total_budget)
    async def worker():
     nonlocal active,peak,issued
     while time.perf_counter()<deadline and issued<stage_budget and not abort.is_set():
      issued+=1;start=time.perf_counter();active+=1;peak=max(peak,active)
      try:
       async with client.get(BASE+'/api/catalog?limit=30') as response:
        await response.read();statuses.append(str(response.status))
      except Exception as error:statuses.append(type(error).__name__)
      finally:latencies.append(time.perf_counter()-start);active-=1
      if len(statuses)>=50 and sum(v!='200' for v in statuses)/len(statuses)>.01:abort.set()
    async def monitor():
     failures=0
     while time.perf_counter()<deadline and not abort.is_set():
      try:
       async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=4)) as probe:
        start=time.perf_counter()
        async with probe.get(BASE+'/api/health') as response:
         await response.read();ok=response.status==200
         health_checks.append({'status':response.status,'seconds':round(time.perf_counter()-start,3)})
      except Exception:ok=False;health_checks.append({'status':'timeout'})
      failures=0 if ok else failures+1
      if failures>=2:abort.set();return
      await asyncio.sleep(2)
    watcher=asyncio.create_task(monitor());await asyncio.gather(*(worker() for _ in range(concurrency)))
    watcher.cancel()
    try:await watcher
    except asyncio.CancelledError:pass
    elapsed=time.perf_counter()-began;ordered=sorted(latencies);n=len(statuses);errors=sum(v!='200' for v in statuses);total_budget-=n
    stage={'concurrency':concurrency,'peak_client_inflight':peak,'requests':n,'duration_seconds':round(elapsed,3),'statuses':dict(collections.Counter(statuses)),'successful_rps':round(statuses.count('200')/elapsed,2),'error_percent':round(100*errors/max(n,1),3),'p50_ms':round(ordered[n//2]*1000,2),'p95_ms':round(ordered[max(0,int(n*.95)-1)]*1000,2),'max_ms':round(max(ordered)*1000,2),'health_checks':health_checks}
    stages.append(stage);print(json.dumps(stage),flush=True)
    Path('load-verification').mkdir(exist_ok=True);Path('load-verification/progress.json').write_text(json.dumps(stages,indent=2))
    if abort.is_set() or errors/max(n,1)>.01:stop_reason='error or availability safety threshold';break
    if stage['p95_ms']>3000:stop_reason='p95 exceeded 3000 ms; higher concurrency would increase queueing';break
    if total_budget<=0:stop_reason='bounded request budget reached';break
    await asyncio.sleep(3)
  return {'target_requested_rps':10000000,'target_verified':False,'method':'closed-loop staged HTTPS authenticated catalog read; one external GitHub runner, one temporary test member; not a distributed open-loop RPS test','endpoint':'GET /api/catalog?limit=30','read_only':True,'stage_duration_seconds':15,'cpu_cores':info['cpu_cores'],'stages':stages,'stop_reason':stop_reason,'best_observed_successful_rps':max(x['successful_rps'] for x in stages)}
 report=asyncio.run(measure())
 try:
  health=httpx.get(BASE+'/api/health',timeout=15);report['health_after']=health.status_code
 except Exception as e:report['health_after']=type(e).__name__
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
