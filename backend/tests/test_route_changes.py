import json
import math
from pathlib import Path

import pytest

from rutautp_backend.desvios import desvios_por_ruta
from rutautp_backend.geo import haversine_m, match_point_to_polyline
from rutautp_backend.route_changes import (
    DEFAULT_QUORUM, MAX_VOTES_PER_PRINCIPAL, RouteChanges, SIMULATED_TTL_S, SNAPSHOT_TOPIC, TTL,
    decode_polyline, encode_polyline, load_simulated,
)

NOW = 1_790_000_000
WORKS = TTL["works"]


def report(route, **updates):
    lat, lon = route.shape[len(route.shape) // 2]
    body = dict(schemaVersion=1, requestId="request-1", routeId=route.route_id,
                reason="works", lat=lat, lon=lon, timestamp=NOW, place="Av. de prueba")
    body.update(updates)
    return json.dumps(body)


def send(service, route, principal="device-1", now=NOW, **updates):
    return service.handle(f"rutautp/cambios/{principal}/reporte",
                          report(route, timestamp=now, **updates), now)


def rejoin_point(route, minimum=60, maximum=4000):
    """Vértice del mismo recorrido a una distancia válida del punto inicial."""
    lat, lon = route.shape[len(route.shape) // 2]
    for point in route.shape[len(route.shape) // 2:]:
        if minimum <= haversine_m(lat, lon, *point) <= maximum:
            return point
    pytest.skip("la ruta de referencia no tiene un tramo utilizable")


def detour(route, end, offset_m, sign=None):
    """Trazo que sale del recorrido, va en paralelo a `offset_m` m y retoma en `end`.

    Devuelve el trazo y el lado elegido, para trazar otro por el mismo lado.
    """
    start = route.shape[len(route.shape) // 2]
    k_lat, k_lon = 110_574, 111_320 * math.cos(math.radians(start[0]))
    dx, dy = (end[1] - start[1]) * k_lon, (end[0] - start[0]) * k_lat
    norm = math.hypot(dx, dy)
    steps = max(2, int(norm // 100))
    options = []
    for side in ((sign,) if sign else (1, -1)):
        points = [(start[0] + (end[0] - start[0]) * i / steps + side * dx / norm * offset_m / k_lat,
                   start[1] + (end[1] - start[1]) * i / steps - side * dy / norm * offset_m / k_lon)
                  for i in range(steps + 1)]
        far = min(match_point_to_polyline(*p, list(route.shape)).distance_m for p in points)
        options.append((far, side, points))
    far, side, points = max(options, key=lambda option: option[0])
    if far < 100:
        pytest.skip("el recorrido de referencia no deja libre un tramo paralelo")
    return [start, *points, end], side


def send_detour(service, route, principal, end, path, now=NOW):
    return send(service, route, principal, now, reason="detour", endLat=end[0], endLon=end[1],
                path=path if isinstance(path, str) else encode_polyline(path))


def test_default_quorum_is_two():
    assert DEFAULT_QUORUM == 2


def test_one_account_cannot_confirm_by_repeating(feed, sample_route):
    service = RouteChanges(feed)
    assert send(service, sample_route)[1]["code"] == "pending"
    assert send(service, sample_route, now=NOW+1)[1]["code"] == "rate_limit"
    assert send(service, sample_route, now=NOW+31)[1]["code"] == "pending"
    assert service.snapshot(NOW+31)["alerts"] == []


def test_one_account_does_not_confirm_with_default_quorum(feed, sample_route):
    service = RouteChanges(feed)
    receipt = send(service, sample_route)[1]
    assert receipt["code"] == "pending"
    assert receipt["confirmations"] == 1 and receipt["required"] == 2
    assert service.snapshot(NOW)["alerts"] == []


def test_two_accounts_confirm_and_snapshot_contains_no_identity(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    receipt = send(service, sample_route, "device-2", NOW+1)[1]
    assert receipt["code"] == "confirmed"
    assert receipt["confirmations"] == 2 and receipt["required"] == 2
    snapshot = service.snapshot(NOW+1)
    assert snapshot["quorum"] == 2
    alerts = snapshot["alerts"]
    assert len(alerts) == 1
    assert alerts[0]["confirmations"] == 2
    assert alerts[0]["expiresAt"] == NOW+WORKS
    assert "device-" not in json.dumps(alerts)
    assert service.snapshot(NOW+WORKS)["alerts"] == []


def test_configured_quorum_of_three_needs_a_third_account(feed, sample_route):
    service = RouteChanges(feed, quorum=3)
    send(service, sample_route)
    receipt = send(service, sample_route, "device-2", NOW+1)[1]
    assert receipt["code"] == "pending"
    assert receipt["confirmations"] == 2 and receipt["required"] == 3
    assert service.snapshot(NOW+1)["alerts"] == []
    assert send(service, sample_route, "device-3", NOW+2)[1]["code"] == "confirmed"
    alerts = service.snapshot(NOW+2)["alerts"]
    assert alerts[0]["confirmations"] == 3
    assert alerts[0]["expiresAt"] == NOW+WORKS


@pytest.mark.parametrize("quorum", [1, 0, True, 2.0, "3"])
def test_quorum_below_two_or_not_integer_is_rejected(feed, quorum):
    with pytest.raises(ValueError):
        RouteChanges(feed, quorum=quorum)


def test_fourth_account_keeps_quorum_until_third_newest_expires(feed, sample_route):
    service = RouteChanges(feed, quorum=3)
    for i in range(4):
        send(service, sample_route, f"device-{i}", NOW+i*60)
    alert = service.snapshot(NOW+WORKS)["alerts"][0]
    assert alert["confirmations"] == 3
    assert alert["expiresAt"] == NOW+60+WORKS
    assert service.snapshot(NOW+60+WORKS)["alerts"] == []


def test_vote_lifetime_depends_on_reason(feed, sample_route):
    service = RouteChanges(feed)
    for i in range(3):
        send(service, sample_route, f"device-{i}", reason="traffic")
    assert service.snapshot(NOW)["alerts"][0]["expiresAt"] == NOW+TTL["traffic"]
    assert TTL["traffic"] < TTL["crash"] < TTL["closure"] <= TTL["works"]
    assert service.snapshot(NOW+TTL["traffic"])["alerts"] == []


def test_renewing_a_vote_extends_the_alert(feed, sample_route):
    service = RouteChanges(feed)
    for i in range(3):
        send(service, sample_route, f"device-{i}")
    for i in range(3):
        send(service, sample_route, f"device-{i}", NOW+3600)
    alert = service.snapshot(NOW+3600)["alerts"][0]
    assert alert["confirmations"] == 3
    assert alert["expiresAt"] == NOW+3600+WORKS


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
    send(service, sample_route, "device-3", lat=lat-0.0001, lon=lon)
    assert len(service.snapshot(NOW)["alerts"]) == 1


def test_road_incidents_confirm_across_lines_but_route_changes_do_not(feed, sample_route):
    lat, lon = sample_route.shape[len(sample_route.shape)//2]
    other = next((route for route in feed.routes_with_geometry()
                  if route.route_id != sample_route.route_id
                  and (match := match_point_to_polyline(lat, lon, list(route.shape), threshold_m=100))
                  and match.is_on_route), None)
    if other is None:
        pytest.skip("ninguna otra ruta del feed pasa por el punto de referencia")
    for reason, expected in (("crash", 1), ("detour", 0)):
        service = RouteChanges(feed)
        send(service, sample_route, reason=reason)
        assert send(service, other, "device-2", reason=reason, lat=lat, lon=lon)[1]["accepted"]
        assert len(service.snapshot(NOW)["alerts"]) == expected


def test_first_report_with_detail_sets_alternate_street_and_stretch(feed, sample_route):
    service = RouteChanges(feed)
    end = rejoin_point(sample_route)
    send(service, sample_route, reason="detour")
    send(service, sample_route, "device-2", reason="detour", via="  Av. Valderrama ",
         endLat=end[0], endLon=end[1])
    send(service, sample_route, "device-3", reason="detour", via="Otra calle")
    alert = service.snapshot(NOW)["alerts"][0]
    assert alert["via"] == "Av. Valderrama"
    assert (alert["endLat"], alert["endLon"]) == end
    assert set(alert) == {"id", "routeId", "reason", "lat", "lon", "place", "via",
                          "endLat", "endLon", "confirmations", "expiresAt"}


def test_alert_without_detail_keeps_original_fields(feed, sample_route):
    service = RouteChanges(feed, quorum=2)
    send(service, sample_route)
    send(service, sample_route, "device-2")
    assert set(service.snapshot(NOW)["alerts"][0]) == {
        "id", "routeId", "reason", "lat", "lon", "place", "confirmations", "expiresAt"}


def test_rejoin_point_off_route_is_rejected(feed, sample_route):
    service = RouteChanges(feed)
    lat, lon = sample_route.shape[len(sample_route.shape)//2]
    # ~1,1 km en perpendicular aproximada: dentro del tramo máximo y fuera de ruta
    # solo si el recorrido no pasa por ahí; se comprueba antes de afirmar.
    end = (lat + 0.01, lon + 0.01)
    match = match_point_to_polyline(*end, list(sample_route.shape), threshold_m=500)
    if match and match.is_on_route:
        pytest.skip("el punto de prueba cae sobre el recorrido de referencia")
    receipt = send(service, sample_route, endLat=end[0], endLon=end[1])[1]
    assert receipt == {"requestId": "request-1", "accepted": False, "code": "off_route"}
    assert service.groups == []


@pytest.mark.parametrize("updates", [dict(routeId="missing"), dict(lat=float("nan")),
    dict(lon=181), dict(reason="fake"), dict(place=""), dict(place="x"*121),
    dict(timestamp=NOW-121), dict(timestamp=NOW+11), dict(lat=True), dict(schemaVersion=2),
    dict(via=""), dict(via="ab"), dict(via="x"*81), dict(via=7),
    dict(endLat=0.0), dict(endLon=0.0), dict(endLat="a", endLon="b"),
    dict(endLat=91, endLon=0), dict(endLat=True, endLon=False),
    dict(endLat=10 ** 400, endLon=0)])
def test_invalid_reports_never_count(feed, sample_route, updates):
    service = RouteChanges(feed)
    result = service.handle("rutautp/cambios/device-1/reporte", report(sample_route, **updates), NOW)
    assert result is None or not result[1]["accepted"]
    assert service.groups == []


@pytest.mark.parametrize("meters", [0, 20, 6000])
def test_rejoin_point_too_close_or_too_far_is_invalid(feed, sample_route, meters):
    service = RouteChanges(feed)
    lat, lon = sample_route.shape[len(sample_route.shape)//2]
    receipt = send(service, sample_route, endLat=lat + meters / 111_320, endLon=lon)[1]
    assert receipt["accepted"] is False and receipt["code"] == "invalid"
    assert service.groups == []


def test_off_route_rejected(feed, sample_route):
    service = RouteChanges(feed)
    assert send(service, sample_route, lat=0, lon=0)[1]["code"] == "off_route"


def test_expired_votes_cannot_confirm_new_report(feed, sample_route):
    service = RouteChanges(feed)
    send(service, sample_route)
    send(service, sample_route, "device-2")
    send(service, sample_route, "device-3", NOW+WORKS)
    assert service.snapshot(NOW+WORKS)["alerts"] == []


def test_one_account_cannot_hold_unlimited_pending_groups(feed, sample_route):
    service = RouteChanges(feed)
    reasons = list(TTL)
    points = [sample_route.shape[0], sample_route.shape[len(sample_route.shape)//2],
              sample_route.shape[-1]]
    sent = 0
    for point in points:
        for reason in reasons:
            receipt = send(service, sample_route, now=NOW+sent*31, reason=reason,
                           lat=point[0], lon=point[1])[1]
            assert receipt["accepted"]
            sent += 1
    assert sent > MAX_VOTES_PER_PRINCIPAL
    held = [g for g in service.groups if "device-1" in g["votes"]]
    assert len(held) <= MAX_VOTES_PER_PRINCIPAL
    assert len(service.groups) == len(held)


def test_push_only_covers_route_changes_not_road_incidents(feed, sample_route):
    service = RouteChanges(feed)
    lat, lon = sample_route.shape[0]
    for i in range(3):
        send(service, sample_route, f"device-{i}", reason="traffic")
    for i in range(3, 6):
        send(service, sample_route, f"device-{i}", reason="detour", lat=lat, lon=lon)
    assert {a["reason"] for a in service.snapshot(NOW)["alerts"]} == {"traffic", "detour"}
    pushed = service.confirmed_for_push(NOW)
    assert [a["reason"] for a in pushed] == ["detour"]
    assert pushed[0]["confirmedAt"] == NOW


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


@pytest.mark.parametrize("field", ["lat", "lon", "timestamp"])
def test_huge_integer_number_is_invalid_and_keeps_quota(feed, sample_route, field):
    """F7 B1: un entero JSON que no cabe en float es un número inválido.

    Antes, `math.isfinite` lanzaba `OverflowError` y la excepción detenía el
    bucle MQTT de Bridge. El rechazo ocurre antes de registrar votos o cuota.
    """
    service = RouteChanges(feed)
    payload = report(sample_route, **{field: 10 ** 400})
    principal, receipt = service.handle("rutautp/cambios/device-1/reporte", payload, NOW)
    assert principal == "device-1"
    assert receipt["accepted"] is False
    assert receipt["code"] == "invalid"
    assert send(service, sample_route)[1]["code"] == "pending"


def test_polyline_matches_reference_example_and_round_trips():
    reference = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
    assert encode_polyline(reference) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    assert decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@") == reference


@pytest.mark.parametrize("text", ["", "?", "_p~iF", "\x00\x00", "_p~iF~ps|U_", "~" * 50,
                                  "x" * 1401, 7, None])
def test_incomplete_or_invalid_polyline_is_rejected(text):
    assert decode_polyline(text) is None


def test_matching_paths_from_two_accounts_publish_the_new_street(feed, sample_route):
    service = RouteChanges(feed)
    end = rejoin_point(sample_route)
    first, side = detour(sample_route, end, 150)
    second, _ = detour(sample_route, end, 160, side)
    assert send_detour(service, sample_route, "device-1", end, first)[1]["code"] == "pending"
    assert send_detour(service, sample_route, "device-2", end, second)[1]["code"] == "confirmed"
    alert = service.snapshot(NOW)["alerts"][0]
    assert alert["path"] == encode_polyline(first)
    assert "paths" not in alert and "device-" not in json.dumps(alert)


def test_lone_or_disagreeing_paths_are_not_published(feed, sample_route):
    end = rejoin_point(sample_route)
    first, side = detour(sample_route, end, 150)
    other_street, _ = detour(sample_route, end, 330, side)
    service = RouteChanges(feed)
    send_detour(service, sample_route, "device-1", end, first)
    send(service, sample_route, "device-2", reason="detour", endLat=end[0], endLon=end[1])
    assert "path" not in service.snapshot(NOW)["alerts"][0]
    service = RouteChanges(feed)
    send_detour(service, sample_route, "device-1", end, first)
    assert send_detour(service, sample_route, "device-2", end, other_street)[1]["code"] == "confirmed"
    assert "path" not in service.snapshot(NOW)["alerts"][0]


def test_expired_vote_takes_its_path_with_it(feed, sample_route):
    service = RouteChanges(feed)
    end = rejoin_point(sample_route)
    first, side = detour(sample_route, end, 150)
    second, _ = detour(sample_route, end, 155, side)
    send_detour(service, sample_route, "device-1", end, first)
    send(service, sample_route, "device-2", NOW + 60, reason="detour")
    send_detour(service, sample_route, "device-3", end, second, now=NOW + TTL["detour"])
    alerts = service.snapshot(NOW + TTL["detour"])["alerts"]
    assert alerts and "path" not in alerts[0]


def test_path_needs_the_rejoin_point(feed, sample_route):
    service = RouteChanges(feed)
    path, _ = detour(sample_route, rejoin_point(sample_route), 150)
    receipt = send(service, sample_route, reason="detour", path=encode_polyline(path))[1]
    assert receipt["accepted"] is False and receipt["code"] == "invalid"
    assert service.groups == []


@pytest.mark.parametrize("reason", ["traffic", "crash"])
def test_road_incident_cannot_carry_a_path(feed, sample_route, reason):
    service = RouteChanges(feed)
    end = rejoin_point(sample_route)
    path, _ = detour(sample_route, end, 150)
    receipt = send(service, sample_route, reason=reason, endLat=end[0], endLon=end[1],
                   path=encode_polyline(path))[1]
    assert receipt["accepted"] is False and receipt["code"] == "invalid"
    assert service.groups == []


@pytest.mark.parametrize("kind", ["far_start", "on_route", "jump", "garbage"])
def test_implausible_path_is_rejected_and_uses_the_quota(feed, sample_route, kind):
    service = RouteChanges(feed)
    end = rejoin_point(sample_route)
    path, _ = detour(sample_route, end, 150)
    start = path[0]
    shape = list(sample_route.shape)
    middle = len(shape) // 2
    broken = {
        "far_start": [(start[0] + 0.002, start[1]), *path[1:]],
        "on_route": [start, *shape[middle + 1:shape.index(end)], end],
        "jump": [start, (start[0] + 0.01, start[1]), end],
        "garbage": "no es una polilínea",
    }[kind]
    receipt = send_detour(service, sample_route, "device-1", end, broken)[1]
    assert receipt["accepted"] is False and receipt["code"] == "invalid_path"
    assert service.groups == []
    assert send(service, sample_route, now=NOW + 1)[1]["code"] == "rate_limit"


PRESENTATION_INCIDENTS = Path(__file__).resolve().parents[1] / "simulation" / "incidencias-presentacion.json"


def write_simulated(tmp_path, *alerts):
    path = tmp_path / "incidencias.json"
    path.write_text(json.dumps({"schemaVersion": 1, "alerts": list(alerts)}), encoding="utf-8")
    return path


def simulated_item(route, **updates):
    lat, lon = route.shape[len(route.shape) // 2]
    item = dict(id="obras-prueba", routeId=route.route_id, reason="works", lat=lat, lon=lon,
                place="Av. de prueba")
    item.update(updates)
    return item


def test_simulated_incidents_are_published_marked_and_renewed(feed, sample_route, tmp_path):
    end = rejoin_point(sample_route)
    path, _ = detour(sample_route, end, 150)
    alerts = load_simulated(write_simulated(
        tmp_path, simulated_item(sample_route),
        simulated_item(sample_route, id="desvio-prueba", reason="detour", endLat=end[0], endLon=end[1],
                       via="Av. Paralela", path=encode_polyline(path))), feed)
    assert [a["id"] for a in alerts] == ["sim-obras-prueba", "sim-desvio-prueba"]
    service = RouteChanges(feed, simulated=alerts)
    for now in (NOW, NOW + 3600):
        published = service.snapshot(now)["alerts"]
        assert len(published) == 2
        assert all(a["simulated"] is True and a["confirmations"] == DEFAULT_QUORUM
                   and a["expiresAt"] == now + SIMULATED_TTL_S for a in published)
    assert published[1]["path"] == encode_polyline(path)
    assert service.confirmed_for_push(NOW) == []


@pytest.mark.parametrize("updates", [dict(routeId="missing"), dict(reason="fake"), dict(lat=0, lon=0),
    dict(place="x"), dict(id="Con Mayúsculas"), dict(lat=True), dict(via="ab"),
    dict(afterS=-1), dict(afterS=True), dict(afterS=1.5), dict(afterS=3601),
    dict(reason="traffic", endLat=0.0, endLon=0.0, path="??")])
def test_invalid_simulated_incidents_are_dropped(feed, sample_route, tmp_path, updates):
    assert load_simulated(write_simulated(tmp_path, simulated_item(sample_route, **updates)), feed) == []


@pytest.mark.parametrize("content", [None, "{", "[]", json.dumps({"schemaVersion": 2, "alerts": []})])
def test_unreadable_simulated_file_publishes_nothing(feed, tmp_path, content):
    path = tmp_path / "incidencias.json"
    if content is not None:
        path.write_text(content, encoding="utf-8")
    assert load_simulated(path, feed) == []


def test_presentation_incidents_stay_valid_with_the_feed(feed):
    # Las reales (obra de Nicolás de Piérola, MPT, noviembre de 2026, sus
    # desvíos oficiales y el desvío de prueba de la M-34 «A», extendido a las
    # líneas que recorren su tramo) salen al arrancar con su calle nueva. Los
    # reportes en vivo de demostración aparecen después, escalonados, y cada
    # línea afectada lleva también su calle nueva.
    items = json.loads(PRESENTATION_INCIDENTS.read_text(encoding="utf-8"))["alerts"]
    alerts = load_simulated(PRESENTATION_INCIDENTS, feed)
    assert len(alerts) == len(items)
    reales = [a for a in alerts if "afterS" not in a]
    en_vivo = [a for a in alerts if "afterS" in a]
    assert {a["reason"] for a in reales} == {"works", "detour"}
    assert all("path" in a for a in reales if a["reason"] == "detour")
    m34 = next(a for a in reales if a["id"] == "sim-desvio-m34a")
    assert sum(a.get("path") == m34["path"] for a in reales) > 1
    assert en_vivo and all(a["id"].startswith("sim-vivo-") and "path" in a for a in en_vivo)
    # Las líneas de un mismo reporte aparecen a la vez.
    demoras = {}
    for alert in en_vivo:
        demoras.setdefault(alert["id"].rsplit("-", 1)[0], set()).add(alert["afterS"])
    assert len(demoras) > 1 and all(len(d) == 1 for d in demoras.values())
    # Cada calle nueva, también la de un cierre u obra, es un recorrido válido
    # para los micros simulados de su línea.
    desvios = desvios_por_ruta(alerts, feed)
    assert ({d.alert_id for ds in desvios.values() for d in ds}
            == {a["id"] for a in alerts if "path" in a})


def test_delayed_simulated_incidents_appear_after_their_delay(feed, sample_route, tmp_path):
    alerts = load_simulated(write_simulated(
        tmp_path, simulated_item(sample_route), simulated_item(sample_route, id="vivo-prueba", afterS=60)), feed)
    service = RouteChanges(feed, simulated=alerts)
    assert [a["id"] for a in service.snapshot(NOW)["alerts"]] == ["sim-obras-prueba"]
    assert [a["id"] for a in service.snapshot(NOW + 59)["alerts"]] == ["sim-obras-prueba"]
    published = service.snapshot(NOW + 60)["alerts"]
    assert [a["id"] for a in published] == ["sim-obras-prueba", "sim-vivo-prueba"]
    assert all("afterS" not in a for a in published)
