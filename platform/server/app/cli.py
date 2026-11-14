"""Administrative commands; never create production demo accounts automatically."""
import argparse
import getpass
import json
from pathlib import Path

from sqlalchemy import select

from .db import Audit, Partner, Resource, Revision, SessionLocal, User
from .schemas import ResourceData
from .security import hash_password


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['bootstrap-admin', 'import-reference'])
    parser.add_argument('--username', default='')
    parser.add_argument('--file', default='')
    args = parser.parse_args()
    with SessionLocal() as db:
        if args.command == 'bootstrap-admin':
            if not args.username:
                parser.error('--username is required')
            if db.scalar(select(User).where(User.username == args.username.casefold())):
                parser.error('This login already exists')
            password = getpass.getpass('Temporary password (12+ characters): ')
            if len(password) < 12:
                parser.error('Password must contain at least 12 characters')
            user = User(username=args.username.casefold(), name='Администратор профсоюза',
                        role='admin', password_hash=hash_password(password), must_change_password=True)
            db.add(user)
            db.flush()
            db.add(Audit(actor_id=user.id, action='bootstrap_admin', target=user.id, detail={}))
            db.commit()
            print('Administrator created. First login requires a new password.')
        else:
            # Reference advertisements are drafts. No publication or partner credentials are implied.
            source = json.loads(Path(args.file).read_text())
            admin = db.scalar(select(User).where(User.role == 'admin'))
            if not admin:
                parser.error('Create an administrator first')
            for entry in source:
                if db.scalar(select(Partner).where(Partner.name == entry['partner'])):
                    continue
                partner = Partner(name=entry['partner'])
                db.add(partner)
                db.flush()
                venue = Resource(kind='venue', partner_id=partner.id)
                db.add(venue)
                db.flush()
                payload = ResourceData(**entry['venue']).model_dump(mode='json')
                db.add(Revision(resource_id=venue.id, author_id=admin.id, payload=payload, base_version=0))
                if entry.get('offer'):
                    offer = Resource(kind='offer', partner_id=partner.id, venue_id=venue.id)
                    db.add(offer)
                    db.flush()
                    db.add(Revision(resource_id=offer.id, author_id=admin.id,
                                    payload=ResourceData(**entry['offer']).model_dump(mode='json'), base_version=0))
                db.add(Audit(actor_id=admin.id, action='reference_imported', target=partner.id,
                             detail={'source': entry['source'], 'requires_confirmation': True}))
            db.commit()
            print('Reference data imported as pending drafts. Verify terms, photos and addresses before approval.')


if __name__ == '__main__':
    main()
