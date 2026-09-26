import json

import pytest

from rutautp_backend.route_changes import RouteChanges, WINDOW, SNAPSHOT_TOPIC

NOW = 1_790_000_000


def report(route, **updates):
    lat, lon = route.shape[len(route.shape) // 2]
    body = dict(schemaVersion=1, requestId="request-1", routeId=route.route_id,
                reason="works", lat=lat, lon=lon, timestamp=NOW, place="Av. de prueba")
    body.update(updates)
    return json.dumps(body)


def send(service, route, principal="device-1", now=NOW, **updates):
    return service.handle(f"rutautp/cambios/{principal}/reporte",
                          report(route, timestamp=now, **updates), now)


def test_one_account_cannot_confirm_by_repeating(feed, sample_route):
    service = RouteChanges(feed)
    assert send(service, sample_route)[1]["code"] == "pending"
    assert send(service, sample_route, now=NOW+1)[1]["code"] == "rate_limit"
    assert send(service, sample_route, now=NOW+31)[1]["code"] == "pending"
    assert service.snapshot(NOW+31)["alerts"] == []


def test_two_accounts_confirm_and_snapshot_contains_no_identity(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    assert send(service, sample_route, "device-2", NOW+1)[1]["code"] == "confirmed"
    alerts = service.snapshot(NOW+1)["alerts"]
    assert len(alerts) == 1
    assert alerts[0]["confirmations"] == 2
    assert alerts[0]["expiresAt"] == NOW+WINDOW
    assert "device-" not in json.dumps(alerts)
    assert service.snapshot(NOW+WINDOW)["alerts"] == []


def test_third_account_keeps_quorum_until_second_newest_expires(feed, sample_route):
    service = RouteChanges(feed)
    for i in range(3):
        send(service, sample_route, f"device-{i}", NOW+i*60)
    alert = service.snapshot(NOW+WINDOW)["alerts"][0]
    assert alert["confirmations"] == 2
    assert alert["expiresAt"] == NOW+60+WINDOW
    assert service.snapshot(NOW+60+WINDOW)["alerts"] == []


def test_different_reason_does_not_confirm(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    send(service, sample_route, "device-2", reason="closure")
    assert service.snapshot(NOW)["alerts"] == []


def test_distant_points_do_not_confirm(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    lat, lon = sample_route.shape[0]
    send(service, sample_route, "device-2", lat=lat, lon=lon)
    assert service.snapshot(NOW)["alerts"] == []


def test_nearby_points_confirm(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    lat, lon = sample_route.shape[len(sample_route.shape)//2]
    send(service, sample_route, "device-2", lat=lat+0.0001, lon=lon)
    assert len(service.snapshot(NOW)["alerts"]) == 1


@pytest.mark.parametrize("updates", [dict(routeId="missing"), dict(lat=float("nan")),
    dict(lon=181), dict(reason="fake"), dict(place=""), dict(place="x"*121),
    dict(timestamp=NOW-121), dict(timestamp=NOW+11), dict(lat=True), dict(schemaVersion=2)])
def test_invalid_reports_never_count(feed, sample_route, updates):
    service = RouteChanges(feed)
    result = service.handle("rutautp/cambios/device-1/reporte", report(sample_route, **updates), NOW)
    assert result is None or not result[1]["accepted"]
    assert service.groups == []


def test_off_route_rejected(feed, sample_route):
    service = RouteChanges(feed)
    assert send(service, sample_route, lat=0, lon=0)[1]["code"] == "off_route"


def test_expired_votes_cannot_confirm_new_report(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    send(service, sample_route, "device-2", NOW+WINDOW)
    assert service.snapshot(NOW+WINDOW)["alerts"] == []


def test_failed_snapshot_publish_is_retried(feed):
    service = RouteChanges(feed)
    messages = []
    service.publish_snapshot(NOW, lambda *args: False)
    service.publish_snapshot(NOW+1, lambda *args: messages.append(args) or True)
    assert messages[0][0] == SNAPSHOT_TOPIC
    assert json.loads(messages[0][1])["alerts"] == []
    service.publish_snapshot(NOW+2, lambda *args: messages.append(args) or True)
    assert len(messages) == 1


@pytest.mark.parametrize("payload", [b"[]", b"null", b"{", b"x"*2049, b'"text"'])
def test_malformed_payload_does_not_crash(feed, payload):
    assert RouteChanges(feed).handle("rutautp/cambios/device-1/reporte", payload, NOW) is None
