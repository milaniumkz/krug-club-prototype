"""Immediate cross-worker session revocation using PostgreSQL NOTIFY and async long polling."""
import asyncio
import contextlib
import os
from sqlalchemy import text, event
from sqlalchemy.orm import Session as ORMSession

CHANNEL = 'qm_session_revoked'
_subscribers = {}
_loop = None
_task = None


def invalidate(scope):
    if scope == 'catalog':
        from .catalog_cache import invalidate as clear_catalog
        clear_catalog()
    for queue, scopes in tuple(_subscribers.items()):
        if scope in scopes and queue.empty():
            queue.put_nowait(False)


def publish(db, scope):
    if db.bind.dialect.name == 'postgresql':
        db.execute(text('SELECT pg_notify(:channel, :scope)'), {'channel': CHANNEL, 'scope': scope})
    db.info.setdefault('session_revocations', set()).add(scope)


@event.listens_for(ORMSession, 'after_commit')
def deliver_local(session):
    scopes = session.info.pop('session_revocations', set())
    if _loop and not _loop.is_closed():
        for scope in scopes:
            _loop.call_soon_threadsafe(invalidate, scope)


@event.listens_for(ORMSession, 'after_rollback')
def discard_local(session):
    session.info.pop('session_revocations', None)


async def listen():
    import psycopg
    url = os.environ['DATABASE_URL'].replace('postgresql+psycopg://', 'postgresql://', 1)
    while True:
        try:
            async with await psycopg.AsyncConnection.connect(url, autocommit=True) as conn:
                await conn.execute('LISTEN '+CHANNEL)
                async for notification in conn.notifies():
                    invalidate(notification.payload)
        except asyncio.CancelledError:
            raise
        except Exception:
            # Clients also reauthenticate every 25 seconds if the listener reconnects.
            await asyncio.sleep(2)


async def start():
    global _loop, _task
    _loop = asyncio.get_running_loop()
    if os.getenv('APP_ENV') == 'production' and os.getenv('DATABASE_URL', '').startswith('postgresql'):
        _task = asyncio.create_task(listen())


async def stop():
    global _task
    if _task:
        _task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await _task
        _task = None
    _subscribers.clear()


async def watch(scopes, recheck):
    queue = asyncio.Queue(maxsize=1)
    _subscribers[queue] = set(scopes)
    try:
        await recheck()  # Close the authenticate/subscribe race without holding a DB connection.
        try:
            return await asyncio.wait_for(queue.get(), timeout=25)
        except TimeoutError:
            return True
    finally:
        _subscribers.pop(queue, None)
