"""Explicitly requested demo setup. Idempotent: never reset an existing password or QR."""
import hashlib,json,os,sys
from pathlib import Path
from PIL import Image
from sqlalchemy import select
sys.path.insert(0,'/app')
from app.db import Audit,Organization,Partner,Resource,Revision,SessionLocal,User,now
from app.schemas import ResourceData
from app.security import digest,hash_password

settings=json.load(sys.stdin)
initial=settings['initial_password']
assets=Path(os.environ.get('DEMO_ASSET_DIR','/tmp/qazaqmetal-demo-assets'))
uploads=Path(os.environ.get('UPLOAD_DIR','/data/uploads'))
state_path=uploads/'.demo-setup.json'
state=json.loads(state_path.read_text()) if state_path.exists() else {'partners':[]}
presets={p['key']:p for p in json.loads((assets/'qr-codes.json').read_text())['partners']}
translations=json.loads((assets/'translations-kk.json').read_text()) if (assets/'translations-kk.json').exists() else {}
def localized_value(field, value, payload, kind):
    translated=translations.get(value, '')
    if translated:
        return translated
    if field=='name' and kind=='offer' and value.startswith('ДЕМО · Скидка '):
        return 'ДЕМО · Кәсіподақ мүшелеріне '+str(payload.get('percent', ''))+'% жеңілдік'
    if field=='name' and kind=='banner':
        for preset in presets.values():
            if value.startswith(preset['name']+' −'):
                return translations.get(preset['name'],preset['name'])+value[len(preset['name']):]
    return ''


