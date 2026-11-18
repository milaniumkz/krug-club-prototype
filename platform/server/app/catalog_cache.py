"""Bounded, one-second catalog response cache. Authentication is never cached."""
from collections import OrderedDict
from threading import RLock
from time import monotonic
from sqlalchemy import event
from sqlalchemy.orm import Session as ORMSession

_TTL = 1.0
_MAX_ENTRIES = 128
_MAX_ITEM_BYTES = 256 * 1024
_entries = OrderedDict()
_lock = RLock()
_generation = 0


def invalidate():
    global _generation
    with _lock:
        _entries.clear()
        _generation += 1


def get(key):
    with _lock:
        row = _entries.get(key)
        if row and row[0] > monotonic():
            _entries.move_to_end(key)
            return row[1], _generation
        if row:
            _entries.pop(key, None)
        return None, _generation


def put(key, body, generation):
    if len(body) > _MAX_ITEM_BYTES:
        return
    with _lock:
        # A read that raced with a committed change must not repopulate stale data.
        if generation != _generation:
            return
        _entries[key] = (monotonic() + _TTL, body)
        _entries.move_to_end(key)
        while len(_entries) > _MAX_ENTRIES:
            _entries.popitem(last=False)


@event.listens_for(ORMSession, 'after_commit')
def invalidate_local_after_commit(_session):
    invalidate()
