"""Run on the authorized host. Passwords generated here never enter repository/logs."""
import json,os,secrets,subprocess,sys,time,zipfile
from pathlib import Path
ROOT=Path('/opt/qazaqmetal'); shared=ROOT/'shared'; release=ROOT/'releases'/'2.3.0-fb894f86d2dc'
def run(args,**kwargs):
    return subprocess.run(args,check=True,**kwargs)
# Inspect before changing the host. Preserve existing services and app data.
print('HOST INVENTORY',flush=True)
run(['uname','-a']);run(['free','-h']);run(['df','-h','/'])
os_release=Path('/etc/os-release').read_text();print(os_release,flush=True)
if 'ID=ubuntu' not in os_release and 'ID=debian' not in os_release:raise SystemExit('Unsupported host: Ubuntu/Debian required')
run(['ss','-lntp'])
if not Path('/usr/bin/docker').exists():
    env={**os.environ,'DEBIAN_FRONTEND':'noninteractive'}
    run(['apt-get','update'],env=env)
    run(['apt-get','install','-y','ca-certificates','curl','gnupg'],env=env)
    distro='ubuntu' if 'ID=ubuntu' in os_release else 'debian'
    version=dict(line.split('=',1) for line in os_release.splitlines() if '=' in line)['VERSION_CODENAME'].strip('"')
    Path('/etc/apt/keyrings').mkdir(exist_ok=True)
    run(['curl','-fsSL',f'https://download.docker.com/linux/{distro}/gpg','-o','/etc/apt/keyrings/docker.asc'])
    Path('/etc/apt/keyrings/docker.asc').chmod(0o644)
    arch=subprocess.check_output(['dpkg','--print-architecture'],text=True).strip()
    Path('/etc/apt/sources.list.d/docker.list').write_text(f'deb [arch={arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/{distro} {version} stable\n')
    run(['apt-get','update'],env=env)
    run(['apt-get','install','-y','docker-ce','docker-ce-cli','containerd.io','docker-buildx-plugin','docker-compose-plugin'],env=env)
run(['systemctl','enable','--now','docker'])
run(['docker','compose','version'])
shared.mkdir(parents=True,exist_ok=True);shared.chmod(0o700)
config=shared/'.env'
if not config.exists():
    values={'DOMAIN':'qazaqmetal.109.235.119.144.sslip.io','ACME_EMAIL':'not-configured','DB_PASSWORD':secrets.token_urlsafe(36),'ROOT_DB_PASSWORD':secrets.token_urlsafe(36),'MAP_TILE_URL':'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png','MAP_ATTRIBUTION':'© OpenStreetMap contributors · Tiles OSM France','COMPOSE_PROJECT_NAME':'qazaqmetal','COMPOSE_FILE':'compose.yaml:/opt/qazaqmetal/shared/compose.production.override.yaml'}
    fd=os.open(config,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:f.write('\n'.join(f'{k}={v}' for k,v in values.items())+'\n')
# Add role portals without changing the existing database passwords.
with config.open('a') as f:
    text=config.read_text()
    for key,value in {'PARTNER_HOST':'qazaqmetalpartners.109.235.119.144.sslip.io','ADMIN_HOST':'qazaqmetaladmin.109.235.119.144.sslip.io'}.items():
        if key+'=' not in text:f.write(key+'='+value+'\n')
# ACME contact email is optional; use normal public TLS validation.
(shared/'Caddyfile').write_text('''{$DOMAIN}, {$PARTNER_HOST}, {$ADMIN_HOST} {
 encode zstd gzip
 request_body {
  max_size 9MB
 }
 reverse_proxy api:8000 {
  header_up X-Forwarded-For {remote_host}
  transport http {
   response_header_timeout 120s
  }
 }
}
''')
(shared/'compose.production.override.yaml').write_text('''services:
  edge:
    volumes:
      - /opt/qazaqmetal/shared/Caddyfile:/etc/caddy/Caddyfile:ro
''')
# Release immutable app source, never unpack over an existing working tree.
if not (release/'qazaqmetal/platform/compose.yaml').exists():
    release.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(ROOT/'incoming/project.zip') as z:
        for member in z.infolist():
            target=(release/member.filename).resolve()
            if not target.is_relative_to(release.resolve()):raise SystemExit('Unsafe package path')
        z.extractall(release)
platform=release/'qazaqmetal/platform'
(platform/'.env').unlink(missing_ok=True);(platform/'.env').symlink_to(config)
for name in ('deploy/init-db.sh','scripts/backup.sh','scripts/restore.sh'):
    (platform/name).chmod(0o755)
current=ROOT/'current'
if current.exists():
    result=subprocess.run(['docker','compose','ps','--status','running','-q'],cwd=current,capture_output=True,text=True)
    if result.returncode==0 and result.stdout.strip():run(['sh','scripts/backup.sh',str(shared/'backups')],cwd=current)
os.chdir(platform)
run(['docker','compose','config','--quiet'])
run(['docker','compose','up','-d','--build','--wait','--wait-timeout','240'])
if current.is_symlink():current.unlink()
elif current.exists():raise SystemExit('Existing /opt/qazaqmetal/current is not a symlink; refusing overwrite')
current.symlink_to(platform,target_is_directory=True)
# Open web ports only if a firewall is already enabled; do not alter SSH rules.
if Path('/usr/sbin/ufw').exists():
    result=subprocess.run(['ufw','status'],capture_output=True,text=True)
    if 'Status: active' in result.stdout:
        run(['ufw','allow','80/tcp']);run(['ufw','allow','443/tcp']);run(['ufw','allow','443/udp'])
run(['docker','compose','ps'])
print('Application services started; checking public HTTPS next.',flush=True)
