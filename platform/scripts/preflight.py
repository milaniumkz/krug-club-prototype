"""Read-only deployment checks. Never prints passwords or replaces configuration."""
import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--env-file', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
path = args.env_file or root / '.env'
errors = []
if not path.is_file():
    errors.append('Missing .env: run scripts/configure_server.py --domain DOMAIN --email EMAIL on the target host')
    values = {}
else:
    values = dict(line.split('=', 1) for line in path.read_text().splitlines()
                  if line and not line.startswith('#') and '=' in line)
    for key in ['DOMAIN', 'ACME_EMAIL', 'DB_PASSWORD', 'ROOT_DB_PASSWORD']:
        if not values.get(key):
            errors.append(f'Missing configuration value: {key}')
    for key in ['DB_PASSWORD', 'ROOT_DB_PASSWORD']:
        if not re.fullmatch(r'[A-Za-z0-9_-]{32,}', values.get(key, '')):
            errors.append(f'{key} must contain at least 32 URL-safe characters')
    if values.get('DB_PASSWORD') == values.get('ROOT_DB_PASSWORD'):
        errors.append('Database user and root must have different passwords')
for file in ['web/index.html', 'web/main.dart.js', 'web/zxing.min.js']:
    if not (root / file).is_file():
        errors.append(f'Missing compiled web file: {file}; build the Flutter web client first')
if not os.access(root / 'deploy/init-db.sh', os.X_OK):
    errors.append('Run chmod 755 deploy/init-db.sh before starting PostgreSQL')
if not shutil.which('docker'):
    errors.append('Docker and Compose are required on the target host')
elif path.is_file():
    # Compose validates substitutions and service dependencies; its output is deliberately suppressed.
    command = ['docker', 'compose', '--env-file', str(path), '-f', str(root / 'compose.yaml'), 'config', '--quiet']
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    if result.returncode:
        errors.append('Docker Compose configuration validation failed; check the configuration locally')
if errors:
    for error in errors:
        print('FAIL:', error)
    raise SystemExit(1)
print('PASS: configuration, Compose dependencies, executable init script and compiled web are present.')
print('Next: docker compose up -d --build --wait; then bootstrap the administrator interactively.')
