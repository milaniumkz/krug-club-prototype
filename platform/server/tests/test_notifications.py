from sqlalchemy import select
from app.db import Notification, PushDelivery
from test_system import setup_catalog, submit, approve


def test_favorite_notifications_only_after_moderation_and_increase(world):
    c,a,p,m,venue,offer,_ = setup_catalog(world)
    def favorites_notices():
        return [n for n in c.get('/api/me/notifications',headers=m).json() if n['kind'] != 'new_venue']
    c.put('/api/me/favorites/'+venue['id'],headers=m)
    d=c.post('/api/me/push-devices',headers=m,json={'token':'qa-device-token-for-tests-only','platform':'android','language':'kk'})
    assert d.status_code==201
    new=submit(c,p,'offer',venue['id'],name='Новая акция',percent=20,terms='Условия')
    assert favorites_notices()==[]
    approve(c,a,new)
    notices=favorites_notices()
    assert len(notices)==1 and notices[0]['kind']=='new_offer'
    assert notices[0]['title_kk'] and notices[0]['body_kk']
    with world[1]() as db:
        assert len(db.scalars(select(PushDelivery)).all())==1
    revision=c.post('/api/workspace/resources/'+new['id']+'/revisions',headers=p,json={'data':{'name':'Новая акция','percent':25,'terms':'Условия'}}).json()
    assert len(favorites_notices())==1
    assert c.post('/api/admin/moderation/'+revision['id'],headers=a,json={'decision':'approve'}).status_code==200
    notices=favorites_notices();assert len(notices)==2
    assert any(n['kind']=='discount_increased' for n in notices)
    assert c.post('/api/admin/moderation/'+revision['id'],headers=a,json={'decision':'approve'}).status_code==409
    assert len(favorites_notices())==2
    c.delete('/api/me/favorites/'+venue['id'],headers=m)
    extra=submit(c,p,'offer',venue['id'],name='Без подписки',percent=30,terms='Условия');approve(c,a,extra)
    assert len(favorites_notices())==2
    assert c.post('/api/me/notifications/'+notices[0]['id']+'/read',headers=m).status_code==200
    assert all(n['kind'].startswith('moderation_') for n in c.get('/api/me/notifications',headers=p).json())


def test_category_list_matches_available_venues(world):
    c,a,p,m,venue,_,_ = setup_catalog(world)
    extra=submit(c,p,name='Сад',category='Еда и напитки');approve(c,a,extra)
    assert 'Еда и напитки' in c.get('/api/categories',headers=m).json()
    assert c.get('/api/catalog?category=Еда%20и%20напитки',headers=m).json()['total']==1
