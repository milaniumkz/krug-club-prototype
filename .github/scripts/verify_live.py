"""Acceptance tests on the deployed demo. Keep 01/02 passwords unchanged. Remove only unique QA accounts."""
import base64,hashlib,json,os,re,secrets,shlex,shutil,socket,time,uuid
from pathlib import Path
import httpx,paramiko
BASE='https://qazaqmetal.109.235.119.144.sslip.io';PARTNER='https://qazaqmetalpartners.109.235.119.144.sslip.io';ADMIN='https://qazaqmetaladmin.109.235.119.144.sslip.io';token_roles={};out=Path('live-verification');out.mkdir(exist_ok=True);checks=[]
password=os.environ.pop('DEPLOY_SSH_PASSWORD','');ssh=paramiko.Transport(socket.create_connection(('109.235.119.144',22),timeout=20));ssh.get_security_options().key_types=('ssh-ed25519',);ssh.start_client(timeout=20)
fp='SHA256:'+base64.b64encode(hashlib.sha256(ssh.get_remote_server_key().asbytes()).digest()).decode().rstrip('=')
if not secrets.compare_digest(fp,'SHA256:Bt3HkaktjLmWe4tB1pOK9b8gOnHuxp+tvp1hhEDtxp8'):raise SystemExit('SSH identity changed')
ssh.auth_password('root',password);password=None

def remote(code,payload):
 ch=ssh.open_session();ch.exec_command('cd /opt/qazaqmetal/current && docker compose exec -T api python -c '+shlex.quote(code));ch.sendall(json.dumps(payload).encode());ch.shutdown_write();data=ch.makefile('r').read();err=ch.makefile_stderr('r').read();status=ch.recv_exit_status()
 if status:raise RuntimeError('QA administrative operation failed; no credentials logged')
 return json.loads(data) if data.strip() else None
qa='qa-live-'+uuid.uuid4().hex[:12];member_identifier=qa+'-member';admin_password=secrets.token_urlsafe(24);memberid=None;adminid=None
bootstrap='''import json,sys
from sqlalchemy import select
from app.db import SessionLocal,User
from app.security import hash_password
p=json.load(sys.stdin)
with SessionLocal() as db:
 assert not db.scalar(select(User).where(User.username==p['name']))
 u=User(username=p['name'],name='QA · проверка запуска',role='admin',must_change_password=False,password_hash=hash_password(p['password']))
 db.add(u);db.commit();print(json.dumps({'id':u.id}))
'''
client=httpx.Client(base_url=BASE,timeout=30,follow_redirects=True,headers={'X-QM-Client':'web'})
def call(method,path,body=None,token=None,status=200):
 headers={'Authorization':'Bearer '+token} if token else {}
 role=token_roles.get(token,'member')
 if path=='/api/auth/login' and body:
  identifier=body['identifier'];role='admin' if identifier==qa else 'partner' if identifier.startswith('partner') else 'member'
 origin={'member':BASE,'partner':PARTNER,'admin':ADMIN}[role]
 r=client.request(method,origin+path,json=body,headers=headers)
 assert r.status_code==status,(method,path,r.status_code,status)
 checks.append({'method':method,'path':path,'http_status':r.status_code,'result':'PASS'})
 if 'application/json' in r.headers.get('content-type',''):
  data=r.json()
  if isinstance(data,dict) and 'token' in data:token_roles[data['token']]=data['user']['role']
  return data
 return r.content
