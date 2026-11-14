import csv
import io
import math
import os
import re
import secrets
import uuid
from urllib.parse import urlsplit
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

from fastapi import Depends, FastAPI, File, HTTPException, Query, Request, Response, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError
from sqlalchemy import delete, func, or_, select, text
from sqlalchemy.exc import IntegrityError

from . import schemas as S
from .db import (Audit, Favorite, LoginAttempt, Organization, Partner, Resource,
                 Revision, Session, Ticket, User, Visit, get_db, now)
from .security import (COOKIE, DUMMY_HASH, PRODUCTION, admin, current_user, digest,
                       hash_password, issue_session, manager, member, new_password,
                       ready_user, user_json, verify_password)

app = FastAPI(title='QAZAQMETAL KÁSIPODAǴY API', version='1.0.0',
              docs_url=None if PRODUCTION else '/api/docs', redoc_url=None,
              openapi_url='/api/openapi.json')
if PRODUCTION and (not os.getenv('DATABASE_URL', '').startswith('postgresql') or not os.getenv('PUBLIC_ORIGIN', '').startswith('https://')):
    raise RuntimeError('Production requires PostgreSQL DATABASE_URL and HTTPS PUBLIC_ORIGIN')
UPLOADS = Path(os.getenv('UPLOAD_DIR', './uploads')).resolve()
UPLOADS.mkdir(parents=True, exist_ok=True)
WEB = Path(os.getenv('WEB_DIR', str(Path(__file__).resolve().parents[2] / 'web')))
ORIGIN = os.getenv('PUBLIC_ORIGIN', 'http://localhost:8000').rstrip('/')
TILE_URL = os.getenv('MAP_TILE_URL') or 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png'
TILE_ORIGIN = urlsplit(TILE_URL).scheme + '://' + urlsplit(TILE_URL).netloc.replace('{s}', '*')
if PRODUCTION and not TILE_URL.startswith('https://'):
    raise RuntimeError('Production map tiles must use HTTPS')
Image.MAX_IMAGE_PIXELS = 20_000_000


@app.middleware('http')
async def protection(request, call_next):
    if request.method not in ('GET', 'HEAD', 'OPTIONS'):
        origin = request.headers.get('origin')
        if origin and origin != ORIGIN:
            return JSONResponse({'detail': 'Недопустимый источник запроса'}, status_code=403)
        if request.cookies.get(COOKIE) and request.headers.get('x-qm-client') != 'web':
            return JSONResponse({'detail': 'Недопустимый запрос'}, status_code=403)
        length = request.headers.get('content-length')
        if length and (not length.isdigit() or int(length) > 9 * 1024 * 1024):
            return JSONResponse({'detail': 'Файл слишком большой'}, status_code=413)
    response = await call_next(request)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'same-origin'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['Permissions-Policy'] = 'camera=(self), geolocation=(self), microphone=()'
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self' blob:; style-src 'self' 'unsafe-inline'; "
        f"img-src 'self' data: blob: {TILE_ORIGIN} https://tile.openstreetmap.org https://*.tile.openstreetmap.org https://*.tile.openstreetmap.fr; "
        f"connect-src 'self' {TILE_ORIGIN} https://tile.openstreetmap.org https://*.tile.openstreetmap.org https://*.tile.openstreetmap.fr; "
        f"font-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'self'; "
        f"media-src 'self' blob:; "
    )
    if request.url.path.startswith('/api/'):
        response.headers['Cache-Control'] = 'no-store'
    if PRODUCTION:
        response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    return response


@app.exception_handler(RequestValidationError)
async def validation_error(_request, exc):
    # Never echo passwords, tokens or the submitted CSV/JSON back in error payloads.
    return JSONResponse(status_code=422, content={'detail': 'Проверьте заполнение полей',
        'fields': [{'field': '.'.join(map(str, e['loc'])), 'type': e['type']} for e in exc.errors()]})


@app.exception_handler(IntegrityError)
async def integrity_error(_request, _exc):
    return JSONResponse(status_code=409, content={'detail': 'Такие данные уже существуют. Обновите страницу'})


def audit(db, user, action, target, **details):
    db.add(Audit(actor_id=user.id if user else None, action=action,
                 target=str(target), detail=details))


def require(row, message='Объект не найден'):
    if row is None:
        raise HTTPException(404, message)
    return row


