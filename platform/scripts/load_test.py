"""Authorized, loopback-only HTTP load runner. Never targets public services.
Tokens/QR/passwords are read from a private fixture file and never written to results.
5000 outstanding requests, 5000 RPS, and response latency are reported separately.
"""
import argparse
import asyncio
import collections
import csv
import json
import ssl
import time
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from urllib.parse import urlsplit
import ipaddress

import aiohttp

@dataclass
class Result:
    index: int
    endpoint: str
    status: int = 0
    error: str = ''
    latency_ms: float = 0
    connect_ms: float = 0
    ttfb_ms: float = 0
    send_at: float = 0
    end_at: float = 0
    bytes_received: int = 0


def percentile(values, q):
    if not values:
        return None
    values=sorted(values);p=(len(values)-1)*q;i=int(p);fraction=p-i
    return round(values[i]*(1-fraction)+values[min(i+1,len(values)-1)]*fraction,3)


def make_request(index, fixture, workload):
    account=fixture['accounts'][index % len(fixture['accounts'])]
    venue=fixture['venues'][index % len(fixture['venues'])]
    kind=workload
    if workload=='mixed':
        slot=index%20;kind='catalog' if slot<8 else 'detail' if slot<12 else 'map' if slot<15 else 'history' if slot<18 else 'me'
    token=account['token'];method='GET';body=b''
    paths={'health':'/api/health','meta':'/api/meta','catalog':'/api/catalog?limit=30',
           'map':'/api/catalog?west=76.90&south=52.20&east=77.10&north=52.40&limit=100',
           'detail':'/api/catalog/'+venue['id'],'history':'/api/me/history?limit=20','me':'/api/auth/me',
           'stats':'/api/workspace/stats'}
    if kind=='scan':
        method='POST';path='/api/scan';body=json.dumps({'code':venue['code'],'request_id':str(uuid.uuid4())}).encode()
    elif kind=='login':
        method='POST';path='/api/auth/login';token='';body=json.dumps({'identifier':account['identifier'],'password':fixture['password']}).encode()
    else:path=paths[kind]
    if kind=='stats':token=fixture['managers']['admin']['token']
    return kind,method,path,token,body


async def read_response(reader):
    header=await reader.readuntil(b'\r\n\r\n');lines=header.decode('latin1').split('\r\n');status=int(lines[0].split()[1]);headers={}
    for line in lines[1:]:
        if ':' in line:
            key,value=line.split(':',1);headers[key.lower()]=value.strip()
    headers_at=time.perf_counter()
    received=0
    if 'content-length' in headers:
        size=int(headers['content-length'])
        while size:
            data=await reader.readexactly(min(size,65536));received+=len(data);size-=len(data)
    elif 'chunked' in headers.get('transfer-encoding',''):
        while True:
            n=int((await reader.readline()).split(b';')[0],16)
            if not n:
                while (await reader.readline()) not in (b'\r\n',b''):pass
                break
            await reader.readexactly(n+2);received+=n
    return status,received,headers_at


async def burst(args, fixture, ctx, url):
    barrier=asyncio.Event();ready=0;all_connected=asyncio.Event();connections=[None]*args.count;sem=asyncio.Semaphore(500)
    async def connect(i):
        nonlocal ready
        try:
            async with sem:
                start=time.perf_counter()
                connection=await asyncio.wait_for(asyncio.open_connection(url.hostname,url.port or (443 if ctx else 80),ssl=ctx,server_hostname=url.hostname if ctx else None,limit=65536),args.timeout)
                connections[i]=(connection,time.perf_counter()-start)
        except Exception as exc:connections[i]=exc
        finally:
            ready+=1
            if ready==args.count:all_connected.set()
    preparation_started=time.perf_counter()
    if args.preconnect:
        await asyncio.gather(*(connect(i) for i in range(args.count)))
    preparation_seconds=time.perf_counter()-preparation_started
    results=[];in_flight=0;peak=0;start=0
    async def one(i):
        nonlocal in_flight,peak
        kind,method,path,token,body=make_request(i,fixture,args.workload)
        await barrier.wait();t=time.perf_counter();in_flight+=1;peak=max(peak,in_flight);r=Result(i,kind);writer=None
        try:
            if args.preconnect:
                item=connections[i]
                if isinstance(item,Exception):raise item
                (reader,writer),conn=item;r.connect_ms=round(conn*1000,3)
            else:
                c=time.perf_counter();reader,writer=await asyncio.wait_for(asyncio.open_connection(url.hostname,url.port or (443 if ctx else 80),ssl=ctx,server_hostname=url.hostname if ctx else None,limit=65536),args.timeout);r.connect_ms=round((time.perf_counter()-c)*1000,3)
            request=(f'{method} {path} HTTP/1.1\r\nHost: {url.netloc}\r\nUser-Agent: QazaqMetal-Local-LoadTest/1.0\r\nConnection: keep-alive\r\nAccept-Encoding: identity\r\n'+(f'Authorization: Bearer {token}\r\n' if token else '')+(f'Content-Type: application/json\r\nContent-Length: {len(body)}\r\n' if body else '')+'\r\n').encode()+body
            r.send_at=time.perf_counter()-start;writer.write(request);await writer.drain()
            r.status,r.bytes_received,headers_at=await asyncio.wait_for(read_response(reader),args.timeout);r.ttfb_ms=round((headers_at-t)*1000,3)
        except Exception as exc:r.error=type(exc).__name__
        finally:
            r.end_at=time.perf_counter()-start;r.latency_ms=round((time.perf_counter()-t)*1000,3);in_flight-=1
            if writer:writer.close()
            results.append(r)
    tasks=[asyncio.create_task(one(i)) for i in range(args.count)];await asyncio.sleep(0);start=time.perf_counter();barrier.set()
    while not all(t.done() for t in tasks):
        await asyncio.sleep(1)
        if int(time.perf_counter()-start)%5==0:print('progress',len(results),'/',args.count,flush=True)
    await asyncio.gather(*tasks)
    return results,{'preconnect_seconds':round(preparation_seconds,3),'peak_outstanding':peak,'wall_seconds':round(max((r.end_at for r in results),default=0),6),'requested':args.count,'not_dispatched':0}


