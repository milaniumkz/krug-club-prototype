import io
from openpyxl import load_workbook
from PIL import Image
from conftest import login


def filled_template(client, admin, values):
    response = client.get('/api/admin/accounts/import-template', headers=admin)
    assert response.status_code == 200
    book = load_workbook(io.BytesIO(response.content))
    assert list(next(book['Сотрудники'].values)) == ['№', 'Фамилия', 'Имя', 'Отчество', 'Табельный номер']
    for row, cells in enumerate(values, 2):
        for col, value in enumerate(cells, 1):
            book['Сотрудники'].cell(row, col, value)
    stream = io.BytesIO()
    book.save(stream)
    return stream.getvalue()


def test_excel_template_minimal_data_preserves_zeroes_and_optional_patronymic(world):
    c, _, ids = world
    admin = login(c, 'admin')
    body = filled_template(c, admin, [(1, 'Иванов', 'Иван', 'Иванович', '0007'),
                                     (2, 'Ахметова', 'Айгүл', '', '02')])
    response = c.post('/api/admin/accounts/import', headers=admin, params={'organization_id': ids['org']},
                      files={'file': ('Сотрудники.xlsx', body)})
    assert response.status_code == 200, response.text
    assert response.json()['count'] == 2
    assert [r['employee_number'] for r in response.json()['credentials']] == ['0007', '02']
    people = c.get('/api/admin/accounts?q=0007', headers=admin).json()['items']
    assert len(people) == 1 and people[0]['name'] == 'Иванов Иван Иванович'
    assert not people[0]['phone']
    assert c.get('/api/admin/accounts/import-template', headers=login(c, '1001')).status_code == 403


def test_russian_csv_duplicate_and_formula_excel_fail_atomically(world):
    c, _, ids = world
    admin = login(c, 'admin')
    csv = '№;Фамилия;Имя;Отчество;Табельный номер\n1;Петров;Петр;;003\n2;Сидоров;Иван;;003\n'
    assert c.post('/api/admin/accounts/import', headers=admin, params={'organization_id': ids['org']},
                  files={'file': ('test.csv', csv.encode('utf-8-sig'))}).status_code == 422
    assert c.get('/api/admin/accounts?q=003', headers=admin).json()['total'] == 0
    csv = '№;Фамилия;Имя;Отчество;Табельный номер\n1;Петров;Петр;;003\n'
    assert c.post('/api/admin/accounts/import', headers=admin, params={'organization_id': ids['org']},
                  files={'file': ('test.csv', csv.encode('utf-8-sig'))}).status_code == 200
    formula = filled_template(c, admin, [(1, 'Иванов', 'Иван', '', '=1+1')])
    assert c.post('/api/admin/accounts/import', headers=admin, params={'organization_id': ids['org']},
                  files={'file': ('test.xlsx', formula)}).status_code == 422
    assert c.post('/api/admin/accounts/import', headers=admin, params={'organization_id': ids['org']},
                  files={'file': ('broken.xlsx', b'not an excel document')}).status_code == 422


def test_profile_photo_upload_persists_only_own_photo_and_delete(world):
    c, _, _ = world
    member = login(c, '1001')
    admin = login(c, 'admin')
    before = c.get('/api/auth/me', headers=member).json()
    stream = io.BytesIO()
    Image.new('RGB', (900, 1200), '#8866bb').save(stream, 'JPEG')
    response = c.post('/api/me/avatar', headers=member, files={'file': ('portrait.jpg', stream.getvalue())})
    assert response.status_code == 201, response.text
    path = response.json()['avatar_path']
    persisted = c.get('/api/auth/me', headers=member).json()
    assert persisted['avatar_path'] == path and persisted['name'] == before['name']
    assert persisted['organization_name'] == before['organization_name']
    assert c.get('/api/auth/me', headers=admin).json()['avatar_path'] is None
    saved = c.get(path, headers=member)
    assert saved.status_code == 200
    with Image.open(io.BytesIO(saved.content)) as image:
        assert image.format == 'WEBP' and max(image.size) <= 640
        assert not image.getexif()
    assert c.get(path).status_code == 401
    assert c.post('/api/me/avatar', headers=member, files={'file': ('bad.svg', b'<svg/>')}).status_code == 422
    assert c.get('/api/auth/me', headers=member).json()['avatar_path'] == path
    assert c.delete('/api/me/avatar', headers=member).status_code == 200
    assert c.get('/api/auth/me', headers=member).json()['avatar_path'] is None