def scope(user, resource):
    if user.role != 'admin' and resource.partner_id != user.partner_id:
        raise HTTPException(404, 'Объект не найден')


def active_data(payload, organization_id=None):
    if not payload:
        return False
    today = datetime.now(timezone(timedelta(hours=5))).date().isoformat()
    if payload.get('starts_on') and payload['starts_on'] > today:
        return False
    if payload.get('ends_on') and payload['ends_on'] < today:
        return False
    return not payload.get('organization_ids') or organization_id in payload['organization_ids']


def resource_json(r, revision=None):
    result = dict(id=r.id, kind=r.kind, partner_id=r.partner_id, venue_id=r.venue_id,
                  data=r.published, version=r.version, enabled=r.enabled, deleted=r.deleted)
    if revision:
        result['revision'] = revision_json(revision)
    return result


def revision_json(r):
    return dict(id=r.id, resource_id=r.resource_id, author_id=r.author_id, data=r.payload,
                action=r.action, base_version=r.base_version, status=r.status,
                reason=r.reason, created_at=r.created_at.isoformat()+'Z', reviewed_at=(r.reviewed_at.isoformat()+'Z') if r.reviewed_at else None)


def visit_json(v, private=False):
    data = dict(id=v.id, venue_id=v.venue_id, offer_id=v.offer_id,
                venue_name=v.venue_name, offer_name=v.offer_name, percent=v.percent,
                created_at=v.created_at.isoformat()+'Z')
    if private:
        data.update(user_id=v.user_id, organization_id=v.organization_id)
    return data


def public_venues(db, user):
    rows = db.scalars(select(Resource).join(Partner, Partner.id == Resource.partner_id)
                      .where(Resource.kind == 'venue', Resource.published.is_not(None),
                             Resource.enabled.is_(True), Resource.deleted.is_(False),
                             Partner.active.is_(True))).all()
    return [r for r in rows if active_data(r.published, user.organization_id)]


def offers_for(db, user, venue_id):
    return [r for r in db.scalars(select(Resource).where(
        Resource.kind == 'offer', Resource.venue_id == venue_id,
        Resource.enabled.is_(True), Resource.deleted.is_(False),
        Resource.published.is_not(None))).all() if active_data(r.published, user.organization_id)]


@app.get('/api/health')
def health(db=Depends(get_db)):
    db.execute(text('SELECT 1'))
    return {'status': 'ok'}


@app.get('/api/meta')
def meta():
    return {'brand': 'QAZAQMETAL KÁSIPODAǴY', 'session_days': 30,
            'tiles': TILE_URL,
            'attribution': (os.getenv('MAP_ATTRIBUTION') or '© OpenStreetMap contributors · Tiles OSM France'), 'default_center': [52.287, 76.967]}


@app.post('/api/auth/login')
def login(body: S.Login, request: Request, response: Response, db=Depends(get_db)):
    ip = request.client.host if request.client else 'unknown'
    keys = [digest('login:' + ip + ':' + body.identifier.casefold()), digest('ip:' + ip)]
    db.execute(delete(LoginAttempt).where(LoginAttempt.created_at < now() - timedelta(days=1)))
    for key, threshold in zip(keys, (8, 80)):
        count = db.scalar(select(func.count()).select_from(LoginAttempt).where(
            LoginAttempt.key == key, LoginAttempt.created_at > now() - timedelta(minutes=15)))
        if count >= threshold:
            raise HTTPException(429, 'Слишком много попыток. Повторите через 15 минут', headers={'Retry-After': '900'})
    query = select(User).where(or_(User.username == body.identifier.casefold(),
                                  User.employee_number == body.identifier,
                                  User.phone == body.identifier))
    if body.organization_code:
        org = db.scalar(select(Organization).where(Organization.code == body.organization_code))
        query = query.where(User.organization_id == (org.id if org else 'unknown'))
    users = db.scalars(query).all()
    user = users[0] if len(users) == 1 else None
    correct = verify_password(user.password_hash if user else DUMMY_HASH, body.password)
    if not user or not correct or user.status != 'active':
        for key in keys:
            db.add(LoginAttempt(key=key))
        db.commit()
        raise HTTPException(401, 'Неверные данные входа или доступ закрыт. При необходимости укажите код организации')
    if user.organization_id and not db.get(Organization, user.organization_id).active:
        raise HTTPException(403, 'Организация отключена')
    if user.partner_id and not db.get(Partner, user.partner_id).active:
        raise HTTPException(403, 'Доступ партнёра приостановлен')
    db.execute(delete(LoginAttempt).where(LoginAttempt.key == keys[0]))
    token = issue_session(db, user, response)
    audit(db, user, 'login', user.id)
    db.commit()
    return dict(user=user_json(user), token=token)


