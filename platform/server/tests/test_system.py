import io
import uuid
from datetime import timedelta

from PIL import Image
from sqlalchemy import select

from app.db import Resource, User, Visit, now
from conftest import PERSONAL, TEMP, login


def submit(client, headers, kind='venue', venue_id=None, partner_id=None, **data):
    payload = {'name': 'Заведение', 'category': 'Ресторан', 'address': 'Адрес 1', **data}
    r = client.post('/api/workspace/resources', headers=headers,
                    json={'kind': kind, 'venue_id': venue_id, 'partner_id': partner_id, 'data': payload})
    assert r.status_code == 201, r.text
    return r.json()


def approve(client, admin, row):
    r = client.post('/api/admin/moderation/' + row['revision']['id'], headers=admin,
                    json={'decision': 'approve'})
    assert r.status_code == 200, r.text


def setup_catalog(world):
    c, db, ids = world
    a, p, m = login(c, 'admin'), login(c, 'owner'), login(c, '1001')
    venue = submit(c, p, latitude=52.28, longitude=76.96)
    approve(c, a, venue)
    offer = submit(c, p, 'offer', venue['id'], percent=15, terms='На меню')
    approve(c, a, offer)
    qr = c.post(f'/api/workspace/resources/{venue["id"]}/qr', headers=p).json()['code']
    return c, a, p, m, venue, offer, qr


def test_temporary_password_gate_persistent_session_and_revocation(world):
    c, _, _ = world
    temp = login(c, '1001', change=False)
    assert c.get('/api/auth/me', headers=temp).json()['must_change_password']
    assert c.get('/api/catalog', headers=temp).status_code == 428
    r = c.post('/api/auth/password', headers=temp, json={'old_password': TEMP, 'new_password': PERSONAL})
    assert r.status_code == 200
    h = {'Authorization': 'Bearer ' + r.json()['token']}
    c.cookies.clear()
    assert c.get('/api/auth/me', headers=h).status_code == 200
    assert c.get('/api/auth/me', headers=temp).status_code == 401
    assert c.post('/api/auth/logout', headers=h).status_code == 200
    assert c.get('/api/auth/me', headers=h).status_code == 401


def test_member_cannot_manage_and_partner_is_isolated(world):
    c, _, _ = world
    m, p, other = login(c, '1001'), login(c, 'owner'), login(c, 'other')
    assert c.get('/api/admin/accounts', headers=p).status_code == 403
    assert c.get('/api/workspace/resources', headers=m).status_code == 403
    row = submit(c, p)
    assert c.get('/api/workspace/resources', headers=other).json() == []
    assert c.post(f'/api/workspace/resources/{row["id"]}/revisions', headers=other,
                  json={'data': {'name': 'Чужое'}}).status_code == 404


def test_moderation_reject_then_approve_and_keep_live_version(world):
    c, a, p, m, venue, _, _ = setup_catalog(world)
    body = {'data': {**venue['revision']['data'], 'name': 'Новое имя'}}
    r = c.post(f'/api/workspace/resources/{venue["id"]}/revisions', headers=p, json=body)
    rev = r.json()['id']
    assert c.get('/api/catalog', headers=m).json()['items'][0]['data']['name'] == 'Заведение'
    assert c.post('/api/admin/moderation/'+rev, headers=p, json={'decision': 'approve'}).status_code == 403
    assert c.post('/api/admin/moderation/'+rev, headers=a, json={'decision': 'reject'}).status_code == 422
    assert c.post('/api/admin/moderation/'+rev, headers=a,
                  json={'decision': 'reject', 'reason': 'Нужно уточнить'}).status_code == 200
    r = c.post(f'/api/workspace/resources/{venue["id"]}/revisions', headers=p, json=body)
    rev = r.json()['id']
    assert c.post('/api/admin/moderation/'+rev, headers=a, json={'decision': 'approve'}).status_code == 200
    assert c.post('/api/admin/moderation/'+rev, headers=a, json={'decision': 'approve'}).status_code == 409
    assert c.get('/api/catalog', headers=m).json()['items'][0]['data']['name'] == 'Новое имя'


