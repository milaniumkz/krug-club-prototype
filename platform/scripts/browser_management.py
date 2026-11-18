"""Additional real UI checks against synthetic QA data. Never log temporary passwords."""
import argparse,json,re,secrets,shutil,time
from pathlib import Path
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:8018');p.add_argument('--credentials',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('artifacts/management'));a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);creds=json.loads(a.credentials.read_text());assert all(v['identifier'].lower().startswith('qa') for v in creds.values());results=[];suffix=str(int(time.time()))
def test(name,fn):
 try:fn();results.append({'case':name,'status':'PASS'})
 except Exception as e:
  results.append({'case':name,'status':'FAIL','error_type':type(e).__name__,'details':str(e)[:500]})
  active=globals().get('current_page')
  if active is not None and not active.is_closed():
   active.goto(a.url);active.wait_for_timeout(1800)
   if active.locator('flt-semantics-placeholder').count():active.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
 print(results[-1],flush=True)
def fill(page,label,value):
 box=page.get_by_role('textbox',name=label,exact=True);box.click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value);page.wait_for_timeout(180)
def fill_any(page,value):
 box=page.get_by_role('textbox').last;box.click();page.wait_for_timeout(250);page.keyboard.press('ControlOrMeta+A');page.keyboard.insert_text(value)
