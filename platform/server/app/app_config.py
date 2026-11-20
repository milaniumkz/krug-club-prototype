"""Data-only remote configuration: no executable code, credentials or access-role edits."""
import hashlib
import html
import json
import re
from typing import Literal
from urllib.parse import urlsplit
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import Field, model_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from .db import AppSetting, Audit, get_db, now
from .schemas import Strict
from .security import admin, portal_role, ready_user
from . import session_events

router = APIRouter()
KEY = 'public-app-v1'


class NativeVersion(Strict):
    minimum_build: int = Field(default=0, ge=0, le=1000000000)
    latest_build: int = Field(default=0, ge=0, le=1000000000)
    store_url: str = Field(default='', max_length=1000)

    @model_validator(mode='after')
    def valid_policy(self):
        if self.latest_build < self.minimum_build:
            raise ValueError('Последняя версия не может быть меньше минимальной')
        if self.store_url:
            url = urlsplit(self.store_url)
            if url.scheme != 'https' or url.hostname not in ('play.google.com', 'apps.apple.com', 'github.com') or url.username or url.password:
                raise ValueError('Ссылка обновления: HTTPS Google Play, App Store или GitHub')
        if self.minimum_build and not self.store_url:
            raise ValueError('Для обязательного обновления нужна ссылка на опубликованную сборку')
        return self


class PlatformVersions(Strict):
    android: NativeVersion = Field(default_factory=NativeVersion)
    ios: NativeVersion = Field(default_factory=NativeVersion)


class VersionPolicies(Strict):
    member: PlatformVersions = Field(default_factory=PlatformVersions)
    partner: PlatformVersions = Field(default_factory=PlatformVersions)


class Features(Strict):
    qr: bool = True
    map: bool = True
    push: bool = True
    banners: bool = True


class Labels(Strict):
    home: str = Field(default='Главная', min_length=1, max_length=24)
    partners: str = Field(default='Партнёры', min_length=1, max_length=24)
    qr: str = Field(default='QR', min_length=1, max_length=24)
    map: str = Field(default='На карте', min_length=1, max_length=24)
    profile: str = Field(default='Профиль', min_length=1, max_length=24)


class Faq(Strict):
    question_ru: str = Field(min_length=1, max_length=200)
    answer_ru: str = Field(min_length=1, max_length=4000)
    question_kk: str = Field(min_length=1, max_length=200)
    answer_kk: str = Field(min_length=1, max_length=4000)


