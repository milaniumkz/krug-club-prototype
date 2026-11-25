import os
import uuid
from datetime import datetime, timezone

from sqlalchemy import (JSON, Boolean, DateTime, Float, ForeignKey, Index, Integer,
                        String, UniqueConstraint, create_engine, event)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


def now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def uid():
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class Organization(Base):
    __tablename__ = 'organizations'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    code: Mapped[str] = mapped_column(String(40), unique=True)
    name: Mapped[str] = mapped_column(String(240))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Partner(Base):
    __tablename__ = 'partners'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    name: Mapped[str] = mapped_column(String(240))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class User(Base):
    __tablename__ = 'users'
    __table_args__ = (UniqueConstraint('organization_id', 'employee_number'),
                     UniqueConstraint('organization_id', 'phone'))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    username: Mapped[str | None] = mapped_column(String(160), unique=True)
    organization_id: Mapped[str | None] = mapped_column(ForeignKey('organizations.id'))
    partner_id: Mapped[str | None] = mapped_column(ForeignKey('partners.id'))
    employee_number: Mapped[str | None] = mapped_column(String(80), index=True)
    phone: Mapped[str | None] = mapped_column(String(20), index=True)
    name: Mapped[str] = mapped_column(String(240))
    avatar_path: Mapped[str | None] = mapped_column(String(80))
    role: Mapped[str] = mapped_column(String(20), default='member')
    status: Mapped[str] = mapped_column(String(20), default='active')
    status_reason: Mapped[str] = mapped_column(String(1000), default='')
    password_hash: Mapped[str] = mapped_column(String(512))
    must_change_password: Mapped[bool] = mapped_column(Boolean, default=True)
    member_until: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class Session(Base):
    __tablename__ = 'sessions'
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class LoginAttempt(Base):
    __tablename__ = 'login_attempts'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    key: Mapped[str] = mapped_column(String(64), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now, index=True)


class Resource(Base):
    __tablename__ = 'resources'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    kind: Mapped[str] = mapped_column(String(20), index=True)
    partner_id: Mapped[str] = mapped_column(ForeignKey('partners.id'), index=True)
    venue_id: Mapped[str | None] = mapped_column(ForeignKey('resources.id'), index=True)
    published: Mapped[dict | None] = mapped_column(JSON)
    version: Mapped[int] = mapped_column(Integer, default=0)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    latitude: Mapped[float | None] = mapped_column(Float, index=True)
    longitude: Mapped[float | None] = mapped_column(Float, index=True)
    qr_hash: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class Revision(Base):
    __tablename__ = 'revisions'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    resource_id: Mapped[str] = mapped_column(ForeignKey('resources.id'), index=True)
    author_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    payload: Mapped[dict] = mapped_column(JSON)
    action: Mapped[str] = mapped_column(String(20), default='publish')
    base_version: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(20), default='pending', index=True)
    reason: Mapped[str] = mapped_column(String(1000), default='')
    moderator_id: Mapped[str | None] = mapped_column(ForeignKey('users.id'))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime)


class Visit(Base):
    __tablename__ = 'visits'
    __table_args__ = (UniqueConstraint('user_id', 'request_id'),
                     Index('ix_visits_partner_date', 'partner_id', 'created_at'))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    request_id: Mapped[str] = mapped_column(String(36))
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    organization_id: Mapped[str] = mapped_column(ForeignKey('organizations.id'))
    partner_id: Mapped[str] = mapped_column(ForeignKey('partners.id'))
    venue_id: Mapped[str] = mapped_column(ForeignKey('resources.id'), index=True)
    offer_id: Mapped[str] = mapped_column(ForeignKey('resources.id'))
    venue_name: Mapped[str] = mapped_column(String(240))
    offer_name: Mapped[str] = mapped_column(String(240))
    percent: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class Favorite(Base):
    __tablename__ = 'favorites'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    venue_id: Mapped[str] = mapped_column(ForeignKey('resources.id'), primary_key=True)


class Ticket(Base):
    __tablename__ = 'tickets'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    subject: Mapped[str] = mapped_column(String(240))
    message: Mapped[str] = mapped_column(String(4000))
    status: Mapped[str] = mapped_column(String(20), default='open')
    reply: Mapped[str] = mapped_column(String(4000), default='')
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class Audit(Base):
    __tablename__ = 'audit'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    actor_id: Mapped[str | None] = mapped_column(ForeignKey('users.id'))
    action: Mapped[str] = mapped_column(String(100))
    target: Mapped[str] = mapped_column(String(100))
    detail: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


def make_engine(url):
    engine = create_engine(url, pool_pre_ping=True,
                           connect_args={'check_same_thread': False} if url.startswith('sqlite') else {})
    if url.startswith('sqlite'):
        @event.listens_for(engine, 'connect')
        def sqlite_fk(connection, _):
            connection.execute('PRAGMA foreign_keys=ON')
            connection.execute('PRAGMA busy_timeout=10000')
    return engine


engine = make_engine(os.getenv('DATABASE_URL', 'sqlite:///./qazaqmetal.db'))
SessionLocal = sessionmaker(engine, expire_on_commit=False)


def get_db():
    with SessionLocal() as db:
        yield db


class PushDevice(Base):
    __tablename__ = 'push_devices'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    token: Mapped[str] = mapped_column(String(4096))
    platform: Mapped[str] = mapped_column(String(12))
    language: Mapped[str] = mapped_column(String(2), default='ru')
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now)


class Notification(Base):
    __tablename__ = 'notifications'
    __table_args__ = (UniqueConstraint('user_id', 'event_key'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    venue_id: Mapped[str] = mapped_column(ForeignKey('resources.id'))
    event_key: Mapped[str] = mapped_column(String(100))
    kind: Mapped[str] = mapped_column(String(24))
    title: Mapped[str] = mapped_column(String(240))
    title_kk: Mapped[str] = mapped_column(String(240))
    body: Mapped[str] = mapped_column(String(1000))
    body_kk: Mapped[str] = mapped_column(String(1000))
    read_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=now, index=True)


class PushDelivery(Base):
    __tablename__ = 'push_deliveries'
    __table_args__ = (UniqueConstraint('notification_id', 'device_id'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    notification_id: Mapped[str] = mapped_column(ForeignKey('notifications.id'))
    device_id: Mapped[str] = mapped_column(ForeignKey('push_devices.id'))
    status: Mapped[str] = mapped_column(String(16), default='pending', index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime, default=now, index=True)
    last_error: Mapped[str] = mapped_column(String(80), default='')


class AppSetting(Base):
    __tablename__ = 'app_settings'
    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    revision: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=now)
    updated_by: Mapped[str | None] = mapped_column(ForeignKey('users.id', ondelete='SET NULL'))
