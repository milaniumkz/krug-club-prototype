"""Moderated publication events, role-specific inbox and transactional push outbox."""
from datetime import datetime, time, timedelta, timezone
from sqlalchemy import select
from .db import Favorite, Notification, Organization, Partner, PushDelivery, PushDevice, Resource, User, now


def _fanout(db, venue, resource, kind, title, title_kk, body, body_kk, favorites_only, scheduled=None):
    partner = db.get(Partner, venue.partner_id)
    if not venue.published or venue.deleted or not venue.enabled or not partner or not partner.active:
        return
    query = select(User).join(Organization, User.organization_id == Organization.id).where(
        User.status == 'active', User.role == 'member', Organization.active.is_(True))
    if favorites_only:
        query = query.join(Favorite, Favorite.user_id == User.id).where(Favorite.venue_id == venue.id)
    restrictions = [p.get('organization_ids', []) for p in (venue.published, resource.published)]
    people = [u for u in db.scalars(query) if (not u.member_until or u.member_until >= now())
              and not any(ids and u.organization_id not in ids for ids in restrictions)]
    key = kind+':'+resource.id+':'+str(resource.version)
    existing = set(db.scalars(select(Notification.user_id).where(Notification.event_key == key)))
    notices = [Notification(user_id=u.id, venue_id=venue.id, event_key=key, kind=kind,
        title=title, title_kk=title_kk, body=body[:1000], body_kk=body_kk[:1000], created_at=scheduled or now())
        for u in people if u.id not in existing]
    _save_notices(db, notices, scheduled)


def _save_notices(db, notices, scheduled=None):
    if not notices:
        return
    db.add_all(notices)
    db.flush()
    by_user = {n.user_id:n for n in notices}
    devices = db.scalars(select(PushDevice).where(PushDevice.user_id.in_(by_user), PushDevice.active.is_(True))).all()
    db.add_all([PushDelivery(notification_id=by_user[d.user_id].id, device_id=d.id, next_attempt_at=scheduled or now()) for d in devices])


def offer_approved(db, resource, previous):
    """Compatibility name: handles venue, discount and banner publication events."""
    if not resource.published or resource.deleted or not resource.enabled:
        return
    venue = resource if resource.kind == 'venue' else db.get(Resource, resource.venue_id)
    if not venue or not venue.published:
        return
    if resource.kind == 'offer' and venue.published.get('percent') is not None:
        return
    name = venue.published['name']
    kk = venue.published.get('name_kk') or name
    if resource.kind == 'venue' and previous is None:
        _fanout(db, venue, resource, 'new_venue', 'Новое заведение в приложении', 'Қосымшадағы жаңа мекеме',
                f'{name}: откройте заведение и узнайте условия привилегии.',
                f'{kk}: мекемені ашып, артықшылық шарттарын біліңіз.', False)
        return
    if resource.kind not in ('venue', 'offer', 'banner'):
        return
    payload = resource.published
    today = datetime.now(timezone(timedelta(hours=5))).date().isoformat()
    if payload.get('ends_on') and payload['ends_on'] < today:
        return
    scheduled = now()
    if payload.get('starts_on') and payload['starts_on'] > today:
        scheduled = datetime.combine(datetime.fromisoformat(payload['starts_on']).date(), time.min)-timedelta(hours=5)
    if resource.kind == 'banner':
        if previous and previous.get('image') == payload.get('image'):
            return
        _fanout(db, venue, resource, 'new_banner', 'Новое предложение в избранном', 'Таңдаулы мекемедегі жаңа ұсыныс',
                f'{name}: опубликован новый баннер. Посмотрите предложение партнёра.',
                f'{kk}: жаңа баннер жарияланды. Серіктестің ұсынысын қараңыз.', True, scheduled)
        return
    before = (previous or {}).get('percent') or 0
    if resource.kind == 'venue' and previous and previous.get('percent') is None:
        legacy = db.scalars(select(Resource).where(Resource.kind == 'offer', Resource.venue_id == venue.id,
            Resource.deleted.is_(False), Resource.enabled.is_(True), Resource.published.is_not(None))).all()
        before = max((r.published.get('percent') or 0 for r in legacy), default=0)
    percent = payload.get('percent') or 0
    if percent <= before or percent == 0:
        return
    kind = 'discount_increased' if previous else 'new_offer'
    _fanout(db, venue, resource, kind, 'Скидка стала больше' if previous else 'Новая акция в избранном',
            'Жеңілдік артты' if previous else 'Таңдаулы мекемедегі жаңа акция',
            f'{name}: скидка {percent}%. Откройте предложение и условия.',
            f'{kk}: {percent}% жеңілдік. Ұсыныс пен шарттарды ашыңыз.', True, scheduled)


def moderation_reviewed(db, resource, revision):
    key = 'review:' + revision.id
    people = db.scalars(select(User).where(User.partner_id == resource.partner_id,
        User.role == 'partner', User.status == 'active')).all()
    existing = set(db.scalars(select(Notification.user_id).where(Notification.event_key == key)))
    approved = revision.status == 'approved'
    name = (revision.payload or resource.published or {}).get('name', '')
    reason = revision.reason or ''
    notices = [Notification(user_id=u.id, venue_id=resource.id if resource.kind == 'venue' else resource.venue_id,
        event_key=key, kind='moderation_approved' if approved else 'moderation_rejected',
        title='Изменения одобрены' if approved else 'Нужны изменения',
        title_kk='Өзгерістер мақұлданды' if approved else 'Өзгерту қажет',
        body=(f'{name}: '+('изменения опубликованы.' if approved else 'изменения отклонены. '+reason))[:1000],
        body_kk=(f'{name}: '+('өзгерістер жарияланды.' if approved else 'өзгерістер қабылданбады. '+reason))[:1000])
        for u in people if u.id not in existing]
    _save_notices(db, notices)


def push_eligible(db, user, notice):
    venue = db.get(Resource, notice.venue_id)
    if not venue:
        return False
    partner = db.get(Partner, venue.partner_id)
    if user.role == 'partner' and notice.kind in ('moderation_approved', 'moderation_rejected'):
        return bool(venue.partner_id == user.partner_id and partner and partner.active)
    if user.role != 'member' or user.status != 'active' or (user.member_until and user.member_until < now()) or venue.deleted or not venue.enabled or not venue.published or not partner or not partner.active:
        return False
    org = db.get(Organization, user.organization_id) if user.organization_id else None
    if not org or not org.active:
        return False
    allowed = venue.published.get('organization_ids', [])
    if allowed and user.organization_id not in allowed:
        return False
    if notice.kind == 'new_venue':
        return True
    if notice.kind in ('new_offer', 'discount_increased', 'new_banner'):
        parts = notice.event_key.split(':')
        resource_id = parts[0] if len(parts[0]) == 36 else parts[1]
        resource = db.get(Resource, resource_id)
        if not resource or resource.deleted or not resource.enabled or not resource.published:
            return False
        limits = resource.published.get('organization_ids', [])
        today = datetime.now(timezone(timedelta(hours=5))).date().isoformat()
        if (limits and user.organization_id not in limits) or (resource.published.get('ends_on') and resource.published['ends_on'] < today):
            return False
        return db.get(Favorite, (user.id, notice.venue_id)) is not None
    return False
