"""Small authenticated App Store Connect client; private keys stay outside Git."""
import base64
import json
from pathlib import Path
import time

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils


class AppStore:
    def __init__(self, key_id, issuer, key_path):
        def encode(value):
            raw = value if isinstance(value, bytes) else json.dumps(value, separators=(',', ':')).encode()
            return base64.urlsafe_b64encode(raw).rstrip(b'=')
        now = int(time.time())
        header = encode({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'})
        payload = encode({'iss': issuer, 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'})
        signing = header + b'.' + payload
        key = serialization.load_pem_private_key(Path(key_path).read_bytes(), password=None)
        r, s = utils.decode_dss_signature(key.sign(signing, ec.ECDSA(hashes.SHA256())))
        token = signing + b'.' + encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))
        self.session = requests.Session()
        self.session.headers.update(Authorization='Bearer ' + token.decode())

    def request(self, method, path, version='v1', **kwargs):
        if version not in ('v1', 'v2'):
            raise ValueError('Unsupported App Store API version')
        response = self.session.request(method, 'https://api.appstoreconnect.apple.com/' + version + '/' + path.lstrip('/'), timeout=90, **kwargs)
        if not response.ok:
            errors = response.json().get('errors', [])
            raise RuntimeError(json.dumps([{'status': e.get('status'), 'code': e.get('code'), 'detail': e.get('detail')} for e in errors], ensure_ascii=False))
        return response.json() if response.content else {}

    def get(self, path, **params):
        return self.request('GET', path, params=params)

    def patch(self, kind, identifier, attributes):
        return self.request('PATCH', kind + '/' + identifier, json={'data': {'type': kind, 'id': identifier, 'attributes': attributes}})


def configured():
    import os
    return AppStore(os.environ.get('ASC_KEY_ID', '7UTUP7KN6T'), os.environ.get('ASC_ISSUER_ID', '69a6de93-c892-47e3-e053-5b8c7c11a4d1'), os.environ.get('ASC_KEY_PATH', str(Path.home() / '.appstoreconnect/private_keys/AuthKey_7UTUP7KN6T.p8')))


if __name__ == '__main__':
    api = configured()
    for app_id in ('6837248361', '6837250404'):
        versions = api.get(f'apps/{app_id}/appStoreVersions')['data']
        builds = api.get('builds', **{'filter[app]': app_id})['data']
        print(json.dumps({'app_id': app_id, 'versions': [{'id': v['id'], 'version': v['attributes']['versionString'], 'state': v['attributes']['appStoreState']} for v in versions], 'builds': [{'id': b['id'], 'version': b['attributes']['version'], 'state': b['attributes']['processingState']} for b in builds]}))
