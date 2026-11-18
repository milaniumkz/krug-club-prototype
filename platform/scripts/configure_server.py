"""Create private deployment configuration on the target host without printing secrets."""
import argparse
import os
import re
import secrets
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--domain', required=True)
parser.add_argument('--email', required=True)
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / '.env')
args = parser.parse_args()
domain = args.domain.strip().lower()
if not re.fullmatch(r'(?=.{3,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}', domain):
    parser.error('Use a domain without https://, a path or a port')
if not re.fullmatch(r'[^\s=@]+@[^\s=@]+\.[^\s=@]+', args.email):
    parser.error('Use a valid contact email for the TLS certificate')
values = {'DOMAIN': domain, 'ACME_EMAIL': args.email,
          'DB_PASSWORD': secrets.token_urlsafe(36), 'ROOT_DB_PASSWORD': secrets.token_urlsafe(36),
          'MAP_TILE_URL': 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
          'MAP_ATTRIBUTION': '© OpenStreetMap contributors · Tiles OSM France'}
try:
    fd = os.open(args.output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
except FileExistsError:
    parser.error('Configuration already exists; existing passwords were preserved')
with os.fdopen(fd, 'w') as file:
    file.write('\n'.join(f'{k}={v}' for k, v in values.items()) + '\n')
print('Private configuration created. No passwords printed. Continue with preflight.py.')