@app.get('/api/auth/me')
def me(user=Depends(current_user), db=Depends(get_db)):
    result = user_json(user)
    result['organization_name'] = db.get(Organization, user.organization_id).name if user.organization_id else None
    result['partner_name'] = db.get(Partner, user.partner_id).name if user.partner_id else None
    return result


@app.post('/api/auth/password')
def change_password(body: S.Password, response: Response, user=Depends(current_user), db=Depends(get_db)):
    if not verify_password(user.password_hash, body.old_password):
        raise HTTPException(400, 'Неверный текущий пароль')
    if body.old_password == body.new_password:
        raise HTTPException(400, 'Новый пароль должен отличаться от временного')
    user.password_hash = hash_password(body.new_password)
    user.must_change_password = False
    db.execute(delete(Session).where(Session.user_id == user.id))
    token = issue_session(db, user, response)
    audit(db, user, 'password_changed', user.id)
    db.commit()
    return dict(user=user_json(user), token=token)


@app.post('/api/auth/logout')
def logout(response: Response, user=Depends(current_user), db=Depends(get_db)):
    db.execute(delete(Session).where(Session.user_id == user.id))
    response.delete_cookie(COOKIE, path='/')
    db.commit()
    return {'ok': True}


@app.get('/api/auth/sessions')
def sessions(user=Depends(ready_user), db=Depends(get_db)):
    return [dict(id=s.id, created_at=s.created_at.isoformat()+'Z', expires_at=s.expires_at.isoformat()+'Z')
            for s in db.scalars(select(Session).where(Session.user_id == user.id,
                                                      Session.expires_at > now())).all()]


@app.delete('/api/auth/sessions/{session_id}')
def revoke_session(session_id: str, user=Depends(ready_user), db=Depends(get_db)):
    db.execute(delete(Session).where(Session.user_id == user.id, Session.id == session_id))
    db.commit()
    return {'ok': True}


@app.get('/api/catalog')
def catalog(q: str = '', category: str = '', latitude: float | None = Query(None, ge=-90, le=90),
            longitude: float | None = Query(None, ge=-180, le=180),
            west: float | None = Query(None, ge=-180, le=180),
            south: float | None = Query(None, ge=-90, le=90),
            east: float | None = Query(None, ge=-180, le=180),
            north: float | None = Query(None, ge=-90, le=90),
            limit: int = Query(50, ge=1, le=500), offset: int = Query(0, ge=0),
            user=Depends(member), db=Depends(get_db)):
    rows = public_venues(db, user)
    results = []
    for r in rows:
        d = r.published
        if q.casefold() not in f'{d["name"]} {d.get("description", "")} {d.get("address", "")}'.casefold():
            continue
        if category and category != d.get('category'):
            continue
        if all(v is not None for v in (west, south, east, north)):
            if r.latitude is None or not (south <= r.latitude <= north and west <= r.longitude <= east):
                continue
        result = resource_json(r)
        result['offers'] = [resource_json(o) for o in offers_for(db, user, r.id)]
        result['distance_km'] = None
        if latitude is not None and longitude is not None and r.latitude is not None:
            lat1, lat2 = math.radians(latitude), math.radians(r.latitude)
            a = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(math.radians(r.longitude-longitude)/2)**2
            result['distance_km'] = round(6371 * 2 * math.asin(min(1, math.sqrt(a))), 2)
        results.append(result)
    results.sort(key=lambda r: (r['distance_km'] if r['distance_km'] is not None else float('inf'), r['data']['name']))
    return {'items': results[offset:offset+limit], 'total': len(results)}


@app.get('/api/catalog/{resource_id}')
def catalog_detail(resource_id: str, user=Depends(member), db=Depends(get_db)):
    r = next((r for r in public_venues(db, user) if r.id == resource_id), None)
    require(r)
    return dict(**resource_json(r), offers=[resource_json(o) for o in offers_for(db, user, r.id)])


