"""Real browser actions against isolated synthetic QA data; no hardware claims."""
import argparse,json,re,shutil,time
from pathlib import Path
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--credentials',type=Path,required=True);p.add_argument('--url',default='http://127.0.0.1:8000');p.add_argument('--output',type=Path,default=Path('artifacts/interactions'));a=p.parse_args();creds=json.loads(a.credentials.read_text());assert all(v['identifier'].lower().startswith('qa') for v in creds.values());a.output.mkdir(parents=True,exist_ok=True);checks=[]
def run(name,fn):
 try:fn();checks.append({'case':name,'status':'PASS'})
 except Exception as e:checks.append({'case':name,'status':'FAIL','error_type':type(e).__name__,'details':str(e)[:700]})
 print(checks[-1],flush=True)
def fill(page,label,value):
 page.get_by_role('textbox',name=label,exact=True).click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value);page.wait_for_timeout(600)
def back(page):page.get_by_role('button',name=re.compile(r'^(Back|Назад)$')).click();page.wait_for_timeout(500)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path=shutil.which('chromium'),args=['--no-sandbox','--disable-dev-shm-usage'])
 def login(role,width=390):
  ctx=b.new_context(viewport={'width':width,'height':900});page=ctx.new_page();page.set_default_timeout(5000);page.goto(a.url);page.wait_for_timeout(1800)
  if page.locator('flt-semantics-placeholder').count():page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
  fill(page,'Табельный номер / телефон / логин',creds[role]['identifier']);fill(page,'Пароль',creds[role]['password']);page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1500);return ctx,page
 ctx,page=login('member')
 def search():
  page.get_by_role('tab',name='Партнёры',exact=True).click();page.wait_for_timeout(600)
  fill(page,'Найти партнёра','Несуществующий-партнёр-QA-99999')
  assert ctx.request.get(a.url+'/api/catalog?q=Несуществующий-партнёр-QA-99999').json()['total']==0
  fill(page,'Найти партнёра','QA — ресторан')
  page.get_by_role('button',name=re.compile('QA — ресторан')).first.click();page.wait_for_timeout(900)
  assert page.get_by_role('button',name='Сканировать QR',exact=True).is_visible()
 run('member: search empty result, search and open partner',search)
 def favorite():
  (a.output/'venue-semantics.txt').write_text(page.locator('body').aria_snapshot())
  page.screenshot(path=str(a.output/'venue-before-favorite.png'))
  locator=page.get_by_role('button',name='В избранное',exact=True)
  if locator.count():
   locator.click();page.mouse.move(5,5);page.wait_for_timeout(1000)
  (a.output/'venue-after-add-semantics.txt').write_text(page.locator('body').aria_snapshot())
  page.screenshot(path=str(a.output/'venue-after-add.png'))
  assert len(ctx.request.get(a.url+'/api/me/favorites').json())>=1, 'UI add not persisted'
  page.get_by_role('button',name='Убрать из избранного',exact=True).click();page.mouse.move(5,5);page.wait_for_timeout(1000)
  page.get_by_role('button',name='В избранное',exact=True).wait_for(state='visible')
 run('member: favorite add/remove persisted',favorite)
 run('member: back from venue',lambda:back(page))
 def qr():
  page.get_by_role('tab',name='QR',exact=True).click();page.wait_for_timeout(1500)
  page.get_by_text('Ввести QR-код вручную',exact=True).click();page.wait_for_timeout(500)
  fill(page,'Текст QR-кода','https://example.invalid/do-not-open')
  page.get_by_role('button',name='Применить код',exact=True).click();page.wait_for_timeout(700)
  assert page.url.startswith(a.url)
  assert 'QR не относится к заведению' in page.locator('body').inner_text()
  page.screenshot(path=str(a.output/'qr-invalid.png'))
 run('member: camera unavailable and manual invalid URL stays in app',qr)
 def support():
  page.get_by_role('tab',name='Профиль',exact=True).click();page.wait_for_timeout(500)
  page.get_by_text('Поддержка',exact=True).first.click();page.wait_for_timeout(500)
  page.get_by_role('button',name='Новое обращение',exact=True).click();page.wait_for_timeout(400)
  fill(page,'Тема','QA проверка интерфейса');fill(page,'Сообщение','Синтетическое обращение из автоматического теста')
  page.get_by_role('button',name='Отправить',exact=True).click();page.wait_for_timeout(700)
  assert any(t['subject']=='QA проверка интерфейса' for t in ctx.request.get(a.url+'/api/tickets').json())
  back(page)
 run('member: create support ticket using form',support)
 ctx.close()
 for role in ['partner','admin']:
  ctx,page=login(role,1320)
  for name in ['Заведения','Скидки и акции','Баннеры']+(['Организации','Партнёры','Участники и доступ'] if role=='admin' else []):
   def form(name=name):
    page.get_by_text(name,exact=True).first.click();page.wait_for_timeout(500)
    page.get_by_role('button',name='Добавить',exact=True).click();page.wait_for_timeout(500)
    assert page.get_by_role('textbox').count()>0
    back(page)
   run(role+': open creation form/back '+name,form)
  ctx.close()
 b.close()
(a.output/'results.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2));print('SUMMARY',len(checks),'PASS',sum(c['status']=='PASS' for c in checks),'FAIL',sum(c['status']=='FAIL' for c in checks));raise SystemExit(any(c['status']=='FAIL' for c in checks))
