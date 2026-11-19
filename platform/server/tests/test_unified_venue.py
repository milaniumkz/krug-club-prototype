import uuid
import io
from PIL import Image
from sqlalchemy import select
from app.db import Notification, Resource, User
from app.notifications import push_eligible
from conftest import login
from test_system import submit, approve


def test_venue_has_discount_without_separate_offer_and_updates_atomically(world):
    c, factory, _ = world
    a, p, m = login(c, "admin"), login(c, "owner"), login(c, "1001")
    venue = submit(c, p, percent=15, terms="На меню")
    assert c.get("/api/catalog", headers=m).json()["total"] == 0
    approve(c, a, venue)
    detail = c.get("/api/catalog/" + venue["id"], headers=m).json()
    assert len(detail["offers"]) == 1 and detail["offers"][0]["data"]["percent"] == 15
    with factory() as db:
        assert db.scalar(select(Resource).where(Resource.kind == "offer")) is None
    code = c.post("/api/workspace/resources/" + venue["id"] + "/qr", headers=p).json()[
        "code"
    ]
    scan = c.post(
        "/api/scan", headers=m, json={"code": code, "request_id": str(uuid.uuid4())}
    )
    assert scan.status_code == 200 and scan.json()["percent"] == 15
    c.put("/api/me/favorites/" + venue["id"], headers=m)
    data = {**venue["revision"]["data"], "percent": 25, "name": "Новое имя"}
    revision = c.post(
        "/api/workspace/resources/" + venue["id"] + "/revisions",
        headers=p,
        json={"data": data},
    ).json()
    assert (
        c.get("/api/catalog/" + venue["id"], headers=m).json()["offers"][0]["data"][
            "percent"
        ]
        == 15
    )
    assert (
        c.post(
            "/api/admin/moderation/" + revision["id"],
            headers=a,
            json={"decision": "approve"},
        ).status_code
        == 200
    )
    detail = c.get("/api/catalog/" + venue["id"], headers=m).json()
    assert (
        detail["data"]["name"] == "Новое имя"
        and detail["offers"][0]["data"]["percent"] == 25
    )
    notices = c.get("/api/me/notifications", headers=m).json()
    assert [n["kind"] for n in notices].count("new_venue") == 1
    assert [n["kind"] for n in notices].count("discount_increased") == 1
    assert all(
        n["kind"] != "new_venue"
        for n in c.get("/api/me/notifications", headers=p).json()
    )


def test_future_discount_does_not_hide_venue_and_qr_rejects_unavailable_privilege(
    world,
):
    c, _, _ = world
    a, p, m = login(c, "admin"), login(c, "owner"), login(c, "1001")
    venue = submit(c, p, percent=10, terms="Условия", starts_on="2099-01-01")
    approve(c, a, venue)
    detail = c.get("/api/catalog/" + venue["id"], headers=m).json()
    assert detail["offers"] == []
    code = c.post("/api/workspace/resources/" + venue["id"] + "/qr", headers=p).json()[
        "code"
    ]
    assert (
        c.post(
            "/api/scan", headers=m, json={"code": code, "request_id": str(uuid.uuid4())}
        ).status_code
        == 409
    )


def test_banner_only_notifies_favorites_after_approval_and_send_time_unfavorite_cancels(
    world,
):
    c, factory, _ = world
    a, p, m = login(c, "admin"), login(c, "owner"), login(c, "1001")
    venue = submit(c, p, percent=10, terms="Условия")
    approve(c, a, venue)
    image = io.BytesIO()
    Image.new("RGB", (20, 20), "purple").save(image, format="PNG")
    photo = c.post(
        "/api/media",
        headers=p,
        files={"file": ("banner.png", image.getvalue(), "image/png")},
    ).json()["path"]
    banner = submit(c, p, "banner", venue["id"], image=photo)
    approve(c, a, banner)
    assert not any(
        n["kind"] == "new_banner"
        for n in c.get("/api/me/notifications", headers=m).json()
    )
    c.put("/api/me/favorites/" + venue["id"], headers=m)
    banner = submit(c, p, "banner", venue["id"], image=photo)
    assert not any(
        n["kind"] == "new_banner"
        for n in c.get("/api/me/notifications", headers=m).json()
    )
    approve(c, a, banner)
    with factory() as db:
        notice = db.scalar(
            select(Notification).where(Notification.kind == "new_banner")
        )
        user = db.get(User, notice.user_id)
        assert push_eligible(db, user, notice)
    c.delete("/api/me/favorites/" + venue["id"], headers=m)
    with factory() as db:
        notice = db.scalar(
            select(Notification).where(Notification.kind == "new_banner")
        )
        assert not push_eligible(db, db.get(User, notice.user_id), notice)