try:
 adminid=remote(bootstrap,{'name':qa,'password':admin_password})['id']
 assert call('GET','/api/health')=={'status':'ok'}
 assert b'flutter' in call('GET','/').lower()
 assert len(call('GET','/main.dart.js'))>10000
 flags=remote("from app.db import SessionLocal,User; from sqlalchemy import select; import json; db=SessionLocal(); print(json.dumps({(u.employee_number if u.role=='member' else u.username):u.must_change_password for u in db.scalars(select(User).where(User.employee_number.in_(['01','02']) | User.username.in_(['partner01','partner02'])))})); db.close()",{})
 verification_sessions=[]
 for identifier in ('01','02','partner01','partner02'):
  if not flags[identifier]:
   checks.append({'account':identifier,'personal_password':'preserved'});continue
  r=call('POST','/api/auth/login',{'identifier':identifier,'password':'123456','organization_code':'DEMO' if identifier in ('01','02') else ''})
  assert r['user']['must_change_password']
  call('GET','/api/catalog' if identifier in ('01','02') else '/api/workspace/resources',token=r['token'],status=428)
  verification_sessions.append(hashlib.sha256(r['token'].encode()).hexdigest())
 if verification_sessions:
  remote("from app.db import SessionLocal,Session; from sqlalchemy import delete; import sys,json; db=SessionLocal(); db.execute(delete(Session).where(Session.id.in_(json.load(sys.stdin)))); db.commit(); db.close()",verification_sessions)
 admin=call('POST','/api/auth/login',{'identifier':qa,'password':admin_password})['token']
 org=next(o for o in call('GET','/api/admin/organizations',token=admin) if o['code']=='DEMO')
 created=call('POST','/api/admin/accounts',{'name':'QA · участник приёмки','organization_id':org['id'],'employee_number':member_identifier,'role':'member'},admin,201);memberid=created['user']['id'];temp=created['temporary_password']
 login=call('POST','/api/auth/login',{'identifier':member_identifier,'password':temp,'organization_code':'DEMO'});token=login['token'];assert login['user']['must_change_password']
 call('GET','/api/catalog',token=token,status=428)
 personal='qa'+secrets.token_hex(2);changed=call('POST','/api/auth/password',{'old_password':temp,'new_password':personal},token);token=changed['token'];assert not changed['user']['must_change_password']
 call('GET','/api/auth/me',token=token);call('GET','/api/auth/sessions',token=token)
 catalog=call('GET','/api/catalog',token=token);assert catalog['total']>=2
 codes=json.loads(Path('.github/demo-assets/qr-codes.json').read_text())['partners']
 for p in codes:
  v=call('GET','/api/catalog/'+p['venue_id'],token=token);assert len(v['data']['description'])>100 and v['offers']
  assert len(call('GET',v['data']['image'],token=token))>1000
  request={'code':p['code'],'request_id':str(uuid.uuid4())};visit=call('POST','/api/scan',request,token);assert visit['percent']==p['percent']
  assert call('POST','/api/scan',request,token)['replay']
 banners=call('GET','/api/banners',token=token);assert len(banners)>=2
 for b in banners:assert len(call('GET',b['data']['image'],token=token))>1000
 assert call('GET','/api/catalog?west=76.9&east=77.1&south=52.2&north=52.4',token=token)['total']>=2
 venue=codes[0]['venue_id'];call('PUT','/api/me/favorites/'+venue,{},token);call('PUT','/api/me/favorites/'+venue,{},token);assert call('GET','/api/catalog?favorites_only=true',token=token)['total']==1;call('DELETE','/api/me/favorites/'+venue,token=token)
 assert len(call('GET','/api/me/history',token=token))==2
 assert 'Еда и напитки' in call('GET','/api/categories',token=token)
 assert 'name:ru' in json.dumps(call('GET','/api/map-style?lang=ru'))
 assert 'name:kk' in json.dumps(call('GET','/api/map-style?lang=kk'))
 call('POST','/api/scan',{'code':'https://example.com','request_id':str(uuid.uuid4())},token,400)
 call('POST','/api/scan',{'code':'QAZAQMETAL:1:'+str(uuid.uuid4())+':'+secrets.token_urlsafe(24),'request_id':str(uuid.uuid4())},token,404)
 call('GET','/api/admin/accounts',token=token,status=403)
 ticket=call('POST','/api/tickets',{'subject':'QA · проверка поддержки','message':'Автоматическая тестовая заявка при запуске.'},token,201)
 call('POST','/api/admin/tickets/'+ticket['id'],{'status':'closed','reply':'QA · проверка ответа'},admin)
 assert any(t['id']==ticket['id'] and t['status']=='closed' for t in call('GET','/api/tickets',token=token))
 assert call('GET','/api/workspace/stats',token=admin)['total_uses']>=2
 # Real first-password/PIN flow and idle session revocation in the deployed browser app.
 browser_temporary=call('POST','/api/admin/accounts/'+memberid+'/reset-password',{},admin)['temporary_password']
 from playwright.sync_api import sync_playwright
 with sync_playwright() as pw:
  executable=shutil.which('google-chrome') or shutil.which('chromium')
  browser=pw.chromium.launch(executable_path=executable,args=['--no-sandbox','--disable-dev-shm-usage'])
  ctx=browser.new_context(viewport={'width':390,'height':844},permissions=['geolocation'],geolocation={'latitude':52.287,'longitude':76.967})
  page=ctx.new_page();page.set_default_timeout(15000)
  def enable():
   page.wait_for_timeout(2200)
   if page.locator('flt-semantics-placeholder').count():page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
   page.wait_for_timeout(300)
  def fill(label,value,prefix=False):
   field=page.get_by_role('textbox',name=re.compile('^'+re.escape(label)) if prefix else label,exact=not prefix)
   field.click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value)
  page.goto(BASE);enable()
  fill('Табельный номер',member_identifier);fill('Пароль',browser_temporary)
  page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1300)
  fill('Временный пароль',browser_temporary);fill('Новый пароль',personal);fill('Повторите новый пароль',personal)
  page.get_by_role('button',name='Сохранить пароль',exact=True).click();page.wait_for_timeout(1800)
  fill('PIN-код','472918',True);fill('Повторите PIN-код','472918',True)
  page.get_by_role('button',name='Сохранить PIN-код',exact=True).click();page.wait_for_timeout(2000)
  assert ctx.request.get(BASE+'/api/auth/me').status==200
  page.get_by_role('tab',name='Главная',exact=True).wait_for()
  page.screenshot(path=str(out/'home.png'))
  page.reload();enable();fill('PIN-код','472918',True)
  page.get_by_role('button',name='Открыть приложение',exact=True).click();page.wait_for_timeout(1200)
  checks.append({'case':'first password with six characters, PIN setup and saved-session PIN unlock','result':'PASS'})
  for tab in ['Партнёры','На карте','QR','Профиль','Главная']:
   page.get_by_role('tab',name=tab,exact=True).click();page.wait_for_timeout(1400)
   assert 'Exception caught' not in page.locator('body').inner_text()
   checks.append({'screen':tab,'result':'PASS'});page.screenshot(path=str(out/('screen-'+str(len(checks))+'.png')))
  page.get_by_role('tab',name='Профиль',exact=True).click();page.wait_for_timeout(800)
  page.get_by_role('button',name='ҚАЗ',exact=True).click();page.wait_for_timeout(700)
  page.get_by_role('tab',name='Басты бет',exact=True).wait_for();page.screenshot(path=str(out/'profile-kk.png'))
  page.get_by_role('button',name='РУС',exact=True).click();page.wait_for_timeout(600)
  checks.append({'case':'Russian/Kazakh profile switch and translated navigation','result':'PASS'})
  for width,height in [(320,640),(430,932),(768,1024)]:
   page.set_viewport_size({'width':width,'height':height});page.wait_for_timeout(500)
   assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth');checks.append({'viewport':[width,height],'result':'PASS'})
  began=time.monotonic()
  call('POST','/api/admin/accounts/'+memberid+'/status',{'status':'dismissed','reason':'QA · проверка немедленного завершения сессии'},admin)
  page.get_by_role('textbox',name='Табельный номер',exact=True).wait_for(state='visible',timeout=5000)
  assert page.get_by_role('tab',name='Главная',exact=True).count()==0
  checks.append({'case':'idle browser forced logout on dismissal','seconds':round(time.monotonic()-began,3),'result':'PASS'})
  page.screenshot(path=str(out/'revoked-session.png'));browser.close()
 call('POST','/api/admin/accounts/'+memberid+'/status',{'status':'active','reason':'QA · завершение проверки отзыва'},admin)
 token=call('POST','/api/auth/login',{'identifier':member_identifier,'password':personal})['token']
 call('POST','/api/auth/logout',{},token);call('GET','/api/auth/me',token=token,status=401)
 print('LIVE ACCEPTANCE PASS:',len(checks),'checks; requested demo passwords remain unchanged',flush=True)
finally:
 # Only unique accounts created by this run and their dependent test records are removed.
 if adminid:
  cleanup='''import json,sys
from sqlalchemy import delete,select
from app.db import SessionLocal,User,Audit,Session,Ticket,Favorite,Visit
p=json.load(sys.stdin);ids=[x for x in p['ids'] if x]
with SessionLocal() as db:
 users=db.scalars(select(User).where(User.id.in_(ids))).all()
 assert all((u.username or u.employee_number or '').startswith(p['prefix']) for u in users)
 for model,column in [(Audit,Audit.actor_id),(Session,Session.user_id),(Ticket,Ticket.user_id),(Favorite,Favorite.user_id),(Visit,Visit.user_id)]:db.execute(delete(model).where(column.in_(ids)))
 db.execute(delete(User).where(User.id.in_(ids)));db.commit()
print(json.dumps({'cleanup':'PASS'}))
'''
  remote(cleanup,{'ids':[adminid,memberid],'prefix':qa})
 client.close();ssh.close();(out/'results.json').write_text(json.dumps({'url':BASE,'checks':checks,'physical_camera_tested':False,'test_accounts_removed':True},ensure_ascii=False,indent=2))
