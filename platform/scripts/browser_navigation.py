"""QA-only browser navigation matrix. Complements browser_smoke.py and API tests.
Never claims physical device/camera coverage; credentials and responses stay private.
"""
import argparse,json,shutil,time,re
from pathlib import Path
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--credentials',type=Path,required=True);p.add_argument('--url',default='http://127.0.0.1:8000');p.add_argument('--output',type=Path,default=Path('artifacts/navigation'));a=p.parse_args();creds=json.loads(a.credentials.read_text());assert all(v['identifier'].lower().startswith('qa') for v in creds.values());a.output.mkdir(parents=True,exist_ok=True);checks=[]
def check(name,fn):
 t=time.time()
 try:fn();checks.append({'case':name,'status':'PASS','seconds':round(time.time()-t,2)})
 except Exception as e:checks.append({'case':name,'status':'FAIL','error_type':type(e).__name__,'seconds':round(time.time()-t,2)})
 print(checks[-1],flush=True)
def enable(page):
 page.wait_for_timeout(1800)
 if page.locator('flt-semantics-placeholder').count():page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
 page.wait_for_timeout(300)
def fill(page,label,value):
 field=page.get_by_role('textbox',name=label,exact=True);field.click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value);page.wait_for_timeout(200)
def back(page):
 page.get_by_role('button',name=re.compile(r'^(Back|Назад)$')).click();page.wait_for_timeout(600)
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path=shutil.which('chromium'),args=['--no-sandbox','--disable-dev-shm-usage'])
 for role in ['member','partner','admin']:
  ctx=browser.new_context(viewport={'width':390 if role=='member' else 1320,'height':844 if role=='member' else 900},permissions=['geolocation'],geolocation={'latitude':52.287,'longitude':76.967})
  page=ctx.new_page();page.set_default_timeout(5000);page.goto(a.url);enable(page)
  fill(page,'Табельный номер / телефон / логин',creds[role]['identifier']);fill(page,'Пароль',creds[role]['password']);page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1800)
  check(role+': persisted authenticated API',lambda: (_ for _ in ()).throw(AssertionError()) if ctx.request.get(a.url+'/api/auth/me').status!=200 else None)
  if role=='member':
   for tab in ['Главная','Партнёры','На карте','QR','Профиль']:
    check('member: tab '+tab,lambda tab=tab: (page.get_by_role('tab',name=tab,exact=True).click(),page.wait_for_timeout(1200)))
   for label in ['Моя карта','Избранное','История скидок','Изменить пароль','Поддержка','Активные сессии']:
    def visit(label=label):
     page.get_by_text(label,exact=True).first.click();page.wait_for_timeout(700);back(page)
    check('member: open/back '+label,visit)
   page.screenshot(path=str(a.output/'member-profile.png'))
   for w,h in [(320,640),(390,844),(430,932),(768,1024)]:
    def resize(w=w,h=h):
     page.set_viewport_size({'width':w,'height':h});page.wait_for_timeout(800)
     assert page.get_by_role('tab',name='QR',exact=True).is_visible()
     assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
     page.screenshot(path=str(a.output/f'member-{w}x{h}.png'))
    check(f'member: layout {w}x{h}',resize)
  else:
   menu=['Обзор','Заведения','Скидки и акции','Баннеры']+(['Модерация','Участники и доступ','Организации','Партнёры','Обращения','Журнал действий'] if role=='admin' else [])+['Профиль']
   for label in menu:
    def visit(label=label):
     page.get_by_text(label,exact=True).first.click();page.wait_for_timeout(600)
     assert 'Exception caught' not in page.locator('body').inner_text()
    check(role+': navigation '+label,visit)
   page.screenshot(path=str(a.output/(role+'-profile.png')))
  ctx.close()
 browser.close()
(a.output/'results.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
print('SUMMARY',len(checks),'PASS',sum(c['status']=='PASS' for c in checks),'FAIL',sum(c['status']=='FAIL' for c in checks))
raise SystemExit(any(c['status']=='FAIL' for c in checks))