class Settings(Strict):
    brand_name: str = Field(default='QMET+', min_length=2, max_length=24)
    logo_path: str = Field(default='', max_length=160)
    accent_color: str = '#6e2ebd'
    background_color: str = '#f8f3ef'
    tagline_ru: str = Field(default='Выгодно быть вместе', max_length=160)
    tagline_kk: str = Field(default='Бірге болу тиімді', max_length=160)
    eyebrow_ru: str = Field(default='ПРИВИЛЕГИИ ВАШЕГО ПРОФСОЮЗА', max_length=100)
    eyebrow_kk: str = Field(default='КӘСІПОДАҒЫҢЫЗДЫҢ АРТЫҚШЫЛЫҚТАРЫ', max_length=100)
    greeting_ru: str = Field(default='Добрый день,\n{name}!', max_length=160)
    greeting_kk: str = Field(default='Қайырлы күн,\n{name}!', max_length=160)
    login_intro_ru: str = Field(default='Войдите по табельному номеру и паролю. Личный номер телефона не нужен. При первом входе используйте выданный временный пароль.', max_length=1000)
    login_intro_kk: str = Field(default='Табельдік нөміріңіз бен құпиясөзіңіз арқылы кіріңіз. Жеке телефон нөмірі қажет емес. Алғаш кіргенде берілген уақытша құпиясөзді пайдаланыңыз.', max_length=1000)
    partner_login_intro_ru: str = Field(default='Войдите по логину и паролю, выданным администрацией профсоюза.', max_length=1000)
    partner_login_intro_kk: str = Field(default='Кәсіподақ әкімшілігі берген логин мен құпиясөз арқылы кіріңіз.', max_length=1000)
    partners_title_ru: str = Field(default='Партнёры клуба', max_length=100)
    partners_title_kk: str = Field(default='Клуб серіктестері', max_length=100)
    offers_title_ru: str = Field(default='Особые предложения', max_length=100)
    offers_title_kk: str = Field(default='Арнайы ұсыныстар', max_length=100)
    home_sections: list[Literal['promotions', 'partners']] = Field(default_factory=lambda: ['promotions', 'partners'], max_length=2)
    labels_ru: Labels = Field(default_factory=Labels)
    labels_kk: Labels = Field(default_factory=lambda: Labels(home='Басты бет', partners='Серіктестер', qr='QR', map='Картада', profile='Профиль'))
    features: Features = Field(default_factory=Features)
    support_phone: str = Field(default='', max_length=30)
    support_email: str = Field(default='', max_length=254)
    support_url: str = Field(default='', max_length=1000)
    faq: list[Faq] = Field(default_factory=list, max_length=20)
    privacy_ru: str = Field(default='QMET+ предоставляет доступ к привилегиям членам профсоюза. Учётную запись создаёт уполномоченная организация. Для работы используются имя, организация, табельный номер, статус членства, избранное и история использования привилегий.\nКадры QR-сканера обрабатываются на устройстве. Геолокация используется с разрешения пользователя для поиска ближайших заведений. PIN и биометрическая проверка защищают вход на устройстве.\nС разрешения пользователя регистрируется токен уведомлений Firebase Cloud Messaging. Новые заведения доступны действующим членам профсоюза; предложения избранного направляются подписчикам.\nЗапросы о персональных данных и прекращении доступа принимаются через поддержку приложения и представителя профсоюза. Доступ прекращается после увольнения либо блокировки за нарушение правил.', max_length=25000)
    privacy_kk: str = Field(default='QMET+ кәсіподақ мүшелеріне артықшылықтарға қол жеткізуге мүмкіндік береді. Аккаунтты уәкілетті ұйым жасайды. Аты-жөні, ұйымы, табельдік нөмірі, мүшелік мәртебесі, таңдаулылары және артықшылықтарды пайдалану тарихы қолданылады.\nQR сканерінің кадрлары құрылғыда өңделеді. Геолокация жақын мекемелерді іздеу үшін пайдаланушының рұқсатымен қолданылады. PIN және биометриялық тексеру құрылғыға кіруді қорғайды.\nПайдаланушының рұқсатымен Firebase Cloud Messaging хабарландыру токені тіркеледі.\nЖеке деректерге қатысты өтініштер қолданбаның қолдау бөлімі және кәсіподақ өкілі арқылы қабылданады. Жұмыстан шыққан немесе ережелерді бұзған жағдайда қолжетімділік тоқтатылады.', max_length=25000)
    terms_ru: str = Field(default='Приложением пользуются действующие члены профсоюза подключённых организаций. Не передавайте аккаунт, пароль и PIN другим людям. Привилегии предоставляются на условиях опубликованного предложения партнёра. Статус участника и доступность предложения проверяются сервером при использовании QR. При увольнении доступ прекращается; нарушение правил может привести к блокировке. По спорным вопросам обратитесь в поддержку.', max_length=25000)
    terms_kk: str = Field(default='Қолданбаны қосылған ұйымдардың кәсіподақ мүшелері пайдаланады. Аккаунтыңызды, құпиясөзіңізді және PIN кодыңызды басқа адамдарға бермеңіз. Артықшылықтар серіктестің жарияланған ұсыныс шарттарына сәйкес беріледі. QR пайдаланылғанда мүшелік мәртебесі мен ұсыныстың қолжетімділігін сервер тексереді. Жұмыстан шыққанда қолжетімділік тоқтатылады; ереже бұзылғанда аккаунт бұғатталуы мүмкін. Даулы мәселелер бойынша қолдау бөліміне жүгініңіз.', max_length=25000)
    maintenance: bool = False
    maintenance_ru: str = Field(default='Проводим техническое обслуживание. Попробуйте немного позже.', max_length=1000)
    maintenance_kk: str = Field(default='Техникалық қызмет көрсету жүргізілуде. Сәл кейінірек қайталап көріңіз.', max_length=1000)
    update_ru: str = Field(default='Доступна новая версия приложения. Обновите её для продолжения работы.', max_length=1000)
    update_kk: str = Field(default='Қолданбаның жаңа нұсқасы қолжетімді. Жұмысты жалғастыру үшін жаңартыңыз.', max_length=1000)
    versions: VersionPolicies = Field(default_factory=VersionPolicies)

    @model_validator(mode='after')
    def valid_settings(self):
        if re.search(r'[\x00-\x1f]', self.brand_name):
            raise ValueError('Название должно быть в одну строку')
        if self.logo_path and not re.fullmatch(r'/media/[a-f0-9]{32}\.webp', self.logo_path):
            raise ValueError('Загрузите логотип через приложение')
        for color in (self.accent_color, self.background_color):
            if not re.fullmatch(r'#[a-fA-F0-9]{6}', color):
                raise ValueError('Цвет: #RRGGBB')
        def luminance(color):
            values = [int(color[i:i+2], 16)/255 for i in (1, 3, 5)]
            rgb = [v/12.92 if v <= 0.04045 else ((v+0.055)/1.055)**2.4 for v in values]
            return sum(v*w for v, w in zip(rgb, (0.2126, 0.7152, 0.0722)))
        if 1.05/(luminance(self.accent_color)+0.05) < 4.5:
            raise ValueError('Основной цвет слишком светлый для белых надписей. Выберите более тёмный оттенок')
        if luminance(self.background_color) < 0.72:
            raise ValueError('Для этого оформления нужен светлый фон')
        if len(set(self.home_sections)) != len(self.home_sections):
            raise ValueError('Блоки главной не должны повторяться')
        if self.support_email and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', self.support_email):
            raise ValueError('Проверьте email поддержки')
        if self.support_phone and not re.fullmatch(r'[+0-9 ()-]{3,30}', self.support_phone):
            raise ValueError('Проверьте телефон поддержки')
        if self.support_url:
            url = urlsplit(self.support_url)
            if url.scheme != 'https' or not url.hostname or url.username or url.password:
                raise ValueError('Поддержка: публичная HTTPS-ссылка без пароля')
        for value in (self.greeting_ru, self.greeting_kk):
            if re.search(r'[{}]', value.replace('{name}', '')):
                raise ValueError('В приветствии разрешён только шаблон {name}')
        return self


