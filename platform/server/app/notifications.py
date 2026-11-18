"""Favorite-venue notifications are created atomically only after moderation approves an offer."""
from datetime import datetime, time, timedelta, timezone
from sqlalchemy import select
from .db import Favorite, Notification, Organization, Partner, PushDelivery, PushDevice, Resource, User, now


def offer_approved(db, resource, previous):
    if resource.kind != 'offer' or not resource.published or resource.deleted or not resource.enabled:
        return
    before = (previous or {}).get('percent') or 0
    percent = resource.published.get('percent') or 0
    if previous and percent <= before:
        return
    venue = db.get(Resource, resource.venue_id)
    partner = db.get(Partner, resource.partner_id)
    if not venue or not venue.published or venue.deleted or not venue.enabled or not partner.active:
        return
    today = datetime.now(timezone(timedelta(hours=5))).date().isoformat()
    payload = resource.published
    if payload.get('ends_on') and payload['ends_on'] < today:
        return
    scheduled = now()
    if payload.get('starts_on') and payload['starts_on'] > today:
        scheduled = datetime.combine(datetime.fromisoformat(payload['starts_on']).date(), time.min)-timedelta(hours=5)
    restrictions = [p.get('organization_ids', []) for p in (venue.published, payload)]
    people = db.scalars(select(User).join(Favorite, Favorite.user_id == User.id)
        .join(Organization, User.organization_id == Organization.id)
        .where(Favorite.venue_id == venue.id, User.status == 'active', User.role == 'member', Organization.active.is_(True))).all()
    eligible = [p for p in people if (not p.member_until or p.member_until >= now())
        and not any(ids and p.organization_id not in ids for ids in restrictions)]
    key = resource.id+':'+str(resource.version)
    existing = set(db.scalars(select(Notification.user_id).where(Notification.event_key == key)))
    notices = []
    for person in eligible:
        if person.id in existing:
            continue
        name = venue.published['name']
        name_kk = venue.published.get('name_kk') or name
        notices.append(Notification(user_id=person.id, venue_id=venue.id, event_key=key,
            kind='discount_increased' if previous else 'new_offer',
            title='Скидка стала больше' if previous else 'Новая акция в избранном',
            title_kk='Жеңілдік артты' if previous else 'Таңдаулы мекемедегі жаңа акция',
            body=f'{name}: скидка {percent}%. Откройте предложение и условия.',
            body_kk=f'{name_kk}: {percent}% жеңілдік. Ұсыныс пен шарттарды ашыңыз.', created_at=scheduled))
    if not notices:
        return
    db.add_all(notices)
    db.flush()
    by_user = {n.user_id:n for n in notices}
    devices = db.scalars(select(PushDevice).where(PushDevice.user_id.in_(by_user), PushDevice.active.is_(True))).all()
    db.add_all([PushDelivery(notification_id=by_user[d.user_id].id, device_id=d.id, next_attempt_at=scheduled) for d in devices])