@app.get('/api/banners')
def banners(user=Depends(member), db=Depends(get_db)):
    venues = {r.id for r in public_venues(db, user)}
    return [resource_json(r) for r in db.scalars(select(Resource).where(
        Resource.kind == 'banner', Resource.enabled.is_(True), Resource.deleted.is_(False),
        Resource.published.is_not(None))).all()
        if r.venue_id in venues and active_data(r.published, user.organization_id)]


@app.get('/api/me/favorites')
def favorites(user=Depends(member), db=Depends(get_db)):
    return list(db.scalars(select(Favorite.venue_id).where(Favorite.user_id == user.id)).all())


@app.put('/api/me/favorites/{venue_id}')
def add_favorite(venue_id: str, user=Depends(member), db=Depends(get_db)):
    if not any(r.id == venue_id for r in public_venues(db, user)):
        raise HTTPException(404, 'Заведение недоступно')
    if not db.get(Favorite, (user.id, venue_id)):
        db.add(Favorite(user_id=user.id, venue_id=venue_id))
    db.commit()
    return {'ok': True}


@app.delete('/api/me/favorites/{venue_id}')
def remove_favorite(venue_id: str, user=Depends(member), db=Depends(get_db)):
    db.execute(delete(Favorite).where(Favorite.user_id == user.id, Favorite.venue_id == venue_id))
    db.commit()
    return {'ok': True}


@app.get('/api/me/history')
def history(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0),
            user=Depends(ready_user), db=Depends(get_db)):
    return [visit_json(v) for v in db.scalars(select(Visit).where(Visit.user_id == user.id)
                                            .order_by(Visit.created_at.desc()).offset(offset).limit(limit)).all()]


@app.post('/api/scan')
def scan(body: S.ScanIn, user=Depends(member), db=Depends(get_db)):
    # Serialize scans and employment changes per member; PostgreSQL supplies row locks.
    user = db.scalar(select(User).where(User.id == user.id).with_for_update().execution_options(populate_existing=True))
    if user.status != 'active' or (user.member_until and user.member_until < now()):
        raise HTTPException(403, 'Членство недоступно')
    previous = db.scalar(select(Visit).where(Visit.user_id == user.id, Visit.request_id == body.request_id))
    if previous:
        return dict(**visit_json(previous), replay=True)
    match = re.fullmatch(r'QAZAQMETAL:1:([a-f0-9-]{36}):([A-Za-z0-9_-]{32,64})', body.code)
    if not match:
        raise HTTPException(400, 'Это не QR-код заведения QAZAQMETAL. Ссылки не открываются')
    venue = db.scalar(select(Resource).where(Resource.id == match[1]).with_for_update())
    if not venue or venue.kind != 'venue' or not venue.qr_hash or not secrets.compare_digest(venue.qr_hash, digest(match[2])):
        raise HTTPException(404, 'QR-код неизвестен или заменён. Попросите актуальный код')
    if venue.id not in {v.id for v in public_venues(db, user)}:
        raise HTTPException(409, 'Заведение временно недоступно')
    offers = offers_for(db, user, venue.id)
    if not offers:
        raise HTTPException(409, 'Сейчас нет доступной скидки для вашей организации')
    offer = max(offers, key=lambda o: o.published['percent'])
    last = db.scalar(select(Visit).where(Visit.user_id == user.id, Visit.venue_id == venue.id,
                                        Visit.created_at > now() - timedelta(seconds=60))
                     .order_by(Visit.created_at.desc()).limit(1))
    if last:
        return dict(**visit_json(last), replay=True)
    visit = Visit(request_id=body.request_id, user_id=user.id, organization_id=user.organization_id,
                  partner_id=venue.partner_id, venue_id=venue.id, offer_id=offer.id,
                  venue_name=venue.published['name'], offer_name=offer.published['name'],
                  percent=offer.published['percent'])
    db.add(visit)
    db.flush()
    audit(db, user, 'privilege_used', visit.id, venue_id=venue.id)
    db.commit()
    return dict(**visit_json(visit), replay=False)


@app.get('/api/workspace/resources')
def workspace_resources(kind: str = '', user=Depends(manager), db=Depends(get_db)):
    query = select(Resource).order_by(Resource.created_at.desc())
    if user.role == 'partner':
        query = query.where(Resource.partner_id == user.partner_id)
    if kind:
        query = query.where(Resource.kind == kind)
    rows = db.scalars(query).all()
    result = []
    for r in rows:
        latest = db.scalar(select(Revision).where(Revision.resource_id == r.id)
                           .order_by(Revision.created_at.desc()).limit(1))
        result.append(resource_json(r, latest))
    return result


