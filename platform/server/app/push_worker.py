"""Optional FCM worker. Starts delivering only when a private Firebase key is configured."""
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from pathlib import Path
import httpx
from sqlalchemy import select
from .db import Notification, Organization, PushDelivery, PushDevice, SessionLocal, User, now


def message_for(notice, device, user):
    kk = device.language == 'kk'
    host = os.getenv('PARTNER_HOST' if user.role == 'partner' else 'MEMBER_HOST', '')
    if not host or '/' in host or ':' in host:
        raise ValueError('Configure the public push portal host')
    link = 'https://' + host + '/?notification=' + notice.id
    return {'token': device.token,
        'notification': {'title': notice.title_kk if kk else notice.title,
                         'body': notice.body_kk if kk else notice.body},
        'data': {'venue_id': notice.venue_id, 'notification_id': notice.id, 'kind': notice.kind},
        'android': {'notification': {'channel_id': 'partner_updates' if user.role == 'partner' else 'union_updates' if notice.kind == 'new_venue' else 'favorite_offers'}},
        'apns': {'payload': {'aps': {'sound': 'default'}}},
        'webpush': {'headers': {'TTL': '86400'}, 'fcm_options': {'link': link},
                    'notification': {'icon': 'https://' + host + '/icons/Icon-192.png', 'tag': notice.id}}}


def main():
    key = Path(os.getenv('GOOGLE_APPLICATION_CREDENTIALS', '/run/secrets/firebase_admin.json'))
    if not key.is_file():
        raise SystemExit('Configure the private Firebase service account before enabling the push profile')
    from google.oauth2 import service_account
    from google.auth.transport.requests import Request
    config = json.loads(key.read_text())
    credentials = service_account.Credentials.from_service_account_file(str(key), scopes=['https://www.googleapis.com/auth/firebase.messaging'])
    endpoint = 'https://fcm.googleapis.com/v1/projects/'+config['project_id']+'/messages:send'
    while True:
        if not credentials.valid:
            try:
                credentials.refresh(Request())
            except Exception:
                # No exception/response text: OAuth errors may include sensitive metadata.
                print('Push OAuth unavailable; retrying in 30 seconds', flush=True)
                time.sleep(30)
                continue
        with SessionLocal() as db:
            deliveries = db.scalars(select(PushDelivery).where(
                PushDelivery.status.in_(['pending', 'retry', 'sending']), PushDelivery.next_attempt_at <= now())
                .order_by(PushDelivery.next_attempt_at).limit(20).with_for_update(skip_locked=True)).all()
            work = []
            for delivery in deliveries:
                notice = db.get(Notification, delivery.notification_id)
                device = db.get(PushDevice, delivery.device_id)
                user = db.get(User, notice.user_id)
                org = db.get(Organization, user.organization_id) if user.organization_id else None
                from .notifications import push_eligible
                eligible = push_eligible(db, user, notice)
                if not device.active or device.user_id != user.id or user.status != 'active' or (user.member_until and user.member_until < now()) or (org and not org.active) or not eligible:
                    delivery.status = 'cancelled'
                    continue
                delivery.status = 'sending'
                delivery.attempts += 1
                delivery.next_attempt_at = now()+timedelta(minutes=5)
                message = message_for(notice, device, user)
                work.append((delivery.id, message))
            db.commit()
        def send(item):
            delivery_id, message = item
            try:
                response = httpx.post(endpoint,headers={'Authorization':'Bearer '+credentials.token},json={'message':message},timeout=20)
                # Never persist FCM response bodies: they can contain device tokens.
                try:
                    details = response.json().get('error', {}).get('details', [])
                    invalid = any(d.get('errorCode') == 'UNREGISTERED' for d in details)
                except (ValueError, AttributeError, TypeError):
                    invalid = False
                return delivery_id, response.status_code, invalid
            except httpx.HTTPError:
                return delivery_id, 503, False
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(send, work))
        with SessionLocal() as db:
            for delivery_id, status, invalid in results:
                delivery = db.get(PushDelivery, delivery_id)
                if delivery.status == 'cancelled':
                    continue
                if 200 <= status < 300:
                    delivery.status = 'sent'
                    delivery.last_error = ''
                elif invalid:
                    delivery.status = 'cancelled'
                    db.get(PushDevice, delivery.device_id).active = False
                else:
                    delivery.status = 'failed' if delivery.attempts >= 8 or status in (400, 401, 403) else 'retry'
                    delivery.last_error = 'HTTP_'+str(status)
                    delivery.next_attempt_at = now()+timedelta(seconds=min(3600, 2**delivery.attempts*10))
            db.commit()
        if results:
            print('Push batch processed: ' + str(len(results)) + '; accepted: ' + str(sum(200 <= r[1] < 300 for r in results)), flush=True)
        if not work:
            time.sleep(3)


if __name__ == '__main__':
    main()