class UpdateSettings(Strict):
    expected_revision: int = Field(ge=0)
    settings: Settings


def read_settings(db):
    row = db.get(AppSetting, KEY)
    data = {k: v for k, v in (row.data if row else {}).items() if k in Settings.model_fields}
    return Settings.model_validate(data), row


def feature_enabled(db, name):
    settings, _ = read_settings(db)
    return bool(getattr(settings.features, name))


def require_feature(db, name, language='ru'):
    settings, _ = read_settings(db)
    if settings.maintenance or not getattr(settings.features, name):
        raise HTTPException(503, (settings.maintenance_kk if language.startswith('kk') else settings.maintenance_ru) if settings.maintenance else ('Бөлім уақытша қолжетімсіз. Кейінірек қайталап көріңіз' if language.startswith('kk') else 'Раздел временно недоступен. Попробуйте позже'))


def envelope(db, role):
    settings, row = read_settings(db)
    data = {'schema_version': 1, 'revision': row.revision if row else 0, 'portal': role, 'settings': settings.model_dump()}
    raw = json.dumps(data, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()
    data['etag'] = '"'+hashlib.sha256(raw).hexdigest()+'"'
    return data


@router.get('/api/app-config')
def public_config(request: Request, db=Depends(get_db)):
    data = envelope(db, portal_role(request) or 'member')
    if request.headers.get('if-none-match') == data['etag']:
        return Response(status_code=304, headers={'ETag': data['etag']})
    return JSONResponse(data, headers={'ETag': data['etag']})


@router.get('/api/admin/app-config')
def admin_config(request: Request, user=Depends(admin), db=Depends(get_db)):
    return envelope(db, 'admin')


@router.put('/api/admin/app-config')
def update_config(body: UpdateSettings, request: Request, user=Depends(admin), db=Depends(get_db)):
    row = db.scalar(select(AppSetting).where(AppSetting.key == KEY).with_for_update())
    if body.expected_revision != (row.revision if row else 0):
        raise HTTPException(409, 'Настройки изменены другим администратором. Обновите страницу')
    previous = row.data if row else {}
    if row is None:
        row = AppSetting(key=KEY, data={}, revision=0)
        db.add(row)
    row.data = body.settings.model_dump()
    row.revision += 1
    row.updated_at, row.updated_by = now(), user.id
    db.add(Audit(actor_id=user.id, action='app_settings_changed', target=KEY,
                 detail={'revision': row.revision, 'changed_fields': [k for k in row.data if row.data[k] != previous.get(k)]}))
    session_events.publish(db, 'catalog')
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Настройки уже сохранены другим администратором. Обновите страницу') from None
    return envelope(db, 'admin')


def client_version_guard(request: Request, db=Depends(get_db)):
    path = request.url.path
    if not path.startswith('/api/') or path.startswith('/api/admin/') or path in ('/api/app-config', '/api/meta', '/api/health', '/api/auth/watch', '/api/auth/logout'):
        return
    platform = request.headers.get('x-qm-platform', '')
    build = request.headers.get('x-qm-build', '')
    if platform not in ('android', 'ios') or not build.isdigit():
        return  # Backwards-compatible legacy clients and browser builds.
    role = portal_role(request) or 'member'
    if role == 'admin':
        return
    settings, _ = read_settings(db)
    policy = getattr(getattr(settings.versions, role), platform)
    if int(build) < policy.minimum_build:
        raise HTTPException(426, settings.update_kk if request.headers.get('accept-language', '').startswith('kk') else settings.update_ru)


@router.get('/privacy')
@router.get('/terms')
def legal_document(request: Request, lang: Literal['ru', 'kk'] = 'ru', db=Depends(get_db)):
    settings, _ = read_settings(db)
    key = 'privacy' if request.url.path == '/privacy' else 'terms'
    title = ('Политика конфиденциальности' if key == 'privacy' else 'Условия использования') if lang == 'ru' else ('Құпиялық саясаты' if key == 'privacy' else 'Пайдалану шарттары')
    text = getattr(settings, key+'_'+lang)
    return HTMLResponse('<!doctype html><html lang="'+lang+'"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+html.escape(title)+' · '+html.escape(settings.brand_name)+'</title><style>body{font:17px/1.65 system-ui;max-width:850px;margin:40px auto;padding:0 22px;background:#f8f3ef;color:#211b29}h1{line-height:1.2}p{white-space:pre-wrap}</style><h2>'+html.escape(settings.brand_name)+'</h2><h1>'+html.escape(title)+'</h1><p>'+html.escape(text)+'</p><a href="/">'+('В приложение' if lang == 'ru' else 'Қолданбаға')+'</a></html>')


@router.post('/api/me/deletion-request', status_code=201)
def deletion_request(user=Depends(ready_user), db=Depends(get_db)):
    from .db import Ticket
    existing = db.scalar(select(Ticket).where(Ticket.user_id == user.id, Ticket.subject == 'Запрос на удаление персональных данных', Ticket.status == 'open'))
    if existing:
        return {'id': existing.id, 'status': existing.status}
    ticket = Ticket(user_id=user.id, subject='Запрос на удаление персональных данных',
                    message='Пользователь запросил рассмотрение удаления персональных данных. Проверьте условия членства, трудовой статус и обязанности по хранению данных. Свяжитесь с участником через обращение.')
    db.add(ticket)
    db.commit()
    return {'id': ticket.id, 'status': ticket.status}
