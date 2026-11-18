"""Favorite venue inbox and push outbox; no external credentials required."""
from alembic import op
from app.db import PushDevice, Notification, PushDelivery
revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    for model in (PushDevice, Notification, PushDelivery):
        model.__table__.create(bind, checkfirst=True)

def downgrade():
    bind = op.get_bind()
    for model in (PushDelivery, Notification, PushDevice):
        model.__table__.drop(bind, checkfirst=True)
