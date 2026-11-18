"""Owner-authorized bounded staged read-only capacity test. Does not create discount visits or touch real members."""
import asyncio,base64,collections,hashlib,json,os,secrets,shlex,socket,time,uuid
import subprocess,tempfile,re
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
  stats_code="""import json,os
from pathlib import Path
root=Path('/sys/fs/cgroup')
def read(name):
 try:return (root/name).read_text().strip()
 except OSError:return None
print(json.dumps({'cpu_cores':os.cpu_count(),'cpu_stat':read('cpu.stat'),'cpu_quota':read('cpu.max'),'host_cpu_stat':Path('/proc/stat').read_text().splitlines()[0],'memory_current_bytes':read('memory.current'),'memory_limit_bytes':read('memory.max'),'load_average':os.getloadavg()}))
"""
  async def stats():return await asyncio.to_thread(remote,stats_code,{})
  async def trial(label,rate,duration,concurrency,closed=False):
   before=await stats();latencies=[];statuses=[];ends=[];active=0;peak=0;dropped=0;scheduled=0;scheduler_lag=0.;abort=asyncio.Event();health_checks=[]
   connector=aiohttp.TCPConnector(limit=concurrency,limit_per_host=concurrency,ttl_dns_cache=300)
   timeout=aiohttp.ClientTimeout(total=15,sock_connect=8,sock_read=12)
   async with aiohttp.ClientSession(connector=connector,timeout=timeout,headers={'Authorization':'Bearer '+token}) as client:
    async with client.get(BASE+'/api/catalog?limit=30') as r:assert r.status==200;await r.read()
    began=time.perf_counter();deadline=began+duration
    async def hit():
     nonlocal active,peak
     start=time.perf_counter();active+=1;peak=max(peak,active)
     try:
      async with client.get(BASE+'/api/catalog?limit=30') as r:await r.read();statuses.append(str(r.status))
     except Exception as error:statuses.append(type(error).__name__)
     finally:latencies.append(time.perf_counter()-start);ends.append(time.perf_counter()-began);active-=1
     if len(statuses)>=50:
      if sum(v!='200' for v in statuses[-200:])/len(statuses[-200:])>.01:abort.set()
      if len(latencies)>=100 and sorted(latencies[-100:])[94]>3:abort.set()
    async def monitor():
     failures=0
     while time.perf_counter()<deadline and not abort.is_set():
      try:
       async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=4)) as probe:
        start=time.perf_counter()
        async with probe.get(BASE+'/api/health') as response:
         await response.read();ok=response.status==200;health_checks.append({'status':response.status,'seconds':round(time.perf_counter()-start,3)})
      except Exception:ok=False;health_checks.append({'status':'timeout'})
      failures=0 if ok else failures+1
      if failures>=2:abort.set();return
      await asyncio.sleep(2)
    watcher=asyncio.create_task(monitor())
    if closed:
     async def worker():
      while time.perf_counter()<deadline and not abort.is_set():await hit()
     await asyncio.gather(*(worker() for _ in range(concurrency)))
     scheduled=len(statuses)
    else:
     tasks=set();target=round(rate*duration);batch=max(1,round(rate/100))
     for first in range(0,target,batch):
      if abort.is_set():break
      due=began+first/rate;await asyncio.sleep(max(0,due-time.perf_counter()));scheduler_lag=max(scheduler_lag,time.perf_counter()-due)
      for i in range(first,min(first+batch,target)):
       scheduled+=1
       if len(tasks)>=concurrency:dropped+=1;continue
       task=asyncio.create_task(hit());tasks.add(task);task.add_done_callback(tasks.discard)
     await asyncio.gather(*tasks)
    watcher.cancel()
    try:await watcher
    except asyncio.CancelledError:pass
    elapsed=time.perf_counter()-began
   ordered=sorted(latencies);n=len(statuses);errors=sum(v!='200' for v in statuses)
   result={'label':label,'model':'closed-loop' if closed else 'open-loop with explicit in-flight cap and recorded drops','offered_rps':rate if not closed else None,'planned_duration_seconds':duration,'duration_including_drain_seconds':round(elapsed,3),'concurrency_limit':concurrency,'peak_client_inflight':peak,'scheduled':scheduled,'client_dropped':dropped,'unoffered_due_to_abort':0 if closed else max(0,round(rate*duration)-scheduled),'requests_completed':n,'statuses':dict(collections.Counter(statuses)),'successful_rps_including_drain':round(statuses.count('200')/elapsed,2),'successful_rps_within_planned_window':round(sum(status=='200' and end<=duration for status,end in zip(statuses,ends))/duration,2),'error_percent':round(100*errors/max(n,1),3),'p50_ms':round(ordered[n//2]*1000,2) if n else None,'p95_ms':round(ordered[max(0,int(n*.95)-1)]*1000,2) if n else None,'max_ms':round(max(ordered)*1000,2) if n else None,'scheduler_max_lag_ms':round(scheduler_lag*1000,2),'safety_stop':abort.is_set(),'health_checks':health_checks,'api_container_before':before,'api_container_after':await stats()}
   print(json.dumps(result),flush=True);return result
  async def native_trial(concurrency,duration=20):
   before=await stats()
   lua='wrk.headers["Authorization"] = "Bearer " .. os.getenv("QM_LOAD_TOKEN")\nlocal threads = {}\nstatuses = {}\nfunction setup(thread) table.insert(threads,thread) end\nfunction response(status, headers, body)\n local k=tostring(status);statuses[k]=(statuses[k] or 0)+1\nend\nfunction done(summary,latency,requests)\n local total={}\n for _,thread in ipairs(threads) do\n  local counts=thread:get("statuses")\n  for k,v in pairs(counts) do total[k]=(total[k] or 0)+v end\n end\n for k,v in pairs(total) do print("QM_STATUS "..k.." "..v) end\n print("QM_SUMMARY "..summary.requests.." "..summary.duration)\n print("QM_P95_US "..latency:percentile(95))\nend\n'
   env=dict(os.environ);env['QM_LOAD_TOKEN']=token
   async def host_stats():
    def collect():
     channel=ssh.open_session();channel.exec_command("docker stats --no-stream --format '{{json .}}'");channel.shutdown_write()
     data=channel.makefile('r').read();channel.makefile_stderr('r').read()
     if channel.recv_exit_status():return []
     return [{k:row.get(k) for k in ['Name','CPUPerc','MemUsage','MemPerc','PIDs']} for row in (json.loads(line) for line in data.splitlines() if line)]
    return await asyncio.to_thread(collect)
   samples=[];done=False
   async def sample():
    while not done:
     samples.append(await host_stats());await asyncio.sleep(4)
   sampling=asyncio.create_task(sample())
   try:
    with tempfile.NamedTemporaryFile(mode='w',suffix='.lua',delete=True) as script:
     script.write(lua);script.flush()
     process=await asyncio.to_thread(subprocess.run,['wrk','-t2','-c'+str(concurrency),'-d'+str(duration)+'s','--latency','-s',script.name,BASE+'/api/catalog?limit=30'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=duration+30)
    output=process.stdout
    counts=dict((status,int(count)) for status,count in re.findall(r'QM_STATUS (\d+) (\d+)',output))
    summary=re.search(r'QM_SUMMARY (\d+) (\d+)',output);p95=re.search(r'QM_P95_US ([\d.]+)',output)
    socket_errors=re.search(r'Socket errors: connect (\d+), read (\d+), write (\d+), timeout (\d+)',output)
    errors=sum(map(int,socket_errors.groups())) if socket_errors else 0
    assert process.returncode==0 and summary and p95,'Native generator failed; no capacity claim'
    count=int(summary[1]);elapsed=int(summary[2])/1e6
    result={'label':'native-wrk-'+str(concurrency),'model':'native multithreaded closed-loop HTTPS generator; not a paced RPS guarantee','concurrency_limit':concurrency,'duration_seconds':round(elapsed,3),'requests_completed':count,'statuses':counts,'socket_errors':errors,'successful_rps':round(counts.get('200',0)/elapsed,2),'p95_ms':round(float(p95[1])/1000,2),'generator_threads':2,'api_container_before':before,'api_container_after':await stats(),'container_samples':samples,'raw_generator_output':output}
    print(json.dumps(result),flush=True);return result
   finally:
    done=True;sampling.cancel()
    try:await sampling
    except asyncio.CancelledError:pass
    env.pop('QM_LOAD_TOKEN',None)
  if os.getenv('QM_LOAD_MODE') == 'stability':
   rate=int(os.getenv('QM_STABILITY_RATE','200'));duration=int(os.getenv('QM_STABILITY_SECONDS','300'))
   assert 1<=rate<=500 and 60<=duration<=300,'Bounded stability configuration required'
   stage=await trial('stability-'+str(rate)+'-rps',rate,duration,1000)
   passed=(not stage['safety_stop'] and stage['client_dropped']==0 and stage['unoffered_due_to_abort']==0 and stage['statuses'].get('200')==rate*duration and stage['requests_completed']==rate*duration)
   return {'target_requested_rps':10000,'target_verified':False,'mode':'stability','stability_passed':passed,'read_only':True,'version_under_test':'asynchronous catalog with live DB authorization','endpoint':'GET /api/catalog?limit=30','cpu_cores':info['cpu_cores'],'stages':[stage]}
  native=[]
  for concurrency in [100,250,500,1000]:
   result=await native_trial(concurrency);native.append(result)
   Path('load-verification').mkdir(exist_ok=True);Path('load-verification/native-progress.json').write_text(json.dumps(native,indent=2))
   if result['p95_ms']>3000 or result['socket_errors'] or sum(v for k,v in result['statuses'].items() if k!='200'):break
   await asyncio.sleep(5)
  stages=[]
  for concurrency in [100,250,500,1000]:
   result=await trial('post-optimization-'+str(concurrency),0,15,concurrency,True);stages.append(result)
   Path('load-verification').mkdir(exist_ok=True);Path('load-verification/progress.json').write_text(json.dumps(stages,indent=2))
   if result['safety_stop'] or result['error_percent']>1 or (result['p95_ms'] or 0)>3000:break
   await asyncio.sleep(5)
  # An explicit bounded attempt at the requested rate, without unbounded queues.
  await asyncio.sleep(10)
  stages.append(await trial('target-10000-rps',10000,5,2000))
  await asyncio.sleep(15)
  healthy=[r['successful_rps_including_drain'] for r in stages if r['label'].startswith('post-optimization') and not r['safety_stop'] and r['error_percent']==0 and (r['p95_ms'] or 99999)<1000]
  sustainable_rate=max(10,int(max(healthy,default=100)*.6))
  stages.append(await trial('sustained-with-headroom',sustainable_rate,120,500))
  target=next(r for r in stages if r['label']=='target-10000-rps')
  verified=(target['scheduled']==50000 and target['client_dropped']==0 and target['requests_completed']==50000 and target['statuses'].get('200')==50000 and not target['safety_stop'] and target['successful_rps_within_planned_window']>=9900)
  return {'target_requested_rps':10000,'target_verified':verified,'version_under_test':'2.2.1+14 with catalog-cache server update','method':'external HTTPS authenticated catalog, one GitHub runner and one temporary member; closed-loop comparison, bounded open-loop target attempt, 120-second sustained test','endpoint':'GET /api/catalog?limit=30','read_only':True,'cpu_cores':info['cpu_cores'],'native_generator_stages':native,'stages':stages}
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
