import os
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app.db import Base, Organization, Partner, User, get_db, make_engine
from app.main import app
from app.security import hash_password

TEMP = 'Temporary!2027'
PERSONAL = 'PersonalPassword!2027'


@pytest.fixture()
def world(tmp_path, monkeypatch):
    import app.main as main
    url=os.getenv('TEST_DATABASE_URL','sqlite:///' + str(tmp_path / 'test.db'))
    engine = make_engine(url)
    if url.startswith('postgresql'):
        assert 'qazaqmetal_test' in url
        Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    factory = sessionmaker(engine, expire_on_commit=False)
    monkeypatch.setattr(main, 'UPLOADS', tmp_path)
    with factory() as db:
        org = Organization(code='ORG', name='Тестовая организация')
        p1, p2 = Partner(name='Тестовый партнёр А'), Partner(name='Тестовый партнёр Б')
        db.add_all([org, p1, p2]); db.flush()
        for username, role, partner in [('admin', 'admin', None), ('owner', 'partner', p1.id), ('other', 'partner', p2.id)]:
            db.add(User(username=username, name=username, role=role, partner_id=partner,
                        password_hash=hash_password(TEMP), must_change_password=True))
        db.add(User(name='Тестовый участник', employee_number='1001', role='member',
                    organization_id=org.id, password_hash=hash_password(TEMP), must_change_password=True))
        db.commit()
        ids = dict(org=org.id, partner=p1.id, other_partner=p2.id)
    def dependency():
        with factory() as db:
            yield db
    app.dependency_overrides[get_db] = dependency
    with TestClient(app, headers={'X-QM-Client': 'web'}) as client:
        yield client, factory, ids
    app.dependency_overrides.clear()
    engine.dispose()


def login(client, identifier, change=True):
    client.cookies.clear()
    r = client.post('/api/auth/login', json={'identifier': identifier, 'password': TEMP})
    assert r.status_code == 200, r.text
    if change:
        r = client.post('/api/auth/password', json={'old_password': TEMP, 'new_password': PERSONAL})
        assert r.status_code == 200, r.text
    token = r.json()['token']
    client.cookies.clear()
    return {'Authorization': 'Bearer ' + token}
