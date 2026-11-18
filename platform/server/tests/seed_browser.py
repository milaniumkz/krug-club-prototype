"""Seed isolated synthetic browser QA only. Run after alembic upgrade head."""
import json
import os
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sqlalchemy import select
from app.db import Organization, Partner, Resource, SessionLocal, User
from app.schemas import ResourceData
from app.security import hash_password

if os.getenv('APP_ENV') == 'production' or 'preview' not in os.getenv('DATABASE_URL', ''):
    raise SystemExit('Use only an isolated DATABASE_URL containing preview, never production')
output = Path(sys.argv[1]).resolve()
if output.exists():
    raise SystemExit('Refusing to overwrite credentials')
credentials = {}
with SessionLocal() as db:
    if db.scalar(select(User.id).limit(1)):
        raise SystemExit('Use an empty preview database')
    org = Organization(code='QA', name='QA — тестовая организация')
    partner = Partner(name='QA — тестовый партнёр')
    db.add_all([org, partner]); db.flush()
    for role, identifier in [('admin', 'qa-admin'), ('partner', 'qa-owner'), ('member', 'QA-1001')]:
        password = secrets.token_urlsafe(18)
        credentials[role] = dict(identifier=identifier, password=password)
        db.add(User(username=identifier if role != 'member' else None,
                    employee_number=identifier if role == 'member' else None,
                    name='QA — '+role, role=role,
                    organization_id=org.id if role == 'member' else None,
                    partner_id=partner.id if role == 'partner' else None,
                    password_hash=hash_password(password), must_change_password=role == 'member'))
    venue = Resource(kind='venue', partner_id=partner.id, version=1, latitude=52.287, longitude=76.967,
                     published=ResourceData(name='QA — ресторан', category='Рестораны', address='QA — адрес',
                                            latitude=52.287, longitude=76.967).model_dump(mode='json'))
    db.add(venue); db.flush()
    db.add(Resource(kind='offer', partner_id=partner.id, venue_id=venue.id, version=1,
                    published=ResourceData(name='QA — скидка', percent=15, terms='Тестовые условия').model_dump(mode='json')))
    db.commit()
output.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(credentials, f)
print('Synthetic QA data created; private credentials file written')
