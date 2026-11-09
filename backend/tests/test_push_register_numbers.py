"""F6-H2: el registro push rechaza números JSON que no caben en `float`.

Antes, `math.isfinite` lanzaba `OverflowError` con un entero de cientos de
cifras en `timestamp` o `pauseUntil`. La excepción no estaba en la captura de
`register`, así que el registro quedaba sin recibo. Ahora es un rechazo
ordinario con recibo `invalid`.
"""

import json
from contextlib import closing

import pytest

from rutautp_backend import push_service
from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.push_config import PushConfig

_NOW = 1_800_000_000
_PRINCIPAL = "h2"
_ROUTE = "h2-route"
_TOPIC = f"rutautp/notificaciones/{_PRINCIPAL}/registro"


class _IdleProvider:
    def send(self, _token, _event, _settings):
        return "accepted"

    def close(self):
        pass


def _body(**updates):
    body = {
        "requestID": "00000000-0000-4000-8000-000000000201",
        "deviceID": "00000000-0000-4000-8000-000000000202",
        "revision": 1,
        "schemaVersion": 1,
        "timestamp": _NOW,
        "enabled": True,
        "quietHours": False,
        "sound": True,
        "language": "es",
        "environment": "development",
        "quietStart": 0,
        "quietEnd": 0,
        "timeZone": "UTC",
        "pauseUntil": None,
        "mutedDays": [],
        "routes": [_ROUTE],
        "token": "aa",
    }
    body.update(updates)
    return json.dumps(body).encode()


@pytest.fixture
def service(tmp_path, monkeypatch):
    monkeypatch.setattr(push_service, "APNsProvider", lambda _config: _IdleProvider())
    config = PushConfig(enabled=True, database_path=str(tmp_path / "push.sqlite"))
    feed = GtfsFeed(routes={_ROUTE: RouteGeometry(_ROUTE, "H2", "A", "Prueba", ())})
    with closing(push_service.PushService(config, feed)) as instance:
        yield instance


@pytest.mark.parametrize("field", ["timestamp", "pauseUntil"])
def test_entero_que_no_cabe_en_float_es_invalido(service, field):
    principal, receipt = service.register(_TOPIC, _body(**{field: 10 ** 400}), _NOW)
    assert principal == _PRINCIPAL
    assert receipt["accepted"] is False
    assert receipt["code"] == "invalid"


def test_registro_valido_sigue_guardandose(service):
    principal, receipt = service.register(_TOPIC, _body(), _NOW)
    assert principal == _PRINCIPAL
    assert receipt["accepted"] is True
    assert receipt["code"] == "saved"
