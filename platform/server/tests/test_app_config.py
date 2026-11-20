import copy
from sqlalchemy import select
from conftest import login
from app.db import AppSetting, Ticket, User
from app.app_config import KEY


def admin_state(c, a):
    r=c.get('/api/admin/app-config',headers=a);assert r.status_code==200
    return r.json()


def save(c,a,state,**changes):
    settings={**state['settings'],**changes}
    return c.put('/api/admin/app-config',headers=a,json={'expected_revision':state['revision'],'settings':settings})


def test_public_config_has_conditional_get_and_no_private_settings(world):
    c,_,_=world
    r=c.get('/api/app-config');assert r.status_code==200
    d=r.json();assert d['schema_version']==1 and d['settings']['brand_name']=='QMET+'
    assert not any(k in d['settings'] for k in ('firebase_private_key','database_url','auth_required'))
    r=c.get('/api/app-config',headers={'If-None-Match':d['etag']});assert r.status_code==304 and not r.content
    assert c.get('/api/admin/app-config').status_code==401


def test_only_admin_updates_and_conflicting_changes_are_rejected(world):
    c,factory,_=world;a,m,p=login(c,'admin'),login(c,'1001'),login(c,'owner')
    state=admin_state(c,a)
    assert save(c,m,state,brand_name='Wrong').status_code==403
    assert save(c,p,state,brand_name='Wrong').status_code==403
    r=save(c,a,state,brand_name='QMET+ Test',tagline_ru='Новый текст');assert r.status_code==200
    updated=c.get('/api/app-config').json();assert updated['revision']==1 and updated['etag']!=state['etag']
    assert updated['settings']['tagline_ru']=='Новый текст'
    assert c.get('/api/meta').json()['brand']=='QMET+ Test'
    assert save(c,a,state,brand_name='Lost update').status_code==409
    with factory() as db:assert db.get(AppSetting,KEY).data['brand_name']=='QMET+ Test'


def test_config_is_data_only_and_validates_links_colors_and_updates(world):
    c,_,_=world;a=login(c,'admin');state=admin_state(c,a)
    for changes in [
        {'accent_color':'javascript:alert(1)'},
        {'accent_color':'#ffffff'},
        {'background_color':'#111111'},
        {'logo_path':'https://external.example/track.svg'},
        {'greeting_ru':'Hello {password}'},
        {'home_sections':['partners','partners']},
        {'support_url':'javascript:alert(1)'},
        {'support_url':'https://user:password@example.com'},
        {'features':{**state['settings']['features'],'auth_required':False}},
        {'versions':{'member':{'android':{'minimum_build':21,'latest_build':21,'store_url':''}}}},
        {'versions':{'member':{'android':{'minimum_build':21,'latest_build':21,'store_url':'https://evil.example/app.apk'}}}},
    ]:
        assert save(c,a,state,**changes).status_code==422
    assert admin_state(c,a)['revision']==0


def test_minimum_native_version_keeps_admin_and_config_available(world):
    c,_,_=world;a,m=login(c,'admin'),login(c,'1001');state=admin_state(c,a)
    policies=copy.deepcopy(state['settings']['versions'])
    policies['member']['android']={'minimum_build':21,'latest_build':21,'store_url':'https://github.com/milaniumkz/krug-club-prototype/releases'}
    assert save(c,a,state,versions=policies).status_code==200
    old={**m,'X-QM-Platform':'android','X-QM-Build':'20'}
    assert c.get('/api/catalog',headers=old).status_code==426
    assert c.get('/api/app-config',headers=old).status_code==200
    assert c.get('/api/health',headers=old).status_code==200
    assert c.get('/api/admin/app-config',headers={**a,'X-QM-Platform':'android','X-QM-Build':'20'}).status_code==200
    assert c.get('/api/catalog',headers={**m,'X-QM-Platform':'android','X-QM-Build':'21'}).status_code==200
    assert c.get('/api/catalog',headers={**m,'X-QM-Platform':'web','X-QM-Build':'1'}).status_code==200


def test_flags_apply_on_server_and_dont_change_authentication(world):
    c,_,_=world;a,m=login(c,'admin'),login(c,'1001');state=admin_state(c,a)
    features={**state['settings']['features'],'qr':False,'map':False,'push':False,'banners':False}
    assert save(c,a,state,features=features).status_code==200
    assert c.get('/api/auth/me',headers=m).status_code==200
    assert c.get('/api/map-style',headers=m).status_code==503
    assert c.get('/api/banners',headers=m).json()==[]
    assert c.get('/api/push-config',headers=m).json()=={'enabled':False}
    assert c.post('/api/scan',headers=m,json={'code':'https://example.com','request_id':'11111111-2222-3333-4444-555555555555'}).status_code==503


def test_legal_documents_escape_text_and_deletion_is_an_idempotent_request(world):
    c,factory,_=world;a,m=login(c,'admin'),login(c,'1001');state=admin_state(c,a)
    assert save(c,a,state,privacy_ru='<script>alert(1)</script>').status_code==200
    legal=c.get('/privacy');assert legal.status_code==200 and '&lt;script&gt;' in legal.text and '<script>' not in legal.text
    assert c.get('/terms?lang=kk').status_code==200
    one=c.post('/api/me/deletion-request',headers=m);two=c.post('/api/me/deletion-request',headers=m)
    assert one.status_code==two.status_code==201 and one.json()['id']==two.json()['id']
    with factory() as db:
        member=db.scalar(select(User).where(User.employee_number=='1001'));assert member.status=='active'
        assert len(db.scalars(select(Ticket).where(Ticket.user_id==member.id)).all())==1