def settle(page):page.wait_for_timeout(750)
def menu(page,label):page.get_by_text(label,exact=True).first.click();settle(page)
def require(value):assert value
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path=shutil.which('chromium'),args=['--no-sandbox','--disable-dev-shm-usage'])
 def new_page(role=None,width=1320):
  global current_page
  ctx=b.new_context(viewport={'width':width,'height':1000},permissions=['clipboard-read','clipboard-write']);page=ctx.new_page();current_page=page;page.set_default_timeout(6500);page.goto(a.url);page.wait_for_timeout(2200)
  if page.locator('flt-semantics-placeholder').count():page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
  if role:
   fill(page,'Табельный номер / телефон / логин',creds[role]['identifier']);fill(page,'Пароль',creds[role]['password']);page.get_by_role('button',name='Войти',exact=True).click();page.wait_for_timeout(1600)
  return ctx,page
 ctx,page=new_page(width=390)
 def wrong_login():
  fill(page,'Табельный номер / телефон / логин',creds['member']['identifier']);fill(page,'Пароль','WrongSyntheticPassword!')
  page.get_by_role('button',name='Войти',exact=True).click();settle(page)
  require('Неверные данные входа' in page.locator('body').inner_text());require(ctx.request.get(a.url+'/api/auth/me').status==401)
 test('login: wrong password shows error and creates no session',wrong_login)
 test('login: show password button',lambda:(page.get_by_role('button',name='Показать пароль',exact=True).click(),page.mouse.move(5,5),settle(page),require(page.get_by_role('button',name='Скрыть пароль',exact=True).count()==1)))
 test('login: hide password button',lambda:(page.get_by_role('button',name='Скрыть пароль',exact=True).click(),page.mouse.move(5,5),settle(page),require(page.get_by_role('button',name='Показать пароль',exact=True).count()==1)))
 def wrong_org():
  fill(page,'Пароль',creds['member']['password']);page.get_by_text('Код организации, если требуется',exact=True).click();settle(page);fill(page,'Код организации','QA_ABSENT')
  page.get_by_role('button',name='Войти',exact=True).click();settle(page);require(ctx.request.get(a.url+'/api/auth/me').status==401)
 test('login: wrong organization is rejected',wrong_org)
 def correct_org():
  fill(page,'Код организации','QA')
  with page.expect_response(lambda r:r.request.method=='POST' and r.url.endswith('/api/auth/login')) as pending:
   page.get_by_role('button',name='Войти',exact=True).click()
  result=pending.value;sent=result.request.post_data_json
  assert result.status==200, f'login status={result.status}, identifier_matches={sent["identifier"]==creds["member"]["identifier"]}, password_matches={sent["password"]==creds["member"]["password"]}, organization_matches={sent["organization_code"]=="QA"}'
  page.wait_for_timeout(1200);require(ctx.request.get(a.url+'/api/auth/me').status==200)
 test('login: employee number and organization sign in',correct_org)
 ctx.close()
 admin,ap=new_page('admin')
 created={}
 def create_entity(kind,label,name,code=None):
  menu(ap,label);ap.get_by_role('button',name='Добавить',exact=True).click();settle(ap);fill(ap,'Название',name)
  if code:fill(ap,'Код организации (латиница / цифры)',code)
  ap.get_by_role('button',name='Сохранить',exact=True).click();settle(ap)
  row=next(x for x in admin.request.get(a.url+'/api/admin/'+kind).json() if x['name']==name);created[kind]=row
 test('admin: create organization using form',lambda:create_entity('organizations','Организации','QA — отдел '+suffix,'QA'+suffix))
 def edit_entity(kind,label,active):
  row=created[kind];menu(ap,label);ap.get_by_role('button',name=re.compile(re.escape(row['name']))).first.click();settle(ap)
  ap.get_by_role('switch',name=re.compile('Доступ разрешён')).click();ap.get_by_role('button',name='Сохранить',exact=True).click();settle(ap)
  fresh=next(x for x in admin.request.get(a.url+'/api/admin/'+kind).json() if x['id']==row['id']);require(fresh['active']==active)
 test('admin: disable organization using switch',lambda:edit_entity('organizations','Организации',False))
 test('admin: enable organization using switch',lambda:edit_entity('organizations','Организации',True))
 test('admin: create partner using form',lambda:create_entity('partners','Партнёры','QA — партнёр '+suffix))
 test('admin: disable partner using switch',lambda:edit_entity('partners','Партнёры',False))
 test('admin: enable partner using switch',lambda:edit_entity('partners','Партнёры',True))
 imported={}
 def csv_import():
  menu(ap,'Участники и доступ');ap.get_by_role('button',name='Импорт CSV',exact=True).click();settle(ap)
  with ap.expect_file_chooser() as picker:ap.get_by_text('QA — тестовая организация',exact=True).last.click()
  csv='employee_number,name\nQA-'+suffix+'1,QA — импорт один\nQA-'+suffix+'2,QA — импорт два\n'
  with ap.expect_response(lambda r:r.request.method=='POST' and '/api/admin/accounts/import' in r.url) as pending:
   picker.value.set_files({'name':'qa.csv','mimeType':'text/csv','buffer':csv.encode()})
  response=pending.value;require(response.status==200);payload=response.json();require(payload['count']==2);require(len({x['temporary_password'] for x in payload['credentials']})==2)
  imported.update(payload['credentials'][0]);ap.get_by_role('button',name='Сохранено',exact=True).click();settle(ap)
 test('admin: CSV import with two individual temporary passwords',csv_import)
 target={}
 def search_member():
  menu(ap,'Участники и доступ');fill(ap,'Имя или табельный номер',imported['employee_number']);ap.keyboard.press('Enter');settle(ap)
  entries=admin.request.get(a.url+'/api/admin/accounts',params={'q':imported['employee_number']}).json()['items'];require(len(entries)==1);target.update(entries[0]);require(ap.get_by_role('button',name='Временный пароль',exact=True).count()==1)
 test('admin: member search by employee number',search_member)
 def change_status(button,status,reason):
  require(bool(target.get('id')));search_member()
  ap.get_by_role('button',name=button,exact=True).click();settle(ap);fill_any(ap,reason);ap.get_by_role('button',name='Продолжить',exact=True).click();settle(ap)
  require(admin.request.get(a.url+'/api/admin/accounts',params={'q':imported['employee_number']}).json()['items'][0]['status']==status)
 test('admin: block member with reason',lambda:change_status('Блокировать','blocked','QA — нарушение правил'))
 test('admin: restore member with reason',lambda:change_status('Восстановить','active','QA — доступ восстановлен'))
 def reset():
  require(bool(target.get('id')));search_member()
  ap.get_by_role('button',name='Временный пароль',exact=True).click();settle(ap)
  with ap.expect_response(lambda r:r.request.method=='POST' and r.url.endswith('/reset-password')) as pending:ap.get_by_role('button',name='Продолжить',exact=True).click()
  require(pending.value.status==200);require(pending.value.json()['temporary_password']!=imported['temporary_password'])
  ap.get_by_role('button',name='Сохранено',exact=True).click();settle(ap)
 test('admin: issue a new temporary password',reset)
 test('admin: remove from club only with dismissal reason',lambda:change_status('Удалить: уволен','dismissed','QA — увольнение из организации'))
 def reply():
  tickets=admin.request.get(a.url+'/api/tickets').json();require(bool(tickets));ticket=tickets[0]
  menu(ap,'Обращения');ap.get_by_role('button',name='Ответить и закрыть',exact=True).first.click();settle(ap);fill_any(ap,'QA — обращение обработано');ap.get_by_role('button',name='Продолжить',exact=True).click();settle(ap)
  require(any(t['status']=='closed' and t['reply']=='QA — обращение обработано' for t in admin.request.get(a.url+'/api/tickets').json()))
 test('admin: answer and close support ticket',reply)
 admin.close()
 partner,pp=new_page('partner')
 def stats_csv():
  pp.mouse.wheel(0,1400);settle(pp);pp.get_by_role('button',name='Скопировать CSV операций',exact=True).click();settle(pp);require('CSV операций скопирован' in pp.locator('body').inner_text())
 test('partner: export statistics to CSV clipboard',stats_csv)
 for label in ['Дата от','Дата до']:
  def picker(label=label):
   pp.mouse.wheel(0,-1500);settle(pp);pp.get_by_role('button',name=label,exact=True).click();settle(pp);pp.get_by_role('button',name=re.compile(r'^(Отмена|ОТМЕНА)$')).click();settle(pp)
  test('partner: date picker opens and cancels '+label,picker)
 test('partner: reset statistics filters',lambda:(pp.get_by_role('button',name='Сбросить',exact=True).click(),settle(pp),require(partner.request.get(a.url+'/api/workspace/stats').status==200)))
 partner.close();b.close()
(a.output/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print('SUMMARY',len(results),'PASS',sum(c['status']=='PASS' for c in results),'FAIL',sum(c['status']=='FAIL' for c in results));raise SystemExit(any(c['status']=='FAIL' for c in results))
