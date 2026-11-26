def test_map_style_is_local_and_localized_without_remote_style_server(world, monkeypatch):
    import httpx
    from app.main import localized_map_style
    def offline(*args, **kwargs):
        raise AssertionError('No network request allowed to obtain bundled map style')
    monkeypatch.setattr(httpx, 'get', offline)
    localized_map_style.cache_clear()
    client, _, _ = world
    ru = client.get('/api/map-style?lang=ru')
    kk = client.get('/api/map-style?lang=kk')
    assert ru.status_code == kk.status_code == 200
    assert ru.json()['sources']['openmaptiles']['url'] == 'https://tiles.openfreemap.org/planet'
    assert 'sprite' not in ru.json()
    assert all(source['type'] == 'vector' for source in ru.json()['sources'].values())
    assert 'name:ru' in ru.text and 'name:kk' in kk.text
    assert 'name:kk' not in ru.text
    assert client.get('/api/map-style?lang=invalid').status_code == 422


def test_web_executable_resources_revalidate_after_deployment(world):
    client, _, _ = world
    for path in ('/main.dart.js', '/flutter_bootstrap.js', '/manifest.json'):
        assert client.get(path).headers['cache-control'] == 'no-cache'
