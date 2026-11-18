import asyncio
from app.middleware import Protection


def test_streaming_response_and_security_headers_preserve_cookies():
    async def run():
        async def app(scope, receive, send):
            await send({'type':'http.response.start','status':200,'headers':[(b'set-cookie',b'example=value; HttpOnly')]})
            await send({'type':'http.response.body','body':b'first','more_body':True})
            await send({'type':'http.response.body','body':b'second','more_body':False})
        middleware=Protection(app, origin='https://example.org', tile_origin='https://tiles.example.org',production=True,cookie='session')
        messages=[]
        async def send(message):messages.append(message)
        async def receive():return {'type':'http.request','body':b''}
        await middleware({'type':'http','method':'GET','path':'/api/catalog','headers':[], 'scheme':'https','server':('example.org',443),'query_string':b''},receive,send)
        assert [m['body'] for m in messages[1:]]==[b'first',b'second']
        headers=dict(messages[0]['headers'])
        assert headers[b'set-cookie']==b'example=value; HttpOnly'
        assert headers[b'cache-control']==b'no-store'
        assert b'frame-ancestors' in headers[b'content-security-policy']
        assert headers[b'strict-transport-security'].startswith(b'max-age=31536000')
    asyncio.run(run())


def test_cross_origin_write_is_rejected_before_application():
    async def run():
        async def app(*args):raise AssertionError('Rejected write must not reach application')
        middleware=Protection(app,origin='https://example.org',tile_origin='',production=False,cookie='session')
        messages=[]
        async def send(message):messages.append(message)
        async def receive():return {'type':'http.request','body':b''}
        await middleware({'type':'http','method':'POST','path':'/api/scan','headers':[(b'origin',b'https://attacker.example')],'scheme':'https','server':('example.org',443),'query_string':b''},receive,send)
        assert messages[0]['status']==403
        assert dict(messages[0]['headers'])[b'cache-control']==b'no-store'
    asyncio.run(run())
