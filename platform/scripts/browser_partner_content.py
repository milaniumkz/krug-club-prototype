"""Partner editor/upload/QR export workflow against isolated QA, including the real browser PNG download."""
import argparse,json,re,shutil,tempfile,time
from pathlib import Path
from PIL import Image
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:8018');p.add_argument('--credentials',type=Path,required=True);p.add_argument('--private-dir',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('artifacts/partner-content'));a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);creds=json.loads(a.credentials.read_text());assert all(v['identifier'].lower().startswith('qa') for v in creds.values());a.private_dir.mkdir(parents=True,exist_ok=True);a.private_dir.chmod(0o700);results=[];suffix=str(int(time.time()));venue_name='QA — новое кафе '+suffix
def fixture(name,source,color):
 if source.is_file():return source
 file=a.private_dir/name
 Image.new('RGB',(640,400),color).save(file)
 return file


def record(name,fn):
 try:fn();results.append({'case':name,'status':'PASS'})
 except Exception as e:
  results.append({'case':name,'status':'FAIL','error_type':type(e).__name__})
  if 'op' in globals():(a.private_dir/'partner-failure.txt').write_text(op.locator('body').aria_snapshot())
  raise
 finally:
  (a.output/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print(results[-1],flush=True)
def seek(page,locator):
 for _ in range(12):
  if locator.count() and locator.first.is_visible():return locator.first
  page.mouse.wheel(0,350);page.wait_for_timeout(150)
 raise AssertionError('Control not reachable')
def fill(page,label,value):
 box=seek(page,page.get_by_role('textbox',name=label,exact=True));box.click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value);page.wait_for_timeout(200)
