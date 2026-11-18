from conftest import TEMP

def test_portal_role_and_employee_only_login(world, monkeypatch):
    c, _, _ = world
    monkeypatch.setenv('MEMBER_HOST', 'members.test')
    monkeypatch.setenv('PARTNER_HOST', 'partners.test')
    monkeypatch.setenv('ADMIN_HOST', 'admin.test')
    def login(host, identifier, portal=None):
        c.cookies.clear()
        data={'identifier':identifier, 'password':TEMP}
        if portal:data['portal']=portal
        return c.post('/api/auth/login',headers={'Host':host},json=data)
    assert login('members.test','1001').status_code==200
    assert login('members.test','admin').status_code==401
    assert login('members.test','owner').status_code==401
    assert login('members.test','1001','admin').status_code==403
    assert login('partners.test','1001').status_code==401
    assert login('partners.test','owner').status_code==200
    assert login('admin.test','owner').status_code==401
    admin=login('admin.test','admin');assert admin.status_code==200
    c.cookies.clear()
    assert c.get('/api/auth/me',headers={'Host':'members.test','Authorization':'Bearer '+admin.json()['token']}).status_code==403
    assert login('unknown.test','admin').status_code==421

def test_new_password_six_characters(world):
    c, _, _ = world
    r=c.post('/api/auth/login',json={'identifier':'1001','password':TEMP})
    token=r.json()['token'];c.cookies.clear();headers={'Authorization':'Bearer '+token}
    assert c.post('/api/auth/password',headers=headers,json={'old_password':TEMP,'new_password':'abcde'}).status_code==422
    r=c.post('/api/auth/password',headers=headers,json={'old_password':TEMP,'new_password':'abc123'})
    assert r.status_code==200 and not r.json()['user']['must_change_password']


def test_live_watch_invalidated_on_dismissal(world):
    import time
    from concurrent.futures import ThreadPoolExecutor
    from conftest import login
    from sqlalchemy import select
    from app.db import User
    c,factory,_=world
    admin=login(c,'admin');member=login(c,'1001')
    with factory() as db:
        uid=db.scalar(select(User.id).where(User.employee_number=='1001'))
    with ThreadPoolExecutor(max_workers=1) as executor:
        watching=executor.submit(c.post,'/api/auth/watch',headers=member)
        time.sleep(.15)
        started=time.monotonic()
        assert c.post('/api/admin/accounts/'+uid+'/status',headers=admin,json={'status':'dismissed','reason':'Увольнение'}).status_code==200
        response=watching.result(timeout=3)
        assert response.status_code==200 and response.json()=={'active':False}
        assert time.monotonic()-started<3
    assert c.get('/api/auth/me',headers=member).status_code==401