def test_new_venue_goes_only_to_active_members_in_allowed_organizations(world):
    from datetime import timedelta
    from app.db import Organization, now
    from app.security import hash_password
    from conftest import TEMP

    c, factory, ids = world
    with factory() as db:
        other = Organization(code="SECOND", name="Другая организация")
        disabled = Organization(code="OFF", name="Отключена", active=False)
        db.add_all([other, disabled])
        db.flush()
        people = []
        for number, org, status, expired in [
            ("2001", ids["org"], "active", False),
            ("2002", ids["org"], "blocked", False),
            ("2003", ids["org"], "active", True),
            ("2004", other.id, "active", False),
            ("2005", disabled.id, "active", False),
        ]:
            u = User(
                name="Тест",
                employee_number=number,
                organization_id=org,
                role="member",
                status=status,
                member_until=now() - timedelta(days=1) if expired else None,
                password_hash=hash_password(TEMP),
            )
            db.add(u)
            people.append(u)
        db.commit()
        allowed_extra = people[0].id
    a, p = login(c, "admin"), login(c, "owner")
    venue = submit(c, p, percent=10, terms="Условия", organization_ids=[ids["org"]])
    with factory() as db:
        assert not db.scalar(
            select(Notification).where(Notification.venue_id == venue["id"])
        )
    approve(c, a, venue)
    with factory() as db:
        notices = db.scalars(
            select(Notification).where(
                Notification.kind == "new_venue", Notification.venue_id == venue["id"]
            )
        ).all()
        member = db.scalar(select(User).where(User.employee_number == "1001"))
        assert {n.user_id for n in notices} == {member.id, allowed_extra}
        assert all(push_eligible(db, db.get(User, n.user_id), n) for n in notices)
        assert all(db.get(User, n.user_id).role == "member" for n in notices)


def test_public_push_config_only_exposes_client_metadata(world, monkeypatch):
    import json

    c, _, _ = world
    monkeypatch.delenv("FIREBASE_CLIENT_CONFIG", raising=False)
    assert c.get("/api/push-config").json() == {"enabled": False}
    monkeypatch.setenv(
        "FIREBASE_CLIENT_CONFIG",
        json.dumps(
            {
                "member": {
                    "android": {
                        "apiKey": "public-client-key",
                        "appId": "public-app-id",
                        "messagingSenderId": "public-sender",
                        "projectId": "public-project",
                        "private_key": "DO-NOT-EXPOSE-SERVER-KEY",
                    }
                }
            }
        ),
    )
    response = c.get("/api/push-config")
    assert response.status_code == 200 and response.json()["enabled"]
    assert "DO-NOT-EXPOSE" not in response.text and "private_key" not in response.text


def test_reduced_venue_discount_does_not_notify_favorites(world):
    c, _, _ = world
    a, p, m = login(c, "admin"), login(c, "owner"), login(c, "1001")
    venue = submit(c, p, percent=20, terms="Условия")
    approve(c, a, venue)
    c.put("/api/me/favorites/" + venue["id"], headers=m)
    data = {**venue["revision"]["data"], "percent": 15}
    revision = c.post(
        "/api/workspace/resources/" + venue["id"] + "/revisions",
        headers=p,
        json={"data": data},
    ).json()
    assert (
        c.post(
            "/api/admin/moderation/" + revision["id"],
            headers=a,
            json={"decision": "approve"},
        ).status_code
        == 200
    )
    assert not any(
        n["kind"] == "discount_increased"
        for n in c.get("/api/me/notifications", headers=m).json()
    )
    assert (
        c.get("/api/catalog/" + venue["id"], headers=m).json()["offers"][0]["data"][
            "percent"
        ]
        == 15
    )
