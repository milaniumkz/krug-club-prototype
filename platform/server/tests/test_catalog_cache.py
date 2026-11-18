from sqlalchemy import select
from app import catalog_cache
from app.db import Organization, User
from app.security import hash_password
from test_system import setup_catalog
from conftest import TEMP, login


def test_cache_never_bypasses_revoked_session_and_visibility(world):
    client, admin, partner, member, venue, _, _ = setup_catalog(world)
    assert client.get("/api/catalog", headers=member).json()["total"] == 1
    assert client.get("/api/catalog", headers=member).json()["total"] == 1
    assert (
        client.post(
            "/api/admin/resources/" + venue["id"] + "/visibility",
            headers=admin,
            json={"enabled": False, "reason": "test"},
        ).status_code
        == 200
    )
    assert client.get("/api/catalog", headers=member).json()["total"] == 0
    assert client.post("/api/auth/logout", headers=member).status_code == 200
    assert client.get("/api/catalog", headers=member).status_code == 401


def test_cache_is_organization_scoped_and_favorites_are_not_shared(world):
    client, admin, partner, member, venue, _, _ = setup_catalog(world)
    _, factory, _ = world
    with factory() as db:
        org = Organization(code="SECOND", name="Second organization")
        db.add(org)
        db.flush()
        db.add(
            User(
                name="Second member",
                employee_number="2002",
                organization_id=org.id,
                password_hash=hash_password(TEMP),
            )
        )
        db.commit()
    second = login(client, "2002")
    from app.db import Resource

    with factory() as db:
        row = db.get(Resource, venue["id"])
        row.published = {**row.published, "organization_ids": [world[2]["org"]]}
        db.commit()
    assert client.get("/api/catalog", headers=member).json()["total"] == 1
    assert client.get("/api/catalog", headers=second).json()["total"] == 0
    assert (
        client.put("/api/me/favorites/" + venue["id"], headers=member).status_code
        == 200
    )
    assert (
        client.get("/api/catalog?favorites_only=true", headers=member).json()["total"]
        == 1
    )
    assert (
        client.get("/api/catalog?favorites_only=true", headers=second).json()["total"]
        == 0
    )


def test_cache_bypasses_temporary_password_gate_never(world):
    client, _, _, member, _, _, _ = setup_catalog(world)
    assert client.get("/api/catalog", headers=member).status_code == 200
    _, factory, _ = world
    with factory() as db:
        user = db.scalar(select(User).where(User.employee_number == "1001"))
        user.must_change_password = True
        db.commit()
    assert client.get("/api/catalog", headers=member).status_code == 428


def test_cache_expires_and_inflight_read_cannot_repopulate_after_invalidation(
    monkeypatch,
):
    clock = [10.0]
    monkeypatch.setattr(catalog_cache, "monotonic", lambda: clock[0])
    catalog_cache.invalidate()
    _, generation = catalog_cache.get("a")
    catalog_cache.put("a", b"old", generation)
    assert catalog_cache.get("a")[0] == b"old"
    clock[0] = 11.1
    assert catalog_cache.get("a")[0] is None
    _, generation = catalog_cache.get("a")
    catalog_cache.invalidate()
    catalog_cache.put("a", b"stale", generation)
    assert catalog_cache.get("a")[0] is None