def validate_payload(db, resource, payload):
    if resource.kind == 'venue':
        if not payload['address'] or not payload['category']:
            raise HTTPException(422, 'Для заведения нужны адрес и категория')
    else:
        venue = require(db.get(Resource, resource.venue_id), 'Выберите заведение')
        if venue.kind != 'venue' or venue.partner_id != resource.partner_id:
            raise HTTPException(422, 'Неверное заведение')
        if resource.kind == 'offer' and (not payload['percent'] or not payload['terms']):
            raise HTTPException(422, 'Для скидки нужны процент и условия')
        if resource.kind == 'banner' and not payload['image']:
            raise HTTPException(422, 'Загрузите изображение баннера')
    for org_id in payload['organization_ids']:
        require(db.get(Organization, org_id), 'Организация не найдена')
    if payload['image'] and not (UPLOADS / Path(payload['image']).name).is_file():
        raise HTTPException(422, 'Изображение не найдено. Загрузите заново')


@app.post('/api/workspace/resources', status_code=201)
def create_resource(body: S.ResourceIn, user=Depends(manager), db=Depends(get_db)):
    partner_id = user.partner_id if user.role == 'partner' else body.partner_id
    partner = require(db.get(Partner, partner_id), 'Выберите партнёра')
    if not partner.active:
        raise HTTPException(409, 'Партнёр отключён')
    if body.kind == 'venue' and body.venue_id:
        raise HTTPException(422, 'Заведение не может относиться к другому заведению')
    resource = Resource(kind=body.kind, partner_id=partner_id, venue_id=body.venue_id)
    payload = body.data.model_dump(mode='json')
    validate_payload(db, resource, payload)
    db.add(resource)
    db.flush()
    revision = Revision(resource_id=resource.id, author_id=user.id, payload=payload, base_version=0)
    db.add(revision)
    db.flush()
    audit(db, user, 'content_submitted', resource.id, revision_id=revision.id)
    db.commit()
    return resource_json(resource, revision)


@app.post('/api/workspace/resources/{resource_id}/revisions', status_code=201)
def revise_resource(resource_id: str, body: S.RevisionIn, user=Depends(manager), db=Depends(get_db)):
    resource = require(db.scalar(select(Resource).where(Resource.id == resource_id).with_for_update()))
    scope(user, resource)
    if resource.deleted:
        raise HTTPException(409, 'Объект удалён')
    if db.scalar(select(Revision.id).where(Revision.resource_id == resource_id, Revision.status == 'pending')):
        raise HTTPException(409, 'Предыдущие изменения ещё на модерации')
    payload = body.data.model_dump(mode='json')
    if body.action == 'publish':
        validate_payload(db, resource, payload)
    revision = Revision(resource_id=resource.id, author_id=user.id, payload=payload,
                        action=body.action, base_version=resource.version)
    db.add(revision)
    db.flush()
    audit(db, user, 'content_submitted', resource.id, revision_id=revision.id, action_type=body.action)
    db.commit()
    return revision_json(revision)


@app.get('/api/admin/moderation')
def moderation(status: str = 'pending', user=Depends(admin), db=Depends(get_db)):
    return [dict(**revision_json(r), resource=resource_json(db.get(Resource, r.resource_id)))
            for r in db.scalars(select(Revision).where(Revision.status == status)
                                 .order_by(Revision.created_at)).all()]


