"""Upload owner-approved QMET+ screenshots using Apple's documented asset flow."""
import argparse
import hashlib
import json
from pathlib import Path
import requests
from PIL import Image
from app_store_api import configured

p = argparse.ArgumentParser()
p.add_argument('--approved', action='store_true', required=True)
args = p.parse_args()
api = configured()
root = Path(__file__).resolve().parents[2] / 'output/store-assets'
results = []
for role, app in [('member', '6837248361'), ('partner', '6837250404')]:
    version = api.get(f'apps/{app}/appStoreVersions')['data'][0]
    locale = api.get('appStoreVersions/' + version['id'] + '/appStoreVersionLocalizations')['data'][0]
    sets = api.get('appStoreVersionLocalizations/' + locale['id'] + '/appScreenshotSets')['data']
    target = next((s for s in sets if s['attributes']['screenshotDisplayType'] == 'APP_IPHONE_67'), None)
    if target is None:
        target = api.request('POST', 'appScreenshotSets', json={'data': {
            'type': 'appScreenshotSets', 'attributes': {'screenshotDisplayType': 'APP_IPHONE_67'},
            'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': locale['id']}}}}})['data']
    existing = api.get('appScreenshotSets/' + target['id'] + '/appScreenshots')['data']
    for number in range(1, 4):
        path = root / f'{role}-{number:02d}.jpg'
        if Image.open(path).size != (1320, 2868):
            raise SystemExit('Unexpected screenshot dimensions: ' + path.name)
        data = path.read_bytes()
        checksum = hashlib.md5(data).hexdigest()
        for old in list(existing):
            if old['attributes']['fileName'] == path.name and (old['attributes'].get('sourceFileChecksum') != checksum or old['attributes']['assetDeliveryState']['state'] == 'FAILED'):
                api.request('DELETE', 'appScreenshots/' + old['id'])
                existing.remove(old)
        matching = next((s for s in existing if s['attributes']['fileName'] == path.name and s['attributes'].get('sourceFileChecksum') == checksum), None)
        if matching:
            screenshot = matching
        else:
            screenshot = api.request('POST', 'appScreenshots', json={'data': {
                'type': 'appScreenshots', 'attributes': {'fileSize': len(data), 'fileName': path.name},
                'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': target['id']}}}}})['data']
            for operation in screenshot['attributes']['uploadOperations']:
                offset, length = operation['offset'], operation['length']
                headers = {h['name']: h['value'] for h in operation['requestHeaders']}
                response = requests.request(operation['method'], operation['url'], headers=headers, data=data[offset:offset + length], timeout=90)
                if not response.ok:
                    raise RuntimeError('Apple asset upload returned HTTP ' + str(response.status_code))
            screenshot = api.patch('appScreenshots', screenshot['id'], {'uploaded': True, 'sourceFileChecksum': checksum})['data']
        results.append({'app': app, 'file': path.name, 'id': screenshot['id'], 'state': screenshot['attributes']['assetDeliveryState']['state']})
        print(role, path.name, 'uploaded', flush=True)
(root / 'apple-upload.json').write_text(json.dumps(results, indent=2))