def test_qr_auto_detection_idempotency_cooldown_stats_and_rotation(world):
    c, a, p, m, venue, _, qr = setup_catalog(world)
    body = {'code': qr, 'request_id': str(uuid.uuid4())}
    r = c.post('/api/scan', headers=m, json=body)
    assert r.status_code == 200 and r.json()['percent'] == 15
    assert c.post('/api/scan', headers=m, json=body).json()['replay']
    body['request_id'] = str(uuid.uuid4())
    assert c.post('/api/scan', headers=m, json=body).json()['replay']
    assert len(c.get('/api/me/history', headers=m).json()) == 1
    stats = c.get('/api/workspace/stats', headers=p).json()
    assert stats['total_uses'] == 1
    assert 'user_id' not in stats['operations'][0]
    assert c.get('/api/workspace/stats', headers=login(c, 'other')).json()['total_uses'] == 0
    c.post(f'/api/workspace/resources/{venue["id"]}/qr', headers=p)
    body['request_id'] = str(uuid.uuid4())
    assert c.post('/api/scan', headers=m, json=body).status_code == 404
    assert c.post('/api/scan', headers=m, json={'code': 'https://example.com', 'request_id': str(uuid.uuid4())}).status_code == 400


def test_deleted_venue_hides_offers_and_qr(world):
    c, a, p, m, venue, _, qr = setup_catalog(world)
    r = c.post(f'/api/workspace/resources/{venue["id"]}/revisions', headers=p,
               json={'action': 'delete', 'data': venue['revision']['data']})
    assert r.status_code == 201
    assert c.get('/api/catalog', headers=m).json()['total'] == 1
    c.post('/api/admin/moderation/'+r.json()['id'], headers=a, json={'decision': 'approve'})
    assert c.get('/api/catalog', headers=m).json()['total'] == 0
    assert c.post('/api/scan', headers=m, json={'code': qr, 'request_id': str(uuid.uuid4())}).status_code == 404


def test_block_and_dismiss_revoke_sessions(world):
    c, a, _, m, _, _, qr = setup_catalog(world)
    account = c.get('/api/auth/me', headers=m).json()['id']
    r = c.post(f'/api/admin/accounts/{account}/status', headers=a,
               json={'status': 'blocked', 'reason': 'Нарушение правил'})
    assert r.status_code == 200
    assert c.get('/api/auth/me', headers=m).status_code == 401
    c.post(f'/api/admin/accounts/{account}/status', headers=a,
           json={'status': 'dismissed', 'reason': 'Увольнение'})
    r = c.post('/api/auth/login', json={'identifier': '1001', 'password': PERSONAL})
    assert r.status_code == 401


def test_expired_membership_no_history_created(world):
    c, _, _, m, _, _, qr = setup_catalog(world)
    with world[1]() as db:
        person = db.scalar(select(User).where(User.employee_number == '1001'))
        person.member_until = now() - timedelta(days=1); db.commit()
    assert c.post('/api/scan', headers=m, json={'code': qr, 'request_id': str(uuid.uuid4())}).status_code == 403
    with world[1]() as db:
        assert db.scalars(select(Visit)).all() == []


def test_import_atomic_and_passwords_individual(world):
    c, _, ids = world
    a = login(c, 'admin')
    r = c.post('/api/admin/accounts/import', headers=a, params={'organization_id': ids['org']},
               files={'file': ('employees.csv', 'employee_number,name\n2001,Человек А\n2002,Человек Б\n'.encode())})
    assert r.status_code == 200, r.text
    creds = r.json()['credentials']
    assert len(creds) == 2 and creds[0]['temporary_password'] != creds[1]['temporary_password']
    r = c.post('/api/admin/accounts/import', headers=a, params={'organization_id': ids['org']},
               files={'file': ('bad.csv', b'employee_number,name\n3001,Name A\n3001,Name B\n')})
    assert r.status_code == 422
    assert c.get('/api/admin/accounts?q=3001', headers=a).json()['total'] == 0


def test_media_validation_banner_moderation_and_favorites(world):
    c, a, p, m, venue, _, _ = setup_catalog(world)
    assert c.post('/api/media', headers=p, files={'file': ('bad.svg', b'<svg/>')}).status_code == 422
    image = Image.new('RGB', (80, 40)); stream = io.BytesIO(); image.save(stream, 'PNG')
    r = c.post('/api/media', headers=p, files={'file': ('image.png', stream.getvalue())})
    assert r.status_code == 201
    path = r.json()['path']
    assert c.get(path, headers=m).headers['content-type'] == 'image/webp'
    banner = submit(c, p, 'banner', venue['id'], image=path)
    assert c.get('/api/banners', headers=m).json() == []
    approve(c, a, banner)
    assert len(c.get('/api/banners', headers=m).json()) == 1
    assert c.put('/api/me/favorites/'+venue['id'], headers=m).status_code == 200
    assert c.get('/api/me/favorites', headers=m).json() == [venue['id']]
    c.delete('/api/me/favorites/'+venue['id'], headers=m)
    assert c.get('/api/me/favorites', headers=m).json() == []


