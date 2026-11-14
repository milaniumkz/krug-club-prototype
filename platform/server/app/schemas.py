import re
from datetime import date
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Login(Strict):
    identifier: str = Field(min_length=1, max_length=160)
    password: str = Field(min_length=1, max_length=256)
    organization_code: str = Field(default='', max_length=40)


class Password(Strict):
    old_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=12, max_length=128)


class OrganizationIn(Strict):
    code: str = Field(pattern=r'^[A-Za-z0-9_-]{2,40}$')
    name: str = Field(min_length=2, max_length=240)
    active: bool = True


class AccountIn(Strict):
    name: str = Field(min_length=2, max_length=240)
    role: Literal['member', 'partner', 'admin'] = 'member'
    username: str | None = Field(default=None, max_length=160)
    organization_id: str | None = None
    partner_id: str | None = None
    employee_number: str | None = Field(default=None, max_length=80)
    phone: str | None = Field(default=None, max_length=20)
    member_until: date | None = None

    @model_validator(mode='after')
    def check_account(self):
        if self.role == 'member' and (not self.organization_id or not self.employee_number):
            raise ValueError('Для участника нужны организация и табельный номер')
        if self.role == 'partner' and not self.partner_id:
            raise ValueError('Нужен партнёр')
        if self.role != 'member' and not self.username:
            raise ValueError('Нужен логин')
        if self.phone and not re.fullmatch(r'\+7\d{10}', self.phone):
            raise ValueError('Телефон: +7 и 10 цифр')
        return self


class StatusIn(Strict):
    status: Literal['active', 'blocked', 'dismissed']
    reason: str = Field(min_length=3, max_length=1000)


class ResourceData(Strict):
    name: str = Field(min_length=2, max_length=240)
    description: str = Field(default='', max_length=4000)
    category: str = Field(default='', max_length=80)
    address: str = Field(default='', max_length=500)
    phone: str = Field(default='', max_length=30)
    hours: str = Field(default='', max_length=240)
    image: str = Field(default='', max_length=160)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    percent: int | None = Field(default=None, ge=1, le=100)
    terms: str = Field(default='', max_length=4000)
    starts_on: date | None = None
    ends_on: date | None = None
    organization_ids: list[str] = Field(default_factory=list, max_length=100)

    @model_validator(mode='after')
    def check_fields(self):
        if self.starts_on and self.ends_on and self.ends_on < self.starts_on:
            raise ValueError('Дата окончания раньше начала')
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError('Нужны обе координаты')
        if self.image and not re.fullmatch(r'/media/[a-f0-9]{32}\.webp', self.image):
            raise ValueError('Выберите загруженное изображение')
        return self


class ResourceIn(Strict):
    kind: Literal['venue', 'offer', 'banner']
    partner_id: str | None = None
    venue_id: str | None = None
    data: ResourceData


class RevisionIn(Strict):
    action: Literal['publish', 'delete'] = 'publish'
    data: ResourceData


class ReviewIn(Strict):
    decision: Literal['approve', 'reject']
    reason: str = Field(default='', max_length=1000)


class ScanIn(Strict):
    code: str = Field(min_length=1, max_length=256)
    request_id: str = Field(pattern=r'^[a-fA-F0-9-]{36}$')


class TicketIn(Strict):
    subject: str = Field(min_length=3, max_length=240)
    message: str = Field(min_length=3, max_length=4000)


class ReplyIn(Strict):
    status: Literal['open', 'in_progress', 'closed']
    reply: str = Field(min_length=1, max_length=4000)


class PartnerIn(Strict):
    name: str = Field(min_length=2, max_length=240)
    active: bool = True


class ToggleIn(Strict):
    enabled: bool
    reason: str = Field(min_length=3, max_length=1000)
