"""Synthetic fixtures for an EMPTY qazaqmetal_load database; never real employees.
Output contains private test tokens and passwords. Never commit or publish it.
"""
from pathlib import Path
import argparse,os,json,sys,secrets,uuid
from datetime import timedelta
parser=argparse.ArgumentParser();parser.add_argument('--private-output',type=Path,required=True);args=parser.parse_args()
assert os.environ.get('DATABASE_URL','').split('?')[0].endswith('/qazaqmetal_load'), 'Dedicated qazaqmetal_load database required'
assert os.environ.get('APP_ENV')!='production', 'Synthetic fixtures are not production data'
P=args.private_output;P.mkdir(parents=True,exist_ok=True);P.chmod(0o700)
assert not (P/'accounts.json').exists(), 'Preserve previous fixtures'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'server'))
from app.db import SessionLocal,Organization,Partner,User,Session,Resource,Revision,Visit,now
from app.security import hash_password,digest
from app.schemas import ResourceData
from sqlalchemy import insert,select
with SessionLocal() as db:
 if db.scalar(select(User.id).limit(1)):raise SystemExit('Lab already seeded')
 organizations=[{'id':str(uuid.uuid4()),'code':f'LOAD{i}','name':f'Нагрузочная организация {i}','active':True} for i in range(4)];db.execute(insert(Organization),organizations)
 partners=[{'id':str(uuid.uuid4()),'name':f'Нагрузочный партнёр {i}','active':True} for i in range(10)];db.execute(insert(Partner),partners)
 password=secrets.token_urlsafe(20);hashed=hash_password(password);users=[];sessions=[];accounts=[]
 for i in range(10000):
  identifier=f'LOAD-{i:05}';user_id=str(uuid.uuid4());org=organizations[i%4]['id'];token=secrets.token_urlsafe(48)
  users.append({'id':user_id,'name':f'Нагрузочный участник {i}','employee_number':identifier,'organization_id':org,'role':'member','status':'active','password_hash':hashed,'must_change_password':False})
  sessions.append({'id':digest(token),'user_id':user_id,'expires_at':now()+timedelta(days=30)})
  accounts.append({'id':user_id,'organization_id':org,'identifier':identifier,'token':token})
 for i in range(0,len(users),500):db.execute(insert(User),users[i:i+500]);db.execute(insert(Session),sessions[i:i+500])
 managers={}
 for role in ['admin','partner']:
  token=secrets.token_urlsafe(48);u=User(username='load-'+role,name='Нагрузочный '+role,role=role,partner_id=partners[0]['id'] if role=='partner' else None,password_hash=hashed,must_change_password=False);db.add(u);db.flush();db.add(Session(id=digest(token),user_id=u.id,expires_at=now()+timedelta(days=30)));managers[role]={'id':u.id,'identifier':'load-'+role,'token':token}
 venues=[];offers=[];revisions=[]
 for i in range(100):
  partner=partners[i%10]['id'];v=str(uuid.uuid4());token=secrets.token_urlsafe(32);d=ResourceData(name=f'Тестовое заведение {i:03}',category=['Рестораны','Кафе','Магазины','Спорт'][i%4],address=f'Павлодар, тестовый адрес {i}',description='Синтетическое описание для замера производительности. '*4,latitude=52.27+(i%10)*.003,longitude=76.94+(i//10)*.004).model_dump(mode='json')
  venues.append({'id':v,'partner_id':partner,'code':f'QAZAQMETAL:1:{v}:{token}','data':d});db.add(Resource(id=v,kind='venue',partner_id=partner,published=d,version=1,latitude=d['latitude'],longitude=d['longitude'],qr_hash=digest(token)));db.flush()
  for j in range(2):
   o=str(uuid.uuid4());od=ResourceData(name=f'Скидка {j+1}',percent=10+j*5,terms='Условия нагрузочного теста. '*6).model_dump(mode='json');db.add(Resource(id=o,kind='offer',partner_id=partner,venue_id=v,published=od,version=1));offers.append({'id':o,'venue_id':v,'partner_id':partner,'data':od});revisions.append({'id':str(uuid.uuid4()),'resource_id':o,'author_id':managers['partner']['id'],'payload':od,'action':'publish','base_version':0,'status':'approved'})
  revisions.append({'id':str(uuid.uuid4()),'resource_id':v,'author_id':managers['partner']['id'],'payload':d,'action':'publish','base_version':0,'status':'approved'})
 db.flush();db.execute(insert(Revision),revisions)
 history=[]
 for i in range(20000):
  u=accounts[i%10000];o=offers[i%len(offers)];history.append({'id':str(uuid.uuid4()),'request_id':str(uuid.uuid4()),'user_id':u['id'],'organization_id':u['organization_id'],'partner_id':o['partner_id'],'venue_id':o['venue_id'],'offer_id':o['id'],'venue_name':'Тестовое заведение','offer_name':o['data']['name'],'percent':o['data']['percent'],'created_at':now()-timedelta(days=1,seconds=i)})
 for i in range(0,len(history),1000):db.execute(insert(Visit),history[i:i+1000])
 db.commit()
 (P/'accounts.json').write_text(json.dumps({'accounts':accounts,'managers':managers,'venues':venues,'password':password},ensure_ascii=False));(P/'accounts.json').chmod(0o600)
print('Seeded: 10,000 synthetic members, 100 venues, 200 offers, 300 revisions, 20,000 visits; private sessions created')