@app.post('/api/admin/moderation/{revision_id}')
def review(revision_id: str, body: S.ReviewIn, user=Depends(admin), db=Depends(get_db)):
    rev = require(db.scalar(select(Revision).where(Revision.id == revision_id).with_for_update()))
    resource = require(db.scalar(select(Resource).where(Resource.id == rev.resource_id).with_for_update()))
    if rev.status != 'pending' or resource.version != rev.base_version:
        raise HTTPException(409, 'Изменения уже рассмотрены или версия устарела')
    if body.decision == 'reject' and not body.reason:
        raise HTTPException(422, 'Укажите причину отклонения')
    if body.decision == 'approve':
        if rev.action == 'delete':
            resource.deleted = True
            resource.qr_hash = None
        else:
            validate_payload(db, resource, rev.payload)
            if resource.venue_id:
                parent = db.get(Resource, resource.venue_id)
                if not parent.published or parent.deleted:
                    raise HTTPException(409, 'Сначала одобрите заведение')
            resource.published = rev.payload
            resource.latitude = rev.payload.get('latitude')
            resource.longitude = rev.payload.get('longitude')
        resource.version += 1
        rev.status = 'approved'
    else:
        rev.status = 'rejected'
    rev.reason = body.reason
    rev.moderator_id = user.id
    rev.reviewed_at = now()
    audit(db, user, 'moderation_' + rev.status, resource.id, revision_id=rev.id, reason=body.reason)
    db.commit()
    return revision_json(rev)


@app.post('/api/admin/resources/{resource_id}/visibility')
def visibility(resource_id: str, body: S.ToggleIn, user=Depends(admin), db=Depends(get_db)):
    resource = require(db.get(Resource, resource_id))
    resource.enabled = body.enabled
    audit(db, user, 'visibility_changed', resource_id, enabled=body.enabled, reason=body.reason)
    db.commit()
    return resource_json(resource)


@app.post('/api/workspace/resources/{resource_id}/qr')
def rotate_qr(resource_id: str, user=Depends(manager), db=Depends(get_db)):
    resource = require(db.get(Resource, resource_id))
    scope(user, resource)
    if resource.kind != 'venue' or not resource.published or resource.deleted or not resource.enabled:
        raise HTTPException(409, 'QR можно выдать только опубликованному заведению')
    token = secrets.token_urlsafe(32)
    resource.qr_hash = digest(token)
    audit(db, user, 'qr_rotated', resource.id)
    db.commit()
    return {'code': f'QAZAQMETAL:1:{resource.id}:{token}',
            'warning': 'Сохраните или распечатайте код. Повторная выдача отменяет предыдущий'}


@app.post('/api/media', status_code=201)
async def upload(file: UploadFile = File(...), user=Depends(manager)):
    data = await file.read(8 * 1024 * 1024 + 1)
    if len(data) > 8 * 1024 * 1024:
        raise HTTPException(413, 'Изображение не больше 8 МБ')
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format not in ('JPEG', 'PNG', 'WEBP'):
                raise ValueError()
            image.load()
            image = image.convert('RGB')
            image.thumbnail((2400, 2400))
            name = uuid.uuid4().hex + '.webp'
            image.save(UPLOADS / name, 'WEBP', quality=85)
    except (UnidentifiedImageError, ValueError, OSError, Image.DecompressionBombError):
        raise HTTPException(422, 'Нужен корректный JPEG, PNG или WebP') from None
    return {'path': '/media/' + name}


@app.get('/media/{name}')
def media(name: str, user=Depends(ready_user)):
    if not re.fullmatch(r'[a-f0-9]{32}\.webp', name):
        raise HTTPException(404)
    path = UPLOADS / name
    if not path.is_file():
        raise HTTPException(404)
    return FileResponse(path, media_type='image/webp', headers={'Cache-Control': 'private, max-age=3600'})


@app.get('/api/workspace/stats')
def stats(start: date | None = None, end: date | None = None, venue_id: str = '',
          organization_id: str = '', user=Depends(manager), db=Depends(get_db)):
    query = select(Visit)
    if user.role == 'partner':
        query = query.where(Visit.partner_id == user.partner_id)
    if venue_id:
        query = query.where(Visit.venue_id == venue_id)
    if organization_id and user.role == 'admin':
        query = query.where(Visit.organization_id == organization_id)
    if start:
        query = query.where(Visit.created_at >= datetime.combine(start, time.min))
    if end:
        query = query.where(Visit.created_at < datetime.combine(end + timedelta(days=1), time.min))
    visits = db.scalars(query.order_by(Visit.created_at.desc())).all()
    venues, days = {}, {}
    for v in visits:
        venues.setdefault(v.venue_id, {'venue_id': v.venue_id, 'name': v.venue_name, 'uses': 0})['uses'] += 1
        day = v.created_at.date().isoformat()
        days[day] = days.get(day, 0) + 1
    return {'total_uses': len(visits), 'unique_members': len({v.user_id for v in visits}),
            'venues': list(venues.values()), 'days': days,
            'operations': [visit_json(v, private=user.role == 'admin') for v in visits[:500]]}


