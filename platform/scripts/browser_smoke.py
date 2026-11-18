"""Browser UI/API smoke test against a synthetic QA instance, never a live member database.
Requires server/requirements-browser.txt and a Chromium browser; saves only QA screenshots.
"""
import argparse
import json
import secrets
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import qrcode
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://127.0.0.1:8000')
parser.add_argument('--credentials', type=Path, required=True)
parser.add_argument('--screenshots', type=Path, default=Path('artifacts/browser'))
args = parser.parse_args()
creds = json.loads(args.credentials.read_text())
assert all(v['identifier'].lower().startswith('qa') for v in creds.values()), 'QA identities only'
args.screenshots.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p, tempfile.TemporaryDirectory() as temp:
    launch = dict(headless=True, args=['--no-sandbox', '--disable-dev-shm-usage'])
    if shutil.which('chromium'):
        launch['executable_path'] = shutil.which('chromium')
    browser = p.chromium.launch(**launch)
    def enable(page):
        page.wait_for_timeout(3000)
        if page.locator('flt-semantics-placeholder').count():
            page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
        page.wait_for_timeout(250)
    def fill(page, label, value):
        field = page.get_by_role('textbox', name=label, exact=True)
        field.click(); page.wait_for_timeout(250)
        page.keyboard.press('ControlOrMeta+A'); page.keyboard.insert_text(value)
        page.wait_for_timeout(150)
    def login(role):
        context = browser.new_context(viewport={'width': 390 if role == 'member' else 1320, 'height': 900},
                                      permissions=['geolocation'], geolocation={'latitude': 52.287, 'longitude': 76.967})
        page = context.new_page(); page.goto(args.url); enable(page)
        fill(page, 'Табельный номер / телефон / логин', creds[role]['identifier'])
        fill(page, 'Пароль', creds[role]['password'])
        page.get_by_role('button', name='Войти', exact=True).click(); page.wait_for_timeout(2000)
        return context, page
    member, page = login('member')
    me = member.request.get(args.url+'/api/auth/me').json()
    if me['must_change_password']:
        fill(page, 'Временный пароль', creds['member']['password'])
        personal = secrets.token_urlsafe(20)
        fill(page, 'Новый пароль', personal); fill(page, 'Повторите новый пароль', personal)
        page.get_by_role('button', name='Сохранить пароль', exact=True).click(); page.wait_for_timeout(2500)
        assert not member.request.get(args.url+'/api/auth/me').json()['must_change_password']
        creds['member']['password'] = personal
        args.credentials.write_text(json.dumps(creds))
    page.screenshot(path=str(args.screenshots/'home.png'))
    page.reload(); enable(page)
    assert member.request.get(args.url+'/api/auth/me').status == 200
    page.get_by_role('tab', name='На карте', exact=True).click(); page.wait_for_timeout(3500)
    page.screenshot(path=str(args.screenshots/'map.png'))
    assert 'OpenStreetMap contributors' in page.locator('body').inner_text()
    owner, op = login('partner')
    op.get_by_text('Заведения', exact=True).first.click(); op.wait_for_timeout(1000)
    op.get_by_role('button', name='Добавить', exact=True).click(); op.wait_for_timeout(1000)
    name = 'QA — новая точка '+str(int(time.time()))
    for label, value in [('Название', name), ('Категория', 'Кафе'), ('Адрес', 'QA — адрес')]:
        fill(op, label, value)
    op.get_by_role('button', name='Отправить на модерацию', exact=True).click(); op.wait_for_timeout(1200)
    assert member.request.get(args.url+'/api/catalog', params={'q': name}).json()['total'] == 0
    op.screenshot(path=str(args.screenshots/'partner-pending.png'))
    admin, ap = login('admin')
    ap.get_by_text('Модерация', exact=True).first.click(); ap.wait_for_timeout(1000)
    ap.screenshot(path=str(args.screenshots/'moderation.png'))
    # Only the isolated QA database is modified.
    for _ in range(20):
        if not ap.get_by_role('button', name='Одобрить', exact=True).count():
            break
        ap.get_by_role('button', name='Одобрить', exact=True).first.click(); ap.wait_for_timeout(250)
        ap.get_by_role('button', name='Продолжить', exact=True).click(); ap.wait_for_timeout(900)
    assert member.request.get(args.url+'/api/catalog', params={'q': name}).json()['total'] == 1
    venues = owner.request.get(args.url+'/api/workspace/resources?kind=venue').json()
    original = next(v for v in venues if v.get('data', {}).get('name') == 'QA — ресторан')
    code = owner.request.post(args.url+'/api/workspace/resources/'+original['id']+'/qr', data={},
                              headers={'X-QM-Client': 'web'}).json()['code']
    image = Path(temp)/'qr.png'; video = Path(temp)/'camera.y4m'
    qrcode.make(code).convert('RGB').resize((600, 600)).save(image)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-loop', '1', '-i', str(image), '-vf',
                    'pad=1280:720:(ow-iw)/2:(oh-ih)/2:white', '-r', '10', '-t', '8',
                    '-pix_fmt', 'yuv420p', '-f', 'yuv4mpegpipe', str(video)], check=True)
    state = member.storage_state(); browser.close()
    launch['args'] += ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
                       '--use-file-for-fake-video-capture='+str(video)]
    browser = p.chromium.launch(**launch)
    camera = browser.new_context(viewport={'width': 390, 'height': 844}, storage_state=state, permissions=['camera'])
    cp = camera.new_page(); cp.goto(args.url); enable(cp)
    cp.get_by_role('tab', name='QR', exact=True).click(); cp.wait_for_timeout(9000)
    assert 'Скидка получена' in cp.locator('body').inner_text()
    assert camera.request.get(args.url+'/api/me/history').json()[0]['percent'] == 15
    cp.screenshot(path=str(args.screenshots/'qr-result.png'))
    browser.close()
print('PASS: first password, session restore, map, partner submission, moderation, QR synthetic camera, history')
