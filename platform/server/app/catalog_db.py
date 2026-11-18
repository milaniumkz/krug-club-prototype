"""Asynchronous DB pool for the read-heavy catalog; write transactions are unchanged."""
import os
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from .db import SessionLocal

_engine = None
_factory = None


async def get_catalog_db():
    global _engine, _factory
    url = os.getenv('DATABASE_URL', '')
    if not url.startswith('postgresql'):
        # Local SQLite development only; the handler runs blocking work in a thread.
        with SessionLocal() as session:
            yield session
        return
    if _factory is None:
        _engine = create_async_engine(url, pool_pre_ping=True, pool_size=10,
                                      max_overflow=0, pool_timeout=5)
        _factory = async_sessionmaker(_engine, expire_on_commit=False)
    async with _factory() as session:
        yield session


async def stop():
    global _engine, _factory
    if _engine is not None:
        await _engine.dispose()
        _engine = _factory = None
