"""Versioned public application content and native compatibility settings."""
from alembic import op
from app.db import AppSetting
revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    AppSetting.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    AppSetting.__table__.drop(op.get_bind(), checkfirst=True)