def menu(page,name):page.get_by_text(name,exact=True).first.click();page.wait_for_timeout(800)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path=shutil.which('chromium'),args=['--no-sandbox','--disable-dev-shm-usage'])
 def login(role):
  ctx=b.new_context(viewport={'width':1320,'height':1000});page=ctx.new_page();page.set_default_timeout(10000);page.goto(a.url);page.wait_for_timeout(2400)
  if page.locator('flt-semantics-placeholder').count():page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
  fill(page,'Табельный номер / телефон / логин',creds[role]['identifier']);fill(page,'Пароль',creds[role]['password']);page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1600);return ctx,page
 owner,op=login('partner');admin,ap=login('admin');member,mp=login('member');state={}
 def submit_venue():
  menu(op,'Заведения');op.get_by_role('button',name='Добавить',exact=True).click();op.wait_for_timeout(700)
  for label,value in [('Название',venue_name),('Описание','QA — подробное описание уютного кафе и условий посещения.'),('Категория','Кафе'),('Адрес','QA — тестовый адрес 18'),('Телефон заведения','+77000000000'),('Режим работы','10:00–22:00'),('Широта','52.286'),('Долгота','76.969')]:fill(op,label,value)
  with op.expect_file_chooser() as chooser:seek(op,op.get_by_role('button',name='Загрузить фотографию / баннер',exact=True)).click()
  photo=fixture('venue-qa.png',Path(__file__).resolve().parents[2]/'mobile/assets/restaurant-reference.png','#b79ad2')
  with op.expect_response(lambda r:r.request.method=='POST' and r.url.endswith('/api/media')) as pending:chooser.value.set_files(str(photo))
  assert pending.value.status==201
  op.wait_for_timeout(600);seek(op,op.get_by_role('button',name='Отправить на модерацию',exact=True)).click();op.wait_for_timeout(800)
  rows=owner.request.get(a.url+'/api/workspace/resources?kind=venue').json();v=next(v for v in rows if (v.get('revision') or {}).get('data',{}).get('name')==venue_name)
  assert v['revision']['status']=='pending' and v['revision']['data']['image'].startswith('/media/');state['venue']=v
  assert member.request.get(a.url+'/api/catalog',params={'q':venue_name}).json()['total']==0
 record('partner: fill all venue fields, upload photo and submit a hidden draft',submit_venue)
 def approve_venue():
  v=state['venue'];r=admin.request.post(a.url+'/api/admin/moderation/'+v['revision']['id'],data={'decision':'approve'},headers={'X-QM-Client':'web'});assert r.status==200
  assert member.request.get(a.url+'/api/catalog',params={'q':venue_name}).json()['total']==1
 record('API: venue becomes visible only after approval',approve_venue)
 def choose_venue():
  op.get_by_role('button',name=re.compile(r'^Заведение(?:\s|$)')).first.click();op.wait_for_timeout(350);op.get_by_role('menuitem',name=venue_name,exact=True).click();op.wait_for_timeout(350)
 def submit_offer():
  menu(op,'Скидки и акции');op.get_by_role('button',name='Добавить',exact=True).click();op.wait_for_timeout(800);choose_venue()
  fill(op,'Название','QA — скидка 18% '+suffix);fill(op,'Скидка, %','18');fill(op,'Условия и ограничения','QA — для членов профсоюза, без суммирования с другими акциями.')
  seek(op,op.get_by_role('button',name='Отправить на модерацию',exact=True)).click();op.wait_for_timeout(700)
  o=next(v for v in owner.request.get(a.url+'/api/workspace/resources?kind=offer').json() if v['venue_id']==state['venue']['id']);assert o['revision']['status']=='pending';state['offer']=o
 record('partner: choose a venue and submit a discount with conditions',submit_offer)
 def approve_offer():
  assert admin.request.post(a.url+'/api/admin/moderation/'+state['offer']['revision']['id'],data={'decision':'approve'},headers={'X-QM-Client':'web'}).status==200
  assert member.request.get(a.url+'/api/catalog/'+state['venue']['id']).json()['offers'][0]['data']['percent']==18
 record('API: approved discount reaches the member catalog',approve_offer)
 def submit_banner():
  menu(op,'Баннеры');op.get_by_role('button',name='Добавить',exact=True).click();op.wait_for_timeout(800);choose_venue();fill(op,'Название','QA — баннер '+suffix);fill(op,'Описание','QA — объявление для участников')
  with op.expect_file_chooser() as chooser:seek(op,op.get_by_role('button',name='Загрузить фотографию / баннер',exact=True)).click()
  with op.expect_response(lambda r:r.request.method=='POST' and r.url.endswith('/api/media')) as pending:chooser.value.set_files(str(fixture('banner-qa.png',Path(__file__).resolve().parents[2]/'mobile/assets/flora.png','#e7d9f0')))
  assert pending.value.status==201;op.wait_for_timeout(500);seek(op,op.get_by_role('button',name='Отправить на модерацию',exact=True)).click();op.wait_for_timeout(600)
  banner=next(v for v in owner.request.get(a.url+'/api/workspace/resources?kind=banner').json() if v['venue_id']==state['venue']['id']);state['banner']=banner
  assert not any(v['id']==banner['id'] for v in member.request.get(a.url+'/api/banners').json())
 record('partner: upload a banner and keep it hidden until moderation',submit_banner)
 def approve_banner():
  assert admin.request.post(a.url+'/api/admin/moderation/'+state['banner']['revision']['id'],data={'decision':'approve'},headers={'X-QM-Client':'web'}).status==200
  assert any(v['id']==state['banner']['id'] for v in member.request.get(a.url+'/api/banners').json())
 record('API: banner publication follows moderation',approve_banner)
 def export_qr():
  menu(op,'Обзор');menu(op,'Заведения');op.get_by_role('button',name='Выдать QR',exact=True).first.click();op.wait_for_timeout(400)
  with op.expect_response(lambda r:r.request.method=='POST' and r.url.endswith('/'+state['venue']['id']+'/qr')) as pending:op.get_by_role('button',name='Продолжить',exact=True).click()
  assert pending.value.status==200;state['code']=pending.value.json()['code'];op.wait_for_timeout(900)
  with op.expect_download(timeout=20000) as downloaded:seek(op,op.get_by_role('button',name='Сохранить / поделиться QR',exact=True)).click()
  downloaded.value.save_as(str(a.private_dir/'qr-poster.png'));assert (a.private_dir/'qr-poster.png').stat().st_size>10000
 record('partner: generate a QR and download its PNG poster in the browser',export_qr)
 owner.close();admin.close();member.close();b.close()
(a.output/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print('SUMMARY',len(results),'PASS',sum(v['status']=='PASS' for v in results))