async def steady(args, fixture, ctx, url):
    connector=aiohttp.TCPConnector(limit=args.concurrency,limit_per_host=args.concurrency,ssl=ctx or True)
    timeout=aiohttp.ClientTimeout(total=args.timeout);results=[];tasks=set();peak=0;dropped=0;lag=0;start=time.perf_counter();target=round(args.rate*args.duration)
    async with aiohttp.ClientSession(connector=connector,timeout=timeout,trust_env=False) as client:
        async def one(i):
            kind,method,path,token,body=make_request(i,fixture,args.workload);t=time.perf_counter();r=Result(i,kind,send_at=t-start)
            try:
                async with client.request(method,args.url.rstrip('/')+path,headers={**({'Authorization':'Bearer '+token} if token else {}),**({'Content-Type':'application/json'} if body else {})},data=body if body else None) as response:
                    r.ttfb_ms=round((time.perf_counter()-t)*1000,3);r.status=response.status
                    async for data in response.content.iter_chunked(65536):r.bytes_received+=len(data)
            except Exception as exc:r.error=type(exc).__name__
            finally:r.latency_ms=round((time.perf_counter()-t)*1000,3);r.end_at=time.perf_counter()-start;results.append(r)
        batch=max(1,round(args.rate/100))
        for first in range(0,target,batch):
            scheduled=start+first/args.rate;await asyncio.sleep(max(0,scheduled-time.perf_counter()));lag=max(lag,time.perf_counter()-scheduled)
            for i in range(first,min(first+batch,target)):
                if len(tasks)>=args.concurrency:dropped+=1;continue
                task=asyncio.create_task(one(i));tasks.add(task);task.add_done_callback(tasks.discard);peak=max(peak,len(tasks))
        await asyncio.gather(*tasks)
    return results,{'requested':target,'not_dispatched':dropped,'peak_outstanding':peak,'offered_rps':args.rate,'offering_seconds':args.duration,'scheduler_max_lag_ms':round(lag*1000,3),'wall_seconds':round(time.perf_counter()-start,3),'success_rps_within_offering_window':round(sum(r.status==200 and not r.error and r.end_at<=args.duration for r in results)/args.duration,3)}


async def main(args):
    url=urlsplit(args.url)
    assert url.scheme in ('http','https') and url.hostname and (url.hostname=='localhost' or ipaddress.ip_address(url.hostname).is_loopback),'Only own loopback test systems are allowed'
    fixture=json.loads(args.fixture.read_text());ctx=ssl.create_default_context(cafile=str(args.ca)) if url.scheme=='https' else None
    function=steady if args.mode=='steady' else burst;results,extra=await function(args,fixture,ctx,url)
    latencies=[r.latency_ms for r in results];ok=[r for r in results if r.status==200 and not r.error];sends=[r.send_at for r in results if r.send_at>0]
    summary={'label':args.label,'mode':args.mode,'workload':args.workload,'transport':url.scheme,'timeout_seconds':args.timeout,'preconnected':args.preconnect,'completed':len(results),'success':len(ok),'http_statuses':dict(collections.Counter(r.status for r in results)),'transport_errors':dict(collections.Counter(r.error for r in results if r.error)),**extra,'p50_ms':percentile(latencies,.5),'p95_ms':percentile(latencies,.95),'p99_ms':percentile(latencies,.99),'max_ms':round(max(latencies,default=0),3),'batch_completion_ms':round(max((r.end_at for r in results),default=0)*1000,3),'p95_ttfb_ms':percentile([r.ttfb_ms for r in ok],.95),'successful_p95_ms':percentile([r.latency_ms for r in ok],.95),'headers_dispatch_span_ms':round((max(sends)-min(sends))*1000,3) if sends else None,'success_under_200ms':sum(r.latency_ms<=200 for r in ok),'success_under_1s':sum(r.latency_ms<=1000 for r in ok),'successful_rps_including_drain':round(len(ok)/extra['wall_seconds'],3),'response_bytes':sum(r.bytes_received for r in results),'slo_5000_requests_under_1s_passed':args.count==5000 and len(ok)==5000 and max((r.end_at for r in results),default=0)<=1}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.with_suffix('.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    with args.output.with_suffix('.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=list(asdict(results[0])) if results else ['index']);writer.writeheader();writer.writerows(asdict(r) for r in sorted(results,key=lambda r:r.index))
    print(json.dumps(summary,ensure_ascii=False,indent=2),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--url',default='http://127.0.0.1:8090');parser.add_argument('--fixture',type=Path,required=True);parser.add_argument('--ca',type=Path);parser.add_argument('--mode',choices=['burst','steady'],default='burst');parser.add_argument('--workload',choices=['health','meta','me','catalog','detail','map','history','stats','scan','login','mixed'],default='mixed');parser.add_argument('--count',type=int,default=5000);parser.add_argument('--preconnect',action='store_true');parser.add_argument('--rate',type=int,default=5000);parser.add_argument('--duration',type=float,default=10);parser.add_argument('--concurrency',type=int,default=5000);parser.add_argument('--timeout',type=float,default=30);parser.add_argument('--label',required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    try:
        import uvloop
        uvloop.run(main(args))
    except ImportError:asyncio.run(main(args))