@app.get('/api/admin/organizations')
def organizations(user=Depends(admin), db=Depends(get_db)):
    return [dict(id=r.id, code=r.code, name=r.name, active=r.active)
            for r in db.scalars(select(Organization).order_by(Organization.name)).all()]


@app.post('/api/admin/organizations', status_code=201)
def add_org(body: S.OrganizationIn, user=Depends(admin), db=Depends(get_db)):
    r = Organization(**body.model_dump())
    db.add(r)
    db.flush()
    audit(db, user, 'organization_created', r.id)
    db.commit()
    return dict(id=r.id, code=r.code, name=r.name, active=r.active)


@app.put('/api/admin/organizations/{org_id}')
def edit_org(org_id: str, body: S.OrganizationIn, user=Depends(admin), db=Depends(get_db)):
    r = require(db.get(Organization, org_id))
    for k, value in body.model_dump().items():
        setattr(r, k, value)
    audit(db, user, 'organization_updated', org_id, active=body.active)
    db.commit()
    return {'ok': True}


@app.get('/api/admin/partners')
def partners(user=Depends(admin), db=Depends(get_db)):
    return [dict(id=r.id, name=r.name, active=r.active) for r in db.scalars(select(Partner).order_by(Partner.name)).all()]


@app.post('/api/admin/partners', status_code=201)
def add_partner(body: S.PartnerIn, user=Depends(admin), db=Depends(get_db)):
    r = Partner(**body.model_dump())
    db.add(r)
    db.flush()
    audit(db, user, 'partner_created', r.id)
    db.commit()
    return dict(id=r.id, name=r.name, active=r.active)


@app.put('/api/admin/partners/{partner_id}')
def edit_partner(partner_id: str, body: S.PartnerIn, user=Depends(admin), db=Depends(get_db)):
    r = require(db.get(Partner, partner_id))
    r.name, r.active = body.name, body.active
    audit(db, user, 'partner_updated', partner_id, active=body.active)
    db.commit()
    return {'ok': True}


def create_account(db, body, actor):
    if body.organization_id:
        require(db.get(Organization, body.organization_id), 'Организация не найдена')
    if body.partner_id:
        require(db.get(Partner, body.partner_id), 'Партнёр не найден')
    password = new_password()
    values = body.model_dump()
    values['username'] = values['username'].casefold() if values['username'] else None
    if values['member_until']:
        values['member_until'] = datetime.combine(values['member_until'], time.max)
    account = User(**values, password_hash=hash_password(password), must_change_password=True)
    db.add(account)
    db.flush()
    audit(db, actor, 'account_created', account.id, role=account.role)
    return account, password


@app.get('/api/admin/accounts')
def accounts(q: str = '', organization_id: str = '', status: str = '',
             limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0),
             user=Depends(admin), db=Depends(get_db)):
    query = select(User)
    if q:
        # Literal substring: do not interpret SQL LIKE wildcard characters from input.
        safe = q.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        query = query.where(or_(User.name.ilike('%'+safe+'%', escape='\\'),
                               User.employee_number.ilike('%'+safe+'%', escape='\\')))
    if organization_id:
        query = query.where(User.organization_id == organization_id)
    if status:
        query = query.where(User.status == status)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    return {'items': [user_json(u) for u in db.scalars(query.order_by(User.created_at.desc()).offset(offset).limit(limit)).all()], 'total': total}


@app.post('/api/admin/accounts', status_code=201)
def add_account(body: S.AccountIn, user=Depends(admin), db=Depends(get_db)):
    account, password = create_account(db, body, user)
    db.commit()
    return {'user': user_json(account), 'temporary_password': password}


