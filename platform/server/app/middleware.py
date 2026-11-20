"""Streaming ASGI protection without BaseHTTPMiddleware task/stream overhead."""
import asyncio
import os
import weakref

from starlette.requests import Request
from starlette.responses import JSONResponse


class Protection:
    def __init__(self, app, *, origin, tile_origin, production, cookie):
        self.app = app
        self.origin = origin
        self.production = production
        self.cookie = cookie
        self.gates = weakref.WeakKeyDictionary()
        self.hosts = {os.getenv(k, '').lower() for k in ('MEMBER_HOST', 'PARTNER_HOST', 'ADMIN_HOST')}
        self.security = {
            'X-Content-Type-Options': 'nosniff',
            'Referrer-Policy': 'same-origin',
            'X-Frame-Options': 'DENY',
            'Permissions-Policy': 'camera=(self), geolocation=(self), microphone=()',
            'Content-Security-Policy': (
                "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com; worker-src 'self' blob:; style-src 'self' 'unsafe-inline'; "
                f"img-src 'self' data: blob: {tile_origin} https://tile.openstreetmap.org https://*.tile.openstreetmap.org https://*.tile.openstreetmap.fr https://tiles.openfreemap.org; "
                f"connect-src 'self' blob: https://firebaseinstallations.googleapis.com https://fcmregistrations.googleapis.com https://fcm.googleapis.com https://www.googleapis.com {tile_origin} https://tile.openstreetmap.org https://*.tile.openstreetmap.org https://*.tile.openstreetmap.fr https://tiles.openfreemap.org; "
                "font-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'self'; media-src 'self' blob:; "
            ),
        }
        if production:
            self.security['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
        self.encoded = [(k.lower().encode(), v.encode()) for k, v in self.security.items()]

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        request = Request(scope)
        path = scope['path']
        cache = 'no-store' if path.startswith('/api/') else (
            'no-cache' if path in ('/', '/index.html', '/flutter_bootstrap.js', '/version.json', '/firebase-messaging-sw.js') else None)
        headers = self.encoded + ([(b'cache-control', cache.encode())] if cache else [])
        replaced = {name for name, _ in headers}

        async def secured_send(message):
            if message['type'] == 'http.response.start':
                message = dict(message)
                message['headers'] = [(k, v) for k, v in message.get('headers', []) if k.lower() not in replaced] + headers
            await send(message)

        if request.method not in ('GET', 'HEAD', 'OPTIONS'):
            origin = request.headers.get('origin')
            allowed = ('https://' + request.url.hostname
                       if self.production and request.url.hostname in self.hosts else self.origin)
            detail, status = None, 403
            if origin and origin != allowed:
                detail = 'Недопустимый источник запроса'
            elif request.cookies.get(self.cookie) and request.headers.get('x-qm-client') != 'web':
                detail = 'Недопустимый запрос'
            else:
                length = request.headers.get('content-length')
                if length and (not length.isdigit() or int(length) > 9 * 1024 * 1024):
                    detail, status = 'Файл слишком большой', 413
            if detail:
                return await JSONResponse({'detail': detail}, status_code=status)(scope, receive, secured_send)
        if not path.startswith('/api/') or path in ('/api/meta', '/api/health', '/api/auth/watch'):
            return await self.app(scope, receive, secured_send)
        loop = asyncio.get_running_loop()
        gate = self.gates.get(loop)
        if gate is None:
            gate = self.gates[loop] = asyncio.Semaphore(10)
        try:
            # Time only admission, never cancel an in-flight database write.
            async with asyncio.timeout(30):
                await gate.acquire()
        except TimeoutError:
            return await JSONResponse({'detail': 'Сервер занят. Повторите запрос'}, status_code=503,
                                      headers={'Retry-After': '2'})(scope, receive, secured_send)
        try:
            await self.app(scope, receive, secured_send)
        finally:
            gate.release()
