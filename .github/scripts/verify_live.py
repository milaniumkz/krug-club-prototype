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
qa='qa-live-'+uuid.uuid4().hex[:12];member_identifier=qa+'-member';admin_password=secrets.token_urlsafe(24);memberid=None;adminid=None;staffid=None;importedid=None
bootstrap='''import json,sys
from sqlalchemy import select
from app.db import SessionLocal,User,Partner
from app.security import hash_password
p=json.load(sys.stdin)
with SessionLocal() as db:
 assert not db.scalar(select(User).where(User.username==p['name']))
 u=User(username=p['name'],name='QA · проверка запуска',role='admin',must_change_password=False,password_hash=hash_password(p['password']))
 db.add(u);db.flush()
 partner=db.scalar(select(Partner).where(Partner.active.is_(True)).limit(1))
 staff=User(username=p['name']+'-partner',name='QA · партнёр',role='partner',partner_id=partner.id,must_change_password=False,password_hash=hash_password(p['password']))
 db.add(staff);db.commit();print(json.dumps({'id':u.id,'staff_id':staff.id}))
'''
client=httpx.Client(base_url=BASE,timeout=30,follow_redirects=True,headers={'X-QM-Client':'web'})
def call(method,path,body=None,token=None,status=200):
 headers={'Authorization':'Bearer '+token} if token else {}
 role=token_roles.get(token,'member')
 if path=='/api/auth/login' and body:
  identifier=body['identifier'];role='admin' if identifier==qa else 'partner' if (identifier.startswith('partner') or identifier==qa+'-partner') else 'member'
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
 created_staff=remote(bootstrap,{'name':qa,'password':admin_password});adminid=created_staff['id'];staffid=created_staff['staff_id']
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
 template=call('GET','/api/admin/accounts/import-template',token=admin);assert template[:2]==b'PK'
 call('GET','/api/admin/accounts/import-template',token=call('POST','/api/auth/login',{'identifier':qa+'-partner','password':admin_password})['token'],status=403)
 import_number=qa+'-import'
 csv=('№;Фамилия;Имя;Отчество;Табельный номер\n1;Тестовый;Импорт;Сотрудника;'+import_number+'\n').encode('utf-8-sig')
 imported=client.post(ADMIN+'/api/admin/accounts/import',params={'organization_id':org['id']},files={'file':('employees.csv',csv)},headers={'Authorization':'Bearer '+admin})
 assert imported.status_code==200 and imported.json()['count']==1
 imported_user=call('GET','/api/admin/accounts?q='+import_number,token=admin)['items'][0];importedid=imported_user['id']
 assert imported_user['organization_id']==org['id'] and imported_user['name']=='Тестовый Импорт Сотрудника'
 checks.append({'case':'Minimal Russian employee spreadsheet imports into selected organization','result':'PASS'})
 created=call('POST','/api/admin/accounts',{'name':'QA · участник приёмки','organization_id':org['id'],'employee_number':member_identifier,'role':'member'},admin,201);memberid=created['user']['id'];temp=created['temporary_password']
 login=call('POST','/api/auth/login',{'identifier':member_identifier,'password':temp,'organization_code':'DEMO'});token=login['token'];assert login['user']['must_change_password']
 call('GET','/api/catalog',token=token,status=428)
 personal='qa'+secrets.token_hex(2);changed=call('POST','/api/auth/password',{'old_password':temp,'new_password':personal},token);token=changed['token'];assert not changed['user']['must_change_password']
 call('GET','/api/auth/me',token=token);call('GET','/api/auth/sessions',token=token)
 avatar=client.post(BASE+'/api/me/avatar',headers={'Authorization':'Bearer '+token},files={'file':('qa-photo.png',Path('.github/demo-assets/restaurant-photo.png').read_bytes())})
 assert avatar.status_code==201 and avatar.json()['id']==memberid
 profile=call('GET','/api/auth/me',token=token);assert profile['avatar_path']==avatar.json()['avatar_path'] and profile['organization_name']==org['name']
 assert len(call('GET',profile['avatar_path'],token=token))>100
 assert call('DELETE','/api/me/avatar',token=token)['avatar_path'] is None
 checks.append({'case':'Own profile photo upload, persistence and removal without losing organization/session','result':'PASS'})
 assert call('GET','/api/meta')['brand']=='QMET+'
 config=call('GET','/api/app-config');assert config['schema_version']==1 and config['settings']['brand_name']=='QMET+'
 cached=client.get(BASE+'/api/app-config',headers={'If-None-Match':config['etag']});assert cached.status_code==304
 checks.append({'case':'Remote configuration conditional cache','http_status':304,'result':'PASS'})
 admin_config=call('GET','/api/admin/app-config',token=admin);assert admin_config['revision']==config['revision']
 call('GET','/api/admin/app-config',token=token,status=403)
 assert 'QMET+' in call('GET','/privacy').decode()
 assert len(call('GET','/terms?lang=kk'))>100
 catalog=call('GET','/api/catalog',token=token);assert catalog['total']>=2
 codes=json.loads(Path('.github/demo-assets/qr-codes.json').read_text())['partners']
 # Owners can rotate their QR codes. Old printed fixtures must not reset production QR hashes.
 qr_current=remote("from app.db import SessionLocal,Resource; from app.security import digest; import sys,json,secrets; p=json.load(sys.stdin); db=SessionLocal(); print(json.dumps({x['venue_id']:bool((v:=db.get(Resource,x['venue_id'])) and v.qr_hash and secrets.compare_digest(v.qr_hash,digest(x['code'].rsplit(':',1)[1]))) for x in p})); db.close()",codes)
 scanned=0
 for p in codes:
  v=call('GET','/api/catalog/'+p['venue_id'],token=token);assert len(v['data']['description'])>100 and v['offers']
  assert len(call('GET',v['data']['image'],token=token))>1000
  request={'code':p['code'],'request_id':str(uuid.uuid4())}
  if not qr_current[p['venue_id']]:
   call('POST','/api/scan',request,token,status=404)
   checks.append({'case':'Previously issued demo QR was replaced by its owner; current QR preserved','result':'INFO','venue':p['venue_id']})
   continue
  visit=call('POST','/api/scan',request,token);assert visit['percent']==max(o['data']['percent'] for o in v['offers']);scanned+=1
  assert call('POST','/api/scan',request,token)['replay']
 banners=call('GET','/api/banners',token=token);assert len(banners)>=2
 for b in banners:assert len(call('GET',b['data']['image'],token=token))>1000
 assert call('GET','/api/catalog?west=76.9&east=77.1&south=52.2&north=52.4',token=token)['total']>=2
 venue=codes[0]['venue_id'];call('PUT','/api/me/favorites/'+venue,{},token);call('PUT','/api/me/favorites/'+venue,{},token);assert call('GET','/api/catalog?favorites_only=true',token=token)['total']==1;call('DELETE','/api/me/favorites/'+venue,token=token)
 assert len(call('GET','/api/me/history',token=token))==scanned
 assert 'Еда и напитки' in call('GET','/api/categories',token=token)
 assert 'name:ru' in json.dumps(call('GET','/api/map-style?lang=ru'))
 assert 'name:kk' in json.dumps(call('GET','/api/map-style?lang=kk'))
 call('POST','/api/scan',{'code':'https://example.com','request_id':str(uuid.uuid4())},token,400)
 call('POST','/api/scan',{'code':'QAZAQMETAL:1:'+str(uuid.uuid4())+':'+secrets.token_urlsafe(24),'request_id':str(uuid.uuid4())},token,404)
 call('GET','/api/admin/accounts',token=token,status=403)
 ticket=call('POST','/api/tickets',{'subject':'QA · проверка поддержки','message':'Автоматическая тестовая заявка при запуске.'},token,201)
 call('POST','/api/admin/tickets/'+ticket['id'],{'status':'closed','reply':'QA · проверка ответа'},admin)
 assert any(t['id']==ticket['id'] and t['status']=='closed' for t in call('GET','/api/tickets',token=token))
 assert call('GET','/api/workspace/stats',token=admin)['total_uses']>=scanned
 # Real first-password/PIN flow and idle session revocation in the deployed browser app.
 browser_temporary=call('POST','/api/admin/accounts/'+memberid+'/reset-password',{},admin)['temporary_password']
 from playwright.sync_api import sync_playwright
 with sync_playwright() as pw:
  executable=shutil.which('google-chrome') or shutil.which('chromium')
  browser=pw.chromium.launch(executable_path=executable,args=['--no-sandbox','--disable-dev-shm-usage'],ignore_default_args=['--disable-background-networking'])
  ctx=browser.new_context(viewport={'width':390,'height':844},permissions=['geolocation','notifications'],geolocation={'latitude':52.287,'longitude':76.967})
  page=ctx.new_page();page.set_default_timeout(15000)
  push_http=[]; push_csp=[]; push_failures=[]
  from urllib.parse import urlsplit
  def push_response(response):
   host=urlsplit(response.url).hostname or ''
   if host.endswith(('googleapis.com','gstatic.com')):push_http.append({'host':host,'status':response.status})
  page.on('response',push_response)
  page.on('console',lambda message:push_csp.append(True) if 'Content Security Policy' in message.text and ('firebase' in message.text or 'gstatic' in message.text or 'googleapis' in message.text) else None)
  page.on('requestfailed',lambda request:push_failures.append({'host':urlsplit(request.url).hostname,'error':request.failure}) if (urlsplit(request.url).hostname or '').endswith(('googleapis.com','gstatic.com')) else None)

  def enable():
   page.locator('flt-semantics-placeholder, flt-semantics').first.wait_for(state='attached',timeout=30000)
   if page.locator('flt-semantics-placeholder').count():page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
   page.wait_for_timeout(300)
  def fill(label,value,prefix=False):
   field=page.get_by_role('textbox',name=re.compile('^'+re.escape(label)) if prefix else label,exact=not prefix)
   field.click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value)
  member_page=page
  staff_token=call('POST','/api/auth/login',{'identifier':qa+'-partner','password':admin_password})['token']
  for origin,session_token,role in [(ADMIN,admin,'admin'),(PARTNER,staff_token,'partner')]:
   staff_context=browser.new_context(viewport={'width':1200,'height':900},permissions=['notifications'])
   staff_context.add_cookies([{'name':'qm_session','value':session_token,'url':origin,'httpOnly':True,'secure':True,'sameSite':'Strict'}])
   page=staff_context.new_page();page.set_default_timeout(15000);page.goto(origin);enable();assert page.title()=='QMET+'
   for reload in range(2):
    page.get_by_text('Обзор',exact=True).first.wait_for()
    assert page.get_by_text('Создайте PIN-код',exact=True).count()==0
    assert page.get_by_text('Введите PIN-код',exact=True).count()==0
    page.reload();enable()
   page.get_by_text('Обзор',exact=True).first.wait_for()
   checks.append({'case':role+' portal opens after browser reload without PIN','result':'PASS'})
   page.screenshot(path=str(out/('staff-'+role+'.png')))
   if role=='admin':
    page.get_by_text('Настройки приложения',exact=True).first.click();page.wait_for_timeout(700)
    page.get_by_role('button',name='Сохранить настройки',exact=True).first.wait_for()
    for settings_width in (390,320):
     page.set_viewport_size({'width':settings_width,'height':844});page.wait_for_timeout(500)
     assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
     page.screenshot(path=str(out/('app-settings-'+str(settings_width)+'.png')))
     checks.append({'case':'Remote settings editor '+str(settings_width)+'px','result':'PASS'})
    page.goto(origin);enable();page.get_by_text('Обзор',exact=True).first.wait_for()
   for width in (390,320):
    page.set_viewport_size({'width':width,'height':844});page.wait_for_timeout(700)
    page.get_by_text('Обзор',exact=True).first.wait_for()
    assert page.get_by_text('Введите PIN-код',exact=True).count()==0
    page.screenshot(path=str(out/('staff-'+role+'-'+str(width)+'.png')))
    checks.append({'case':role+' mobile layout '+str(width)+'px','result':'PASS'})
   staff_context.close()
  page=member_page
  page.goto(BASE);enable();page.get_by_text('QMET+',exact=True).first.wait_for();assert page.title()=='QMET+'
  fill('Табельный номер',member_identifier);fill('Пароль',browser_temporary)
  page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1300)
  fill('Временный пароль',browser_temporary);fill('Новый пароль',personal);fill('Повторите новый пароль',personal)
  page.get_by_role('button',name='Сохранить пароль',exact=True).click();page.wait_for_timeout(1800)
  def enter_pin(value):
   for digit in value:
    page.get_by_role('button',name=digit,exact=True).click();page.wait_for_timeout(100)
   page.wait_for_timeout(400)
  enter_pin('472918');page.screenshot(path=str(out/'pin-confirmation.png'));enter_pin('472918');page.wait_for_timeout(2000)
  assert ctx.request.get(BASE+'/api/auth/me').status==200
  page.get_by_role('tab',name='Главная',exact=True).wait_for()
  page.screenshot(path=str(out/'home.png'))
  page.reload();enable();page.get_by_role('tab',name='Главная',exact=True).wait_for()
  assert page.get_by_text('Введите PIN-код',exact=True).count()==0
  page.wait_for_timeout(1200)
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
  # A real Chrome subscription is optional in hosted/headless environments;
  # never substitute a mock token for confirmed FCM registration/delivery.
  page.get_by_role('tab',name='Главная',exact=True).click();page.wait_for_timeout(1200)
  public=call('GET','/api/push-config?platform=web')
  assert public['enabled'] and public['options']['projectId']=='qazaqmetal-8a77b' and len(public['vapidKey'])==87
  assert 'private_key' not in json.dumps(public)
  worker=ctx.request.get(BASE+'/firebase-messaging-sw.js');assert worker.status==200 and 'firebase-messaging-compat.js' in worker.text()
  config_script=ctx.request.get(BASE+'/api/push-config.js');assert config_script.status==200 and 'MUST_NOT_LEAK' not in config_script.text()
  checks.append({'case':'Firebase web configuration and same-origin messaging worker','result':'PASS'})
  push_devices=remote("from app.db import SessionLocal,PushDevice; from sqlalchemy import select,func; import sys,json; p=json.load(sys.stdin); db=SessionLocal(); print(json.dumps(db.scalar(select(func.count()).select_from(PushDevice).where(PushDevice.user_id==p['id'],PushDevice.platform=='web',PushDevice.active.is_(True))))); db.close()",{'id':memberid})
  if push_devices:
   notice_id=remote("from app.db import SessionLocal,Notification,PushDevice,PushDelivery; from sqlalchemy import select; import sys,json; p=json.load(sys.stdin); db=SessionLocal(); n=Notification(user_id=p['id'],venue_id=p['venue'],event_key=p['key'],kind='new_venue',title='QA · проверка push',title_kk='QA · push тексеру',body='Тестовое уведомление только для временной учётной записи.',body_kk='Тек уақытша аккаунтқа арналған сынақ хабарландыруы.'); db.add(n); db.flush(); [db.add(PushDelivery(notification_id=n.id,device_id=d.id)) for d in db.scalars(select(PushDevice).where(PushDevice.user_id==p['id'],PushDevice.active.is_(True)))]; db.commit(); print(json.dumps(n.id)); db.close()",{'id':memberid,'venue':venue,'key':qa+'-push'})
   delivery_states=[]
   for attempt in range(20):
    page.wait_for_timeout(1500)
    delivery_states=remote("from app.db import SessionLocal,PushDelivery; from sqlalchemy import select; import sys,json; p=json.load(sys.stdin); db=SessionLocal(); print(json.dumps(list(db.scalars(select(PushDelivery.status).where(PushDelivery.notification_id==p['id']))))); db.close()",{'id':notice_id})
    if delivery_states and all(status=='sent' for status in delivery_states):break
   assert delivery_states and all(status=='sent' for status in delivery_states), 'FCM did not accept QA browser delivery'
   page.get_by_text('QA · проверка push',exact=False).first.wait_for(timeout=15000)
   checks.append({'case':'Real Chrome FCM registration, worker delivery and foreground reception','result':'PASS'})
   page.screenshot(path=str(out/'real-web-push.png'))
  else:
   worker_states=page.evaluate("async()=> (await navigator.serviceWorker.getRegistrations()).filter(r=>r.scope.includes('firebase-cloud-messaging-push-scope')).map(r=>r.active?.state || r.installing?.state || 'inactive')")
   assert 'activated' in worker_states, 'Firebase service worker was not activated'
   assert not push_csp, 'Firebase SDK blocked by CSP'
   assert not any(x['status']>=400 and x['host'] in ('firebaseinstallations.googleapis.com','fcmregistrations.googleapis.com','fcm.googleapis.com') for x in push_http), 'Firebase browser registration returned an HTTP error'
   checks.append({'case':'Headless Chrome did not provide an FCM token; real-device delivery still requires physical test','result':'INFO','firebase_http':push_http,'firebase_network_failures':push_failures,'worker_states':worker_states})
  page.get_by_role('button',name='Уведомления',exact=True).click();page.wait_for_timeout(700)
  connect=page.get_by_role('button',name=re.compile('^(Включить уведомления|Проверить подключение)$'))
  connect.wait_for()
  for width in (320,390):
   page.set_viewport_size({'width':width,'height':844});page.wait_for_timeout(400)
   assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
   page.screenshot(path=str(out/('notifications-'+str(width)+'.png')))
  if connect.is_enabled():connect.click();page.wait_for_timeout(1000)
  checks.append({'case':'Notification permission/retry button and inbox at 320/390px','result':'PASS'})
  page.get_by_role('tab',name='Профиль',exact=True).click();page.wait_for_timeout(500)
  # The real Logout UI must end the PIN lifecycle; credential login must create it again.
  for _ in range(8):
   if page.get_by_text('Выйти',exact=True).count():break
   page.mouse.move(200,500);page.mouse.wheel(0,450);page.wait_for_timeout(250)
  page.get_by_text('Выйти',exact=True).scroll_into_view_if_needed()
  page.get_by_text('Выйти',exact=True).click();page.wait_for_timeout(300)
  page.get_by_role('button',name='Продолжить',exact=True).click();page.wait_for_timeout(700)
  fill('Табельный номер',member_identifier);fill('Пароль',personal)
  page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1200)
  page.get_by_text('Создайте PIN-код',exact=True).wait_for()
  enter_pin('826419');enter_pin('826419')
  page.get_by_role('tab',name='Главная',exact=True).wait_for()
  checks.append({'case':'logout button clears PIN; credential re-login creates a different new PIN','result':'PASS'})

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
from app.db import SessionLocal,User,Audit,Session,Ticket,Favorite,Visit,Notification,PushDelivery,PushDevice
p=json.load(sys.stdin);ids=[x for x in p['ids'] if x]
with SessionLocal() as db:
 users=db.scalars(select(User).where(User.id.in_(ids))).all()
 assert all((u.username or u.employee_number or '').startswith(p['prefix']) for u in users)
 notices=select(Notification.id).where(Notification.user_id.in_(ids))
 db.execute(delete(PushDelivery).where(PushDelivery.notification_id.in_(notices)))
 devices=select(PushDevice.id).where(PushDevice.user_id.in_(ids))
 db.execute(delete(PushDelivery).where(PushDelivery.device_id.in_(devices)))
 db.execute(delete(Notification).where(Notification.user_id.in_(ids)))
 db.execute(delete(PushDevice).where(PushDevice.user_id.in_(ids)))
 for model,column in [(Audit,Audit.actor_id),(Session,Session.user_id),(Ticket,Ticket.user_id),(Favorite,Favorite.user_id),(Visit,Visit.user_id)]:db.execute(delete(model).where(column.in_(ids)))
 db.execute(delete(User).where(User.id.in_(ids)));db.commit()
print(json.dumps({'cleanup':'PASS'}))
'''
  remote(cleanup,{'ids':[adminid,memberid,staffid,importedid],'prefix':qa})
 client.close();ssh.close();(out/'results.json').write_text(json.dumps({'url':BASE,'checks':checks,'physical_camera_tested':False,'test_accounts_removed':True},ensure_ascii=False,indent=2))