with SessionLocal() as db:
    admin=db.scalar(select(User).where(User.username=='qazaqmetal-admin'))
    if not admin:
        admin=User(username='qazaqmetal-admin',name='Администратор профсоюза',role='admin',password_hash=hash_password(settings['admin_password']),must_change_password=True)
        db.add(admin);db.flush();db.add(Audit(actor_id=admin.id,action='bootstrap_admin',target=admin.id,detail={}))
    org=db.scalar(select(Organization).where(Organization.code=='DEMO'))
    if not org:
        org=Organization(code='DEMO',name='Демонстрационная организация · QAZAQMETAL');db.add(org);db.flush()
    for number in ('01','02'):
        user=db.scalar(select(User).where(User.organization_id==org.id,User.employee_number==number))
        if not user:
            user=User(organization_id=org.id,employee_number=number,name='Тестовый участник '+number,role='member',password_hash=hash_password(initial),must_change_password=True)
            db.add(user);db.flush();db.add(Audit(actor_id=admin.id,action='demo_member_created',target=user.id,detail={'employee_number':number}))
    definitions=[
      dict(key='restaurant',name='ДЕМО · Ресторан «Сад»',category='Еда и напитки',percent=15,lat=52.2873,lon=76.9674,address='Павлодар · демонстрационная точка в центре города',hours='Ежедневно, 12:00–23:00 · демонстрационное расписание',description='Светлый ресторан с авторской европейской кухней, сезонным меню и уютным залом для встреч с близкими. В карточке показан пример полноценного предложения партнёра. Заведение, адрес и скидка демонстрационные.',terms='Демонстрационная скидка 15% на основное меню, включая безалкогольные напитки. Для 1–6 гостей в одном чеке. Не суммируется с другими акциями. Алкоголь и бизнес-ланчи исключены. Только для активных членов демонстрационной организации. Это тестовое предложение, не реальная скидка.'),
      dict(key='flowers',name='ДЕМО · Цветочная мастерская «Лепесток»',category='Магазины',percent=10,lat=52.2818,lon=76.9598,address='Павлодар · демонстрационная точка рядом с набережной',hours='Ежедневно, 09:00–21:00 · демонстрационное расписание',description='Мастерская букетов из сезонных цветов: нежные композиции, подарочная упаковка и индивидуальный подбор оттенков. Полностью заполненная тестовая карточка для знакомства с приложением. Мастерская и её предложение демонстрационные.',terms='Демонстрационная скидка 10% на готовые букеты и композиции из наличия. Доставка, свадебное оформление и товары по специальной цене исключены. Не суммируется с другими акциями. Только для активных членов демонстрационной организации. Это тестовое предложение, не реальная скидка.')]
    def publish(kind,partner,venue,payload,resource_id=None):
        for field in ('name','description','category','address','hours','terms'):
            if not payload.get(field+'_kk') and payload.get(field):
                payload[field+'_kk']=localized_value(field,payload[field],payload,kind)
        payload=ResourceData(**payload).model_dump(mode='json')
        resource=Resource(**({'id':resource_id} if resource_id else {}),kind=kind,partner_id=partner.id,venue_id=venue.id if venue else None,published=payload,version=1,latitude=payload['latitude'],longitude=payload['longitude'])
        db.add(resource);db.flush()
        db.add(Revision(resource_id=resource.id,author_id=admin.id,payload=payload,base_version=0,status='approved',moderator_id=admin.id,reviewed_at=now(),reason='Демонстрационное наполнение по прямому запросу владельца проекта'))
        db.add(Audit(actor_id=admin.id,action='demo_resource_approved',target=resource.id,detail={'kind':kind,'demonstration':True}))
        return resource
    def media(key,suffix):
        source=assets/(key+'-'+suffix+'.png');filename=hashlib.sha256(('qazaqmetal-demo-v1-'+key+suffix).encode()).hexdigest()[:32]+'.webp'
        destination=uploads/filename
        if not destination.exists():
            with Image.open(source) as image:
                image.convert('RGB').save(destination,'WEBP',quality=92,method=6)
        return '/media/'+filename
    for i,entry in enumerate(definitions,1):
        partner=db.scalar(select(Partner).where(Partner.name==entry['name']))
        if partner:continue
        partner=Partner(name=entry['name']);db.add(partner);db.flush()
        owner=User(username='partner0'+str(i),partner_id=partner.id,name='Демо-кабинет партнёра '+str(i),role='partner',password_hash=hash_password(initial),must_change_password=True)
        db.add(owner);db.flush()
        common={'name':entry['name'],'description':entry['description'],'category':entry['category'],'address':entry['address'],'hours':entry['hours'],'latitude':entry['lat'],'longitude':entry['lon'],'organization_ids':[org.id]}
        preset=presets[entry['key']]
        venue=publish('venue',partner,None,{**common,'image':media(entry['key'],'photo')},preset['venue_id'])
        offer=publish('offer',partner,venue,{'name':'ДЕМО · Скидка '+str(entry['percent'])+'% для членов профсоюза','description':entry['description'],'percent':entry['percent'],'terms':entry['terms'],'organization_ids':[org.id]},preset['offer_id'])
        publish('banner',partner,venue,{'name':'ДЕМО · '+entry['name'].split(' · ',1)[1]+' −'+str(entry['percent'])+'%','description':entry['description'],'image':media(entry['key'],'banner'),'organization_ids':[org.id]})
        token=preset['code'].rsplit(':',1)[1];venue.qr_hash=digest(token)
        state['partners'].append({'name':entry['name'],'venue_id':venue.id,'offer_id':offer.id,'percent':entry['percent'],'code':f'QAZAQMETAL:1:{venue.id}:{token}'})
    # Fill missing Kazakh fields only on the two explicitly requested demo partners.
    # Preserve edited fields, pending revisions, passwords, QR codes and existing histories.
    for entry in definitions:
        partner=db.scalar(select(Partner).where(Partner.name==entry['name']))
        if not partner:
            continue
        for resource in db.scalars(select(Resource).where(Resource.partner_id==partner.id, Resource.deleted.is_(False))):
            if not resource.published or db.scalar(select(Revision.id).where(Revision.resource_id==resource.id,Revision.status=='pending')):
                continue
            payload=dict(resource.published)
            changed=False
            for field in ('name','description','category','address','hours','terms'):
                translated=localized_value(field,payload.get(field, ''),payload,resource.kind)
                if translated and not payload.get(field+'_kk'):
                    payload[field+'_kk']=translated
                    changed=True
            if changed:
                base=resource.version
                resource.published=ResourceData(**payload).model_dump(mode='json')
                resource.version+=1
                db.add(Revision(resource_id=resource.id,author_id=admin.id,payload=resource.published,base_version=base,status='approved',moderator_id=admin.id,reviewed_at=now(),reason='Добавлен казахский перевод демо по запросу владельца'))
                db.add(Audit(actor_id=admin.id,action='demo_locale_added',target=resource.id,detail={'language':'kk'}))
    db.commit()
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2));state_path.chmod(0o600)
print(json.dumps(state,ensure_ascii=False))
