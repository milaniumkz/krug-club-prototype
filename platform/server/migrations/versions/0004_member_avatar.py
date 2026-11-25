"""Optional participant profile photo; preserves existing accounts and sessions."""
from alembic import op
import sqlalchemy as sa
revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    if 'avatar_path' not in {c['name'] for c in sa.inspect(bind).get_columns('users')}:
        op.add_column('users', sa.Column('avatar_path', sa.String(80), nullable=True))

def downgrade():
    op.drop_column('users', 'avatar_path')
