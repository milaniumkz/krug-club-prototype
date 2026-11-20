"""Isolated store-review identities; never modify existing member accounts."""
import json
import sys
import uuid
sys.path.insert(0, '/app')
from sqlalchemy import select
from app.db import Audit, Organization, Partner, Resource, SessionLocal, User
from app.schemas import ResourceData
from app.security import hash_password, verify_password

credentials = json.load(sys.stdin)
def identifier(label):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'qmet-store-review-2026/' + label))

with SessionLocal() as db:
    org = db.get(Organization, identifier('org'))
    if org is None:
        org = Organization(id=identifier('org'), code='STORE_REVIEW', name='ДЕМО · Проверка приложения магазинами')
        db.add(org)
    partner = db.get(Partner, identifier('partner'))
    if partner is None:
        partner = Partner(id=identifier('partner'), name='ДЕМО · Партнёр для проверки магазинами')
        db.add(partner)
    db.flush()
    for role in ('member', 'partner'):
        user = db.get(User, identifier(role + '-user'))
        password = credentials[role]['password']
        if user is None:
            user = User(id=identifier(role + '-user'), name='ДЕМО · Проверка ' + role,
                        role=role, status='active', must_change_password=False,
                        password_hash=hash_password(password),
                        employee_number=credentials[role]['identifier'] if role == 'member' else None,
                        username=credentials[role]['identifier'] if role == 'partner' else None,
                        organization_id=org.id if role == 'member' else None,
                        partner_id=partner.id if role == 'partner' else None)
            db.add(user)
        elif not verify_password(user.password_hash, password):
            raise SystemExit('Existing review credentials differ; no passwords were reset')
    db.flush()
    venue = db.get(Resource, identifier('venue'))
    if venue is None:
        payload = ResourceData(name='ДЕМО · Заведение для проверки', name_kk='ДЕМО · Тексеруге арналған мекеме',
                               category='Другое', description='Демонстрационная карточка для проверки приложения. Не является реальным предложением.',
                               organization_ids=[org.id]).model_dump(mode='json')
        venue = Resource(id=identifier('venue'), kind='venue', partner_id=partner.id,
                         published=payload, version=1)
        db.add(venue)
        db.flush()
        offer = ResourceData(name='ДЕМО · Условия привилегии', percent=10,
                              terms='Только демонстрация для проверки приложения. Реальная скидка не предоставляется.',
                              organization_ids=[org.id]).model_dump(mode='json')
        db.add(Resource(id=identifier('offer'), kind='offer', partner_id=partner.id,
                        venue_id=venue.id, published=offer, version=1))
        db.add(Audit(actor_id=None, action='store_review_setup', target=org.id,
                     detail={'isolated_demo_organization': True, 'real_accounts_modified': False}))
    db.commit()
print('Isolated store-review accounts ready; existing accounts preserved.')
