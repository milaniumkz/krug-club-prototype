import json
from types import SimpleNamespace
from app.push_worker import message_for
from conftest import login


def test_web_config_whitelist_worker_and_role_isolation(world, monkeypatch):
    c, _, _ = world
    monkeypatch.setenv('MEMBER_HOST','testserver')
    monkeypatch.setenv('PARTNER_HOST','qazaqmetalpartners.109.235.119.144.sslip.io')
    monkeypatch.setenv('ADMIN_HOST','qazaqmetaladmin.109.235.119.144.sslip.io')
    options={'apiKey':'public','appId':'web-app','messagingSenderId':'123','projectId':'test','authDomain':'test.firebaseapp.com','private_key':'MUST_NOT_LEAK'}
    monkeypatch.setenv('FIREBASE_CLIENT_CONFIG',json.dumps({'member':{'web':options},'partner':{'web':{**options,'appId':'partner-web'}}}))
    monkeypatch.setenv('FIREBASE_WEB_VAPID_KEY','B'+'a'*86)
    r=c.get('/api/push-config?platform=web');assert r.status_code==200 and r.json()['enabled']
    assert 'private_key' not in r.text
    worker=c.get('/api/push-config.js');assert worker.status_code==200
    assert worker.headers['content-type'].startswith('application/javascript')
    assert worker.text.startswith('self.QM_FIREBASE_CONFIG=') and 'MUST_NOT_LEAK' not in worker.text
    assert c.get('/api/push-config?platform=web',headers={'host':'qazaqmetalpartners.109.235.119.144.sslip.io'}).json()['options']['appId']=='partner-web'
    assert c.get('/api/push-config.js',headers={'host':'qazaqmetaladmin.109.235.119.144.sslip.io'}).text=='self.QM_FIREBASE_CONFIG={"enabled": false};'
    monkeypatch.delenv('FIREBASE_WEB_VAPID_KEY');assert not c.get('/api/push-config?platform=web').json()['enabled']


def test_push_links_channels_language_and_same_origin(monkeypatch):
    monkeypatch.setenv('MEMBER_HOST','members.example.org');monkeypatch.setenv('PARTNER_HOST','partners.example.org')
    notice=SimpleNamespace(id='notice-1',venue_id='venue-1',kind='new_venue',title='Новое',body='Текст',title_kk='Жаңа',body_kk='Мәтін')
    device=SimpleNamespace(token='private-device-token',language='kk')
    m=message_for(notice,device,SimpleNamespace(role='member'))
    assert m['notification']=={'title':'Жаңа','body':'Мәтін'}
    assert m['android']['notification']['channel_id']=='union_updates'
    assert m['webpush']['fcm_options']['link']=='https://members.example.org/?notification=notice-1'
    assert m['webpush']['notification']['tag']=='notice-1'
    m=message_for(notice,device,SimpleNamespace(role='partner'))
    assert m['android']['notification']['channel_id']=='partner_updates'
    assert m['webpush']['fcm_options']['link'].startswith('https://partners.example.org/')


def test_device_reassignment_and_logout_do_not_leak_notifications(world):
    c, factory, _=world
    from sqlalchemy import select
    from app.db import PushDevice
    member=login(c,'1001');partner=login(c,'owner')
    body={'token':'test-device-token-for-account-switch','platform':'web','language':'kk'}
    first=c.post('/api/me/push-devices',headers=member,json=body);assert first.status_code==201
    second=c.post('/api/me/push-devices',headers=partner,json=body);assert second.json()['id']==first.json()['id']
    c.post('/api/auth/logout',headers=member)
    with factory() as db:
        d=db.scalar(select(PushDevice));assert d.active and db.get(__import__('app.db',fromlist=['User']).User,d.user_id).role=='partner'
    c.post('/api/auth/logout',headers=partner)
    with factory() as db:assert not db.scalar(select(PushDevice)).active
