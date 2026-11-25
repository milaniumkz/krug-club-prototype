"""Minimal employee spreadsheet, preserving textual personnel numbers."""
import csv
import io
import zipfile
from decimal import Decimal
from pathlib import Path
from xml.etree.ElementTree import ParseError
from openpyxl.utils.exceptions import InvalidFileException
from defusedxml.common import DefusedXmlException
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Font, PatternFill

HEADERS = ['№', 'Фамилия', 'Имя', 'Отчество', 'Табельный номер']
MAX_ROWS = 500


def template_bytes():
    book = Workbook()
    sheet = book.active
    sheet.title = 'Сотрудники'
    example = book.create_sheet('Пример заполнения')
    for ws in (sheet, example):
        ws.append(HEADERS)
        ws.freeze_panes = 'A2'
        ws.auto_filter.ref = 'A1:E101'
        for c, width in zip('ABCDE', [8, 26, 24, 26, 26]):
            ws.column_dimensions[c].width = width
        for cell in ws[1]:
            cell.font = Font(name='Calibri', size=12, bold=True, color='FFFFFF')
            cell.fill = PatternFill('solid', fgColor='6E2EBD')
            cell.alignment = Alignment(vertical='center', wrap_text=True)
        ws.row_dimensions[1].height = 34
        for row in ws.iter_rows(min_row=2, max_row=101, max_col=5):
            for cell in row:
                cell.font = Font(name='Calibri', size=12)
                cell.alignment = Alignment(vertical='center')
                if cell.column == 5:
                    cell.number_format = '@'
            ws.row_dimensions[row[0].row].height = 24
    example.append([])  # formatted blank rows do not become employees
    for index, values in enumerate([(1, 'Иванов', 'Иван', 'Иванович', '01'),
                                    (2, 'Ахметова', 'Айгүл', '', '02')], 2):
        for column, value in enumerate(values, 1):
            example.cell(index, column, value)
    stream = io.BytesIO()
    book.save(stream)
    return stream.getvalue()


def normalize_header(value):
    return ' '.join(str(value or '').strip().lower().replace('ё', 'е').split())


def personnel_value(cell):
    value = cell.value
    if value is None:
        return ''
    if cell.data_type == 'f':
        raise ValueError('Табельный номер должен быть текстом, а не формулой')
    if isinstance(value, (int, float, Decimal)) and not isinstance(value, bool):
        if value != int(value):
            raise ValueError('Табельный номер должен быть текстом или целым числом')
        text = str(int(value))
        if cell.number_format and set(cell.number_format) == {'0'}:
            text = text.zfill(min(len(cell.number_format), 80))
        return text
    return str(value).strip()


def read_members(raw, filename):
    if Path(filename or '').suffix.lower() == '.xlsx':
        try:
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                if sum(f.file_size for f in archive.infolist()) > 32 * 1024 * 1024:
                    raise ValueError('Слишком большой распакованный файл Excel')
            book = load_workbook(io.BytesIO(raw), read_only=True, data_only=False, keep_links=False)
            try:
                sheet = book['Сотрудники'] if 'Сотрудники' in book.sheetnames else book.worksheets[0]
                if sheet.max_row and sheet.max_row > 5000:
                    raise ValueError('Слишком много строк в Excel')
                matrix = []
                for cells in sheet.iter_rows(max_row=5001, max_col=20):
                    if any(c.data_type == 'f' for c in cells):
                        raise ValueError('Используйте значения, а не формулы')
                    matrix.append([personnel_value(c) for c in cells])
            finally:
                book.close()
        except (zipfile.BadZipFile, KeyError, OSError, IndexError, ParseError, InvalidFileException, DefusedXmlException):
            raise ValueError('Нужен корректный файл Excel .xlsx') from None
    else:
        text = raw.decode('utf-8-sig')
        first = text.splitlines()[0] if text.splitlines() else ''
        delimiter = ';' if first.count(';') > first.count(',') else ','
        matrix = list(csv.reader(io.StringIO(text), delimiter=delimiter))
    if not matrix:
        raise ValueError('Файл пуст')
    aliases = {'фамилия': 'last', 'имя': 'first', 'отчество': 'middle',
               'табельный номер': 'employee_number', 'табельный номер сотрудника': 'employee_number',
               'employee_number': 'employee_number', 'name': 'name', 'phone': 'phone'}
    keys = [aliases.get(normalize_header(x), '') for x in matrix[0]]
    if keys.count('employee_number') != 1 or not ('name' in keys or ('last' in keys and 'first' in keys)):
        raise ValueError('Столбцы: №, Фамилия, Имя, Отчество, Табельный номер')
    if any(keys.count(k) > 1 for k in aliases.values()):
        raise ValueError('Заголовки столбцов не должны повторяться')
    rows = []
    for line, values in enumerate(matrix[1:], 2):
        row = {k: str(v or '').strip() for k, v in zip(keys, values) if k}
        if not any(row.values()):
            continue
        if 'name' not in row:
            if not row.get('last') or not row.get('first'):
                raise ValueError(f'Заполните фамилию и имя в строке {line}')
            row['name'] = ' '.join(row.get(k, '') for k in ('last', 'first', 'middle')).strip()
        row['_line'] = line
        rows.append(row)
        if len(rows) > MAX_ROWS:
            raise ValueError('От 1 до 500 работников за одну загрузку')
    if not rows:
        raise ValueError('Заполните лист «Сотрудники»: от 1 до 500 работников')
    return rows