@app.post('/api/admin/accounts/import')
async def import_accounts(organization_id: str, file: UploadFile = File(...),
                          user=Depends(admin), db=Depends(get_db)):
    require(db.get(Organization, organization_id), 'Организация не найдена')
    raw = await file.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise HTTPException(413, 'CSV не больше 1 МБ')
    try:
        rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))
        if not rows or len(rows) > 500:
            raise ValueError('От 1 до 500 работников за одну загрузку')
        prepared, seen = [], set()
        for line, row in enumerate(rows, 2):
            account = S.AccountIn(name=row.get('name', ''), employee_number=row.get('employee_number', ''),
                                  phone=row.get('phone') or None, organization_id=organization_id)
            if account.employee_number in seen:
                raise ValueError(f'Повтор табельного номера в строке {line}')
            seen.add(account.employee_number)
            prepared.append(account)
        existing = db.scalar(select(User.id).where(User.organization_id == organization_id,
                                                   User.employee_number.in_(seen)).limit(1))
        if existing:
            raise ValueError('В CSV есть уже добавленный работник; загрузка отменена целиком')
    except (ValueError, UnicodeError) as exc:
        raise HTTPException(422, str(exc)[:1000]) from None
    credentials = []
    for account in prepared:
        person, password = create_account(db, account, user)
        credentials.append({'employee_number': person.employee_number, 'temporary_password': password})
    db.commit()
    return {'count': len(credentials), 'credentials': credentials}


@app.post('/api/admin/accounts/{account_id}/status')
def account_status(account_id: str, body: S.StatusIn, user=Depends(admin), db=Depends(get_db)):
    person = require(db.scalar(select(User).where(User.id == account_id).with_for_update()))
    if person.id == user.id:
        raise HTTPException(409, 'Нельзя закрыть собственный доступ')
    if body.status == 'dismissed' and person.role != 'member':
        raise HTTPException(422, 'Увольнение относится к участникам')
    person.status, person.status_reason = body.status, body.reason
    db.execute(delete(Session).where(Session.user_id == person.id))
    audit(db, user, 'account_status_changed', person.id, status=body.status, reason=body.reason)
    db.commit()
    return user_json(person)


@app.post('/api/admin/accounts/{account_id}/reset-password')
def reset_password(account_id: str, user=Depends(admin), db=Depends(get_db)):
    person = require(db.get(User, account_id))
    if person.id == user.id:
        raise HTTPException(409, 'Свой пароль меняйте в профиле')
    password = new_password()
    person.password_hash, person.must_change_password = hash_password(password), True
    db.execute(delete(Session).where(Session.user_id == person.id))
    audit(db, user, 'password_reset', person.id)
    db.commit()
    return {'temporary_password': password}


@app.get('/api/tickets')
def tickets(user=Depends(ready_user), db=Depends(get_db)):
    query = select(Ticket).order_by(Ticket.created_at.desc())
    if user.role != 'admin':
        query = query.where(Ticket.user_id == user.id)
    return [dict(id=t.id, subject=t.subject, message=t.message, reply=t.reply,
                 status=t.status, created_at=t.created_at.isoformat()+'Z') for t in db.scalars(query.limit(500)).all()]


@app.post('/api/tickets', status_code=201)
def add_ticket(body: S.TicketIn, user=Depends(ready_user), db=Depends(get_db)):
    ticket = Ticket(user_id=user.id, **body.model_dump())
    db.add(ticket)
    db.flush()
    audit(db, user, 'ticket_created', ticket.id)
    db.commit()
    return {'id': ticket.id}


@app.post('/api/admin/tickets/{ticket_id}')
def reply(ticket_id: str, body: S.ReplyIn, user=Depends(admin), db=Depends(get_db)):
    ticket = require(db.get(Ticket, ticket_id))
    ticket.status, ticket.reply = body.status, body.reply
    audit(db, user, 'ticket_replied', ticket.id, status=body.status)
    db.commit()
    return {'ok': True}


@app.get('/api/admin/audit')
def audit_log(limit: int = Query(100, ge=1, le=500), user=Depends(admin), db=Depends(get_db)):
    return [dict(id=a.id, actor_id=a.actor_id, action=a.action, target=a.target,
                 detail=a.detail, created_at=a.created_at.isoformat()+'Z')
            for a in db.scalars(select(Audit).order_by(Audit.created_at.desc()).limit(limit)).all()]


@app.get('/api/workspace/options')
def workspace_options(user=Depends(manager), db=Depends(get_db)):
    partners = select(Partner).where(Partner.active.is_(True))
    if user.role == 'partner':
        partners = partners.where(Partner.id == user.partner_id)
    return {'partners': [dict(id=p.id, name=p.name) for p in db.scalars(partners).all()],
            'organizations': [dict(id=o.id, name=o.name) for o in db.scalars(select(Organization).where(Organization.active.is_(True))).all()]}


if WEB.is_dir():
    app.mount('/', StaticFiles(directory=WEB, html=True), name='web')
