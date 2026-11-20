"""Inspect or queue one push for an isolated store-review iOS device only."""
import json
import sys
import uuid

sys.path.insert(0, '/app')
from sqlalchemy import select
from app.db import Audit, Notification, Organization, PushDelivery, PushDevice, Resource, SessionLocal, User
from app.notifications import push_eligible

request = json.load(sys.stdin)
role, operation = request['role'], request['operation']
if role not in ('member', 'partner') or operation not in ('inspect', 'push'):
    raise SystemExit('Unsupported review-device operation')

def fixture(label):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'qmet-store-review-2026/' + label))

with SessionLocal() as db:
    user = db.get(User, fixture(role + '-user'))
    venue = db.get(Resource, fixture('venue'))
    org = db.get(Organization, fixture('org'))
    if not user or user.role != role or user.status != 'active' or not venue or not org or org.code != 'STORE_REVIEW':
        raise SystemExit('Isolated review fixtures unavailable')
    if role == 'member' and user.organization_id != org.id:
        raise SystemExit('Unexpected review organization')
    if role == 'partner' and user.partner_id != venue.partner_id:
        raise SystemExit('Unexpected review partner')
    devices = db.scalars(select(PushDevice).where(PushDevice.user_id == user.id,
        PushDevice.platform == 'ios', PushDevice.active.is_(True))).all()
    print(json.dumps({'role': role, 'active_ios_devices': len(devices)}), flush=True)
    if operation == 'push':
        if len(devices) != 1:
            raise SystemExit('Exactly one isolated iOS review device is required; nothing queued')
        key = 'store-device-check:' + role + ':' + str(uuid.uuid4())
        notice = Notification(user_id=user.id, venue_id=venue.id, event_key=key,
            kind='new_venue' if role == 'member' else 'moderation_approved',
            title='QMET+ · Проверка уведомлений', title_kk='QMET+ · Хабарландыруды тексеру',
            body='Тестовое push-уведомление на вашем iPhone. Сборка 22.',
            body_kk='iPhone құрылғысындағы сынақ push-хабарландыруы. 22 жинағы.')
        if not push_eligible(db, user, notice):
            raise SystemExit('Review device is not eligible; nothing queued')
        db.add(notice)
        db.flush()
        delivery = PushDelivery(notification_id=notice.id, device_id=devices[0].id)
        db.add(delivery)
        db.add(Audit(actor_id=None, action='store_review_push_check', target=user.id,
            detail={'role': role, 'isolated_demo_account': True, 'device_count': 1}))
        db.commit()
        print(json.dumps({'queued': True, 'notification_id': notice.id}), flush=True)
    else:
        notices = db.scalars(select(Notification).where(Notification.user_id == user.id,
            Notification.event_key.like('store-device-check:%')).order_by(Notification.created_at.desc()).limit(3)).all()
        for notice in notices:
            deliveries = db.scalars(select(PushDelivery).where(PushDelivery.notification_id == notice.id)).all()
            print(json.dumps({'notification_id': notice.id, 'deliveries': [
                {'status': item.status, 'attempts': item.attempts, 'error_code': item.last_error}
                for item in deliveries]}), flush=True)
