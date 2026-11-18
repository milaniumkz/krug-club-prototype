import hashlib
import os
import secrets
from datetime import timedelta

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import Depends, HTTPException, Request
from sqlalchemy import delete, select

from .db import Organization, Partner, Session, User, get_db, now

ph = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
COOKIE = 'qm_session'
PRODUCTION = os.getenv('APP_ENV') == 'production'
SESSION_DAYS = 30
DUMMY_HASH = ph.hash(secrets.token_urlsafe(24))


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def hash_password(value):
    return ph.hash(value)


def verify_password(hashed, raw):
    try:
        return ph.verify(hashed, raw)
    except (VerificationError, ValueError):
        return False


def new_password():
    return secrets.token_urlsafe(15)


def user_json(user):
    return dict(id=user.id, name=user.name, role=user.role, status=user.status,
                employee_number=user.employee_number, phone=user.phone,
                organization_id=user.organization_id, partner_id=user.partner_id,
                must_change_password=user.must_change_password,
                member_until=(user.member_until.isoformat()+'Z') if user.member_until else None)


def issue_session(db, user, response):
    db.execute(delete(Session).where(Session.expires_at < now()))
    sessions = db.scalars(select(Session).where(Session.user_id == user.id)
                          .order_by(Session.created_at.desc())).all()
    for session in sessions[4:]:
        db.delete(session)
    token = secrets.token_urlsafe(48)
    db.add(Session(id=digest(token), user_id=user.id,
                   expires_at=now() + timedelta(days=SESSION_DAYS)))
    response.set_cookie(COOKIE, token, httponly=True, secure=PRODUCTION,
                        samesite='strict', max_age=SESSION_DAYS * 86400, path='/')
    response.headers['Cache-Control'] = 'no-store'
    return token


def current_user(request: Request, db=Depends(get_db)):
    auth = request.headers.get('authorization', '')
    token = auth[7:] if auth.startswith('Bearer ') else request.cookies.get(COOKIE, '')
    row = db.execute(select(Session, User, Organization.active, Partner.active)
        .join(User, Session.user_id == User.id)
        .outerjoin(Organization, User.organization_id == Organization.id)
        .outerjoin(Partner, User.partner_id == Partner.id)
        .where(Session.id == digest(token))).first() if token else None
    if not row or row[0].expires_at <= now():
        raise HTTPException(401, 'Войдите в систему')
    _, user, organization_active, partner_active = row
    if user.status != 'active':
        raise HTTPException(403, 'Доступ приостановлен. Обратитесь в профсоюз')
    if user.organization_id and not organization_active:
        raise HTTPException(403, 'Организация отключена')
    if user.partner_id and not partner_active:
        raise HTTPException(403, 'Доступ партнёра приостановлен')
    request.state.user_id = user.id
    return user


def ready_user(user=Depends(current_user)):
    if user.must_change_password:
        raise HTTPException(428, 'Установите собственный пароль')
    return user


def admin(user=Depends(ready_user)):
    if user.role != 'admin':
        raise HTTPException(403, 'Нужны права администратора')
    return user


def manager(user=Depends(ready_user)):
    if user.role not in ('admin', 'partner'):
        raise HTTPException(403, 'Нужны права управления')
    return user


def member(user=Depends(ready_user)):
    if user.role != 'member':
        raise HTTPException(403, 'Раздел для членов профсоюза')
    if user.member_until and user.member_until < now():
        raise HTTPException(403, 'Срок членства истёк. Обратитесь в профсоюз')
    return user