def test_geo_filter_and_search(world):
    c, _, _, m, _, _, _ = setup_catalog(world)
    result = c.get('/api/catalog?latitude=52.28&longitude=76.96', headers=m).json()
    assert result['items'][0]['distance_km'] == 0
    assert c.get('/api/catalog?west=1&south=1&east=2&north=2', headers=m).json()['total'] == 0
    assert c.get('/api/catalog?q=absent', headers=m).json()['total'] == 0


def test_csrf_rate_limit_and_password_not_exposed(world):
    c, _, _ = world
    assert c.post('/api/auth/login', headers={'Origin': 'https://evil.invalid'},
                  json={'identifier': 'admin', 'password': TEMP}).status_code == 403
    for _ in range(8):
        assert c.post('/api/auth/login', json={'identifier': 'admin', 'password': 'wrong'}).status_code == 401
    assert c.post('/api/auth/login', json={'identifier': 'admin', 'password': TEMP}).status_code == 429


def test_ticket_reply_persists(world):
    c, _, _ = world
    m, a = login(c, '1001'), login(c, 'admin')
    r = c.post('/api/tickets', headers=m, json={'subject': 'Вопрос', 'message': 'Как получить скидку?'})
    tid = r.json()['id']
    assert c.post('/api/admin/tickets/'+tid, headers=a,
                  json={'status': 'closed', 'reply': 'Откройте QR в нижнем меню'}).status_code == 200
    assert c.get('/api/tickets', headers=m).json()[0]['reply'] == 'Откройте QR в нижнем меню'


def test_pending_content_cannot_bypass_ownership_or_validation(world):
    c, _, ids = world
    p = login(c, 'owner')
    venue = submit(c, p, partner_id=ids['other_partner'])
    assert venue['partner_id'] == ids['partner']
    assert c.post('/api/workspace/resources', headers=p, json={
        'kind': 'offer', 'venue_id': venue['id'],
        'data': {'name': 'Invalid', 'percent': 101, 'terms': 'Terms'}}).status_code == 422
    assert c.post('/api/workspace/resources', headers=p, json={
        'kind': 'venue', 'data': {'name': 'Invalid', 'category': 'Shop', 'address': 'Street',
                                 'latitude': 120, 'longitude': 50}}).status_code == 422


def test_expired_offer_and_org_restriction_do_not_apply(world):
    c, _, _, m, venue, offer, qr = setup_catalog(world)
    with world[1]() as db:
        resource = db.get(Resource, offer['id'])
        resource.published = {**resource.published, 'ends_on': '2000-01-01'}
        db.commit()
    assert c.post('/api/scan', headers=m, json={'code': qr, 'request_id': str(uuid.uuid4())}).status_code == 409
    with world[1]() as db:
        resource = db.get(Resource, offer['id'])
        resource.published = {**resource.published, 'ends_on': None, 'organization_ids': ['other-organization']}
        db.commit()
    assert c.post('/api/scan', headers=m, json={'code': qr, 'request_id': str(uuid.uuid4())}).status_code == 409


def test_validation_never_echoes_password(world):
    c, _, _ = world
    h = login(c, '1001', change=False)
    secret = 'do-not-echo-this'
    r = c.post('/api/auth/password', headers=h, json={'old_password': secret, 'new_password': 'x7Q'})
    assert r.status_code == 422
    assert secret not in r.text and 'x7Q' not in r.text


def test_session_expiration(world):
    from app.db import Session
    c, factory, _ = world
    h = login(c, '1001')
    with factory() as db:
        for session in db.scalars(select(Session)).all():
            session.expires_at = now() - timedelta(seconds=1)
        db.commit()
    assert c.get('/api/auth/me', headers=h).status_code == 401


def test_concurrent_qr_only_one_visit_on_postgres(world):
    import pytest
    from concurrent.futures import ThreadPoolExecutor
    c, factory, _ = world
    with factory() as db:
        if db.bind.dialect.name != 'postgresql':
            pytest.skip('PostgreSQL row-lock integration test')
    c, _, _, m, _, _, qr = setup_catalog(world)
    def use(_):
        return c.post('/api/scan', headers=m, json={'code': qr, 'request_id': str(uuid.uuid4())})
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(use, range(4)))
    assert all(r.status_code == 200 for r in responses)
    assert len({r.json()['id'] for r in responses}) == 1
    assert len(c.get('/api/me/history', headers=m).json()) == 1
