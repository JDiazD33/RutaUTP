"""El reintento de un envío en curso depende de su inscripción."""

import json
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from threading import Event
from types import SimpleNamespace

import pytest

from rutautp_backend import push_service
from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.push_config import PushConfig


_PRINCIPAL = "p17"
_DEVICE = "00000000-0000-4000-8000-000000000001"
_ROUTE = "p17-route"
_EVENT = "p17-event"
_TOKEN_A = "aa"
_TOKEN_B = "bb"
_TIMEOUT = 10


class _BlockingProvider:
    def __init__(self):
        self.entered = Event()
        self.release = Event()
        self.calls = []

    def send(self, token, event, _settings):
        self.calls.append((token, event["id"], event["deliveryID"]))
        if len(self.calls) == 1:
            self.entered.set()
            if not self.release.wait(timeout=_TIMEOUT):
                raise TimeoutError("No se liberó el primer envío")
            return "retry"
        return "accepted"

    def close(self):
        pass


def _register(service, token, revision, now):
    body = {
        "requestID": f"00000000-0000-4000-8000-{revision + 100:012d}",
        "deviceID": _DEVICE,
        "revision": revision,
        "schemaVersion": 1,
        "timestamp": now,
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
        "token": token,
    }
    result = service.register(
        f"rutautp/notificaciones/{_PRINCIPAL}/registro", json.dumps(body).encode(), now,
    )
    assert result is not None
    principal, receipt = result
    assert principal == _PRINCIPAL
    assert receipt["revision"] == revision
    assert receipt["accepted"] is True
    assert receipt["code"] == "saved"
    return receipt["leaseUntil"]


def _delivery(service):
    with service.lock:
        return service.db.execute(
            "SELECT state,due,attempts FROM deliveries WHERE principal=? AND device=? AND event=?",
            (_PRINCIPAL, _DEVICE, _EVENT),
        ).fetchone()


@pytest.mark.parametrize(
    "tokens, requeue",
    [
        pytest.param((_TOKEN_B,), False, id="rotacion"),
        pytest.param((_TOKEN_B, _TOKEN_A), False, id="rotacion-restaurada-mismo-reloj"),
        pytest.param((_TOKEN_A,), True, id="renovacion-equivalente"),
    ],
)
def test_retry_pertenece_a_la_inscripcion_reclamada(tmp_path, monkeypatch, tokens, requeue):
    now = 1_800_000_000
    provider = _BlockingProvider()
    monkeypatch.setattr(push_service, "APNsProvider", lambda _config: provider)
    monkeypatch.setattr(push_service, "time", SimpleNamespace(time=lambda: now))
    config = PushConfig(enabled=True, database_path=str(tmp_path / "push.sqlite"))
    feed = GtfsFeed(routes={_ROUTE: RouteGeometry(_ROUTE, "P17", "A", "Prueba", ())})

    with closing(push_service.PushService(config, feed)) as service:
        first_lease = _register(service, _TOKEN_A, revision=1, now=now - 10)
        service.observe([{
            "id": _EVENT, "routeId": _ROUTE, "confirmedAt": now - 1, "expiresAt": now + 300,
        }], now)

        with ThreadPoolExecutor(max_workers=1) as executor:
            attempt = executor.submit(service._send_one)
            try:
                assert provider.entered.wait(timeout=_TIMEOUT), "El proveedor no recibió el primer envío"
                assert _delivery(service) == ("sending", now, 1)
                assert len(provider.calls) == 1
                assert provider.calls[0][:2] == (_TOKEN_A, _EVENT)
                # Las dos rotaciones del caso A→B→A usan el mismo reloj.
                for revision, token in enumerate(tokens, start=2):
                    assert _register(service, token, revision, now) > first_lease
            finally:
                provider.release.set()
            assert attempt.result(timeout=_TIMEOUT) is True

        first_call = provider.calls[0]
        reconciled = _delivery(service)
        # El intento siguiente ya sería elegible por backoff.
        now += 30
        processed = service._send_one()
        if requeue:
            assert provider.calls == [first_call, first_call]
            assert processed is True
            assert reconciled == ("pending", now, 1)
            assert _delivery(service) == ("accepted", now + 60, 2)
        else:
            assert provider.calls == [first_call]
            assert processed is False
            assert reconciled == ("retry", now, 1)
            assert _delivery(service) == reconciled
