"""E16: la continuidad usa la observación aceptada de mayor timestamp.

La recta norte y los metros sobre una esfera fijan posiciones reproducibles.
Se ejercita la validación pública y el puente con reloj explícito, publicador
en memoria y SQLite temporal; nunca el broker ni datos de la instalación.
Los mensajes atrasados válidos siguen aceptándose y guardándose como tales.
"""

from __future__ import annotations

import json
import math
from dataclasses import replace

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.geo import EARTH_RADIUS_M
from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.models import RejectReason
from rutautp_backend.persistence import ObservationStore
from rutautp_backend.validation import ObservationValidator

from .conftest import vehicle_id
from .test_bridge import CapturingPublisher, topic_for

NOW = 1_700_000_000.0
ROUTE_ID = "e16-norte"
LONGITUDE = -79.006
ORIGIN_LATITUDE = -8.115


@pytest.fixture
def continuity_feed() -> GtfsFeed:
    route = RouteGeometry(
        route_id=ROUTE_ID,
        linea="E-16",
        variante="",
        empresa="Prueba aislada",
        shape=((-8.12, LONGITUDE), (-8.06, LONGITUDE)),
    )
    return GtfsFeed(routes={ROUTE_ID: route})


def latitude_at(meters: float) -> float:
    return ORIGIN_LATITUDE + math.degrees(meters / EARTH_RADIUS_M)


def payload(meters: float, timestamp: float, *, session: str = "e16", **extra) -> str:
    body = {
        "schemaVersion": 1,
        "sessionId": session,
        "routeId": ROUTE_ID,
        "linea": "E-16",
        "lat": latitude_at(meters),
        "lon": LONGITUDE,
        "speed": 8.0,
        "heading": 0.0,
        "accuracy": 8.0,
        "motionActivity": "automotive",
        "timestamp": timestamp,
    }
    body.update(extra)
    return json.dumps(body)


def send(validator, meters, timestamp, *, now=NOW, session="e16", **extra):
    return validator.validate(payload(meters, timestamp, session=session, **extra), now)


@pytest.mark.parametrize("delayed_meters", [0.0, 4_500.0])
def test_atrasado_no_provoca_falso_rechazo_de_movimiento_legitimo(
    continuity_feed, config, delayed_meters
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 2_000, NOW).ok
    assert send(validator, delayed_meters, NOW - 10, now=NOW + 1).ok

    following = send(validator, 2_020, NOW + 1, now=NOW + 2)

    assert following.ok
    assert following.observation.timestamp == NOW + 1
    assert following.observation.lat == pytest.approx(latitude_at(2_020))


@pytest.mark.parametrize("delay_s", [1.0, 10.0, 40.0])
def test_atrasado_no_permite_un_salto_imposible_desde_la_ultima_medida(
    continuity_feed, config, delay_s
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 0, NOW).ok
    assert send(validator, 2_000, NOW - delay_s, now=NOW + 1).ok

    following = send(validator, 2_000, NOW + 1, now=NOW + 2)

    assert following.ok is False
    assert following.reason is RejectReason.IMPLAUSIBLE_JUMP
    assert following.observation is None


def test_varios_atrasados_no_sustituyen_la_referencia_mas_reciente(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 2_000, NOW).ok
    for delay_s, meters in [(5, 4_000), (10, 0), (20, 4_500)]:
        assert send(validator, meters, NOW - delay_s, now=NOW + 1).ok

    assert send(validator, 2_020, NOW + 1, now=NOW + 2).ok


def test_duplicado_con_otras_coordenadas_no_altera_la_trayectoria(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 2_000, NOW).ok
    duplicate = send(validator, 0, NOW, now=NOW + 1)
    assert duplicate.reason is RejectReason.DUPLICATE
    assert send(validator, 2_020, NOW + 1, now=NOW + 2).ok


@pytest.mark.parametrize(
    "latest_meters,replayed_meters,next_meters,accepted",
    [(2_000, 0, 2_020, True), (0, 2_000, 2_000, False)],
)
def test_igual_timestamp_tras_caducar_dedupe_no_cambia_las_coordenadas_base(
    continuity_feed, config, latest_meters, replayed_meters, next_meters, accepted
):
    validator = ObservationValidator(continuity_feed, replace(config, dedupe_window_s=5))
    assert send(validator, latest_meters, NOW).ok
    # A los seis segundos la repetición ya no es un duplicado. Sigue siendo
    # válida, pero no es una medida posterior a la referencia de continuidad.
    replay = send(validator, replayed_meters, NOW, now=NOW + 6)
    assert replay.ok
    following = send(validator, next_meters, NOW + 1, now=NOW + 7)
    assert following.ok is accepted
    if not accepted:
        assert following.reason is RejectReason.IMPLAUSIBLE_JUMP


def test_cada_sesion_conserva_su_propia_referencia(continuity_feed, config):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 0, NOW, session="a").ok
    assert send(validator, 2_000, NOW, session="b").ok
    assert send(validator, 4_000, NOW - 10, now=NOW + 1, session="a").ok

    assert send(validator, 2_020, NOW + 1, now=NOW + 2, session="b").ok
    assert send(validator, 20, NOW + 1, now=NOW + 2, session="a").ok
    assert validator.tracked_continuity_sessions == 2


def test_salto_rechazado_no_avanza_referencia_ni_consume_el_timestamp(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 0, NOW).ok
    rejected = send(validator, 800, NOW + 1, now=NOW + 1)
    assert rejected.reason is RejectReason.IMPLAUSIBLE_JUMP

    assert send(validator, 20, NOW + 1, now=NOW + 2).ok
    assert send(validator, 40, NOW + 2, now=NOW + 3).ok


def test_medida_rechazada_por_precision_no_avanza_referencia(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 0, NOW).ok
    rejected = send(validator, 800, NOW + 1, now=NOW + 1, accuracy=100)
    assert rejected.reason is RejectReason.BAD_ACCURACY
    assert send(validator, 20, NOW + 1, now=NOW + 2).ok


@pytest.mark.parametrize("direction", [-1.0, 1.0])
@pytest.mark.parametrize("distance,accepted", [(39.99, True), (40.01, False)])
def test_umbral_de_salto_se_aplica_a_la_medida_reciente_en_ambos_lados(
    continuity_feed, config, direction, distance, accepted
):
    # Techo: 10 m/s * 1 s + 10 m de precisión + 20 m de margen = 40 m.
    constrained = replace(
        config, max_speed_ms=10, max_accuracy_m=10, max_displacement_margin_m=20
    )
    validator = ObservationValidator(continuity_feed, constrained)
    assert send(validator, 2_000, NOW).ok
    assert send(validator, 4_000, NOW - 10, now=NOW + 1).ok

    following = send(validator, 2_000 + direction * distance, NOW + 1, now=NOW + 2)

    assert following.ok is accepted
    if not accepted:
        assert following.reason is RejectReason.IMPLAUSIBLE_JUMP


def test_poda_no_caduca_la_sesion_por_timestamp_de_un_atrasado(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, replace(config, dedupe_window_s=20))
    assert send(validator, 0, NOW).ok
    assert send(validator, 2_000, NOW - 15, now=NOW + 1).ok
    validator.prune(NOW + 10)

    following = send(validator, 2_000, NOW + 11, now=NOW + 11)
    assert following.reason is RejectReason.IMPLAUSIBLE_JUMP
    assert validator.tracked_continuity_sessions == 1


def test_poda_conserva_la_referencia_en_el_limite_exacto_de_su_ventana(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, replace(config, dedupe_window_s=20))
    assert send(validator, 0, NOW).ok
    assert send(validator, 2_000, NOW - 1, now=NOW + 1).ok
    validator.prune(NOW + 20)

    assert send(validator, 2_000, NOW + 21, now=NOW + 21).reason is RejectReason.IMPLAUSIBLE_JUMP
    assert validator.tracked_continuity_sessions == 1


def test_poda_caducada_permite_iniciar_otra_trayectoria(continuity_feed, config):
    validator = ObservationValidator(continuity_feed, replace(config, dedupe_window_s=20))
    assert send(validator, 0, NOW).ok
    assert send(validator, 2_000, NOW - 15, now=NOW + 1).ok
    validator.prune(NOW + 20.001)

    assert validator.tracked_continuity_sessions == 0
    restarted = send(validator, 2_000, NOW + 21, now=NOW + 21)
    assert restarted.ok
    assert validator.tracked_continuity_sessions == 1


def test_atrasado_demasiado_antiguo_se_rechaza_sin_alterar_continuidad(
    continuity_feed, config
):
    validator = ObservationValidator(continuity_feed, config)
    assert send(validator, 0, NOW).ok
    assert send(validator, 2_000, NOW - 46, now=NOW + 1).reason is RejectReason.STALE_TIMESTAMP
    assert send(validator, 20, NOW + 1, now=NOW + 2).ok


def bridge_send(bridge, meters, timestamp, *, now, session="e16", principal="cuenta-a"):
    return bridge.handle_message(
        topic_for(session=session, principal=principal),
        payload(meters, timestamp, session=session),
        now,
    )


def test_puente_salto_rechazado_no_contamina_posicion_historial_identidad_ni_quorum(
    continuity_feed, config, tmp_path
):
    publisher = CapturingPublisher()
    store = ObservationStore(tmp_path / "e16.sqlite")
    try:
        bridge = Bridge(
            config=replace(config, min_publish_principals=2),
            feed=continuity_feed,
            publisher=publisher,
            store=store,
        )
        first = bridge_send(bridge, 0, NOW, now=NOW)
        second = bridge_send(
            bridge, 0, NOW + 1, now=NOW + 1, session="corrobora", principal="cuenta-b"
        )
        delayed = bridge_send(bridge, 800, NOW - 10, now=NOW + 2)
        expected_id = vehicle_id(ROUTE_ID, 1)
        assert first.accepted and first.created_vehicle and not first.published
        assert second.accepted and second.published and not second.created_vehicle
        assert delayed.accepted and not delayed.created_vehicle and not delayed.published
        assert first.vehicle_id == second.vehicle_id == delayed.vehicle_id == expected_id
        assert publisher.count == 1
        vehicle = bridge.aggregator.snapshot()[0]
        assert vehicle.lat == pytest.approx(latitude_at(0))
        assert vehicle.timestamp == vehicle.last_seen == NOW + 1
        assert vehicle.principals == {"cuenta-a": NOW, "cuenta-b": NOW + 1}
        before = (dict(vehicle.to_vehicle_position()), vehicle.sample_count, dict(vehicle.principals))

        rejected = bridge_send(bridge, 800, NOW + 2, now=NOW + 3)

        assert rejected.accepted is False
        assert rejected.reason is RejectReason.IMPLAUSIBLE_JUMP
        assert bridge.aggregator.vehicle_count == 1
        assert (vehicle.to_vehicle_position(), vehicle.sample_count, vehicle.principals) == before
        assert publisher.count == 1
        assert len(store.query("SELECT * FROM observations")) == 3
        assert len(store.query("SELECT * FROM vehicle_positions")) == 1

        # Rechazar no consume la clave de deduplicación. La lectura corregida
        # con el mismo timestamp debe conservar la unidad y poder publicarse.
        recovered = bridge_send(bridge, 20, NOW + 2, now=NOW + 7)
        assert recovered.accepted and recovered.published and not recovered.created_vehicle
        assert recovered.vehicle_id == expected_id
        assert publisher.count == 2
        assert publisher.last()["vehicleId"] == expected_id
        assert publisher.last()["timestamp"] == NOW + 2
        assert publisher.last()["lat"] == pytest.approx(latitude_at(20))
        assert vehicle.principals == {"cuenta-a": NOW + 2, "cuenta-b": NOW + 1}

        observations = store.query(
            "SELECT observed_at, lat, vehicle_id FROM observations ORDER BY id"
        )
        assert observations == [
            (NOW, latitude_at(0), expected_id),
            (NOW + 1, latitude_at(0), expected_id),
            (NOW - 10, latitude_at(800), expected_id),
            (NOW + 2, latitude_at(20), expected_id),
        ]
        assert store.query(
            "SELECT observed_at, lat, vehicle_id FROM vehicle_positions ORDER BY id"
        ) == [
            (NOW + 1, latitude_at(0), expected_id),
            (NOW + 2, latitude_at(20), expected_id),
        ]
        assert store.query("SELECT reason FROM rejections") == [(RejectReason.IMPLAUSIBLE_JUMP.value,)]
        assert store.counts.write_errors == 0
    finally:
        store.close()


def test_puente_movimiento_legitimo_tras_atrasado_conserva_unidad_y_publicacion(
    continuity_feed, config, tmp_path
):
    publisher = CapturingPublisher()
    store = ObservationStore(tmp_path / "e16-legitimo.sqlite")
    try:
        bridge = Bridge(config=config, feed=continuity_feed, publisher=publisher, store=store)
        first = bridge_send(bridge, 2_000, NOW, now=NOW)
        delayed = bridge_send(bridge, 0, NOW - 10, now=NOW + 1)
        assert first.published and delayed.accepted and not delayed.published
        assert publisher.last()["lat"] == pytest.approx(latitude_at(2_000))

        following = bridge_send(bridge, 2_020, NOW + 1, now=NOW + 6)

        assert following.accepted and following.published and not following.created_vehicle
        assert first.vehicle_id == delayed.vehicle_id == following.vehicle_id == vehicle_id(ROUTE_ID, 1)
        assert bridge.aggregator.vehicle_count == 1
        assert publisher.count == 2
        assert publisher.last()["lat"] == pytest.approx(latitude_at(2_020))
        assert publisher.last()["timestamp"] == NOW + 1
        assert len(store.query("SELECT * FROM observations")) == 3
        assert len(store.query("SELECT * FROM vehicle_positions")) == 2
        assert store.query("SELECT * FROM rejections") == []
    finally:
        store.close()


def test_atrasado_de_otra_sesion_lejana_sigue_pudiendo_crear_otra_unidad(
    continuity_feed, config
):
    # E16 no cambia la asociación por proximidad del agregador. Una primera
    # lectura de otra sesión no tiene referencia propia y puede crear unidad.
    bridge = Bridge(config=config, feed=continuity_feed, publisher=CapturingPublisher())
    first = bridge_send(bridge, 0, NOW, now=NOW)
    delayed = bridge_send(bridge, 1_000, NOW - 10, now=NOW + 1, session="otra")
    following = bridge_send(bridge, 20, NOW + 1, now=NOW + 6)

    assert first.accepted and delayed.accepted and following.accepted
    assert delayed.created_vehicle and delayed.vehicle_id == vehicle_id(ROUTE_ID, 2)
    assert first.vehicle_id == following.vehicle_id == vehicle_id(ROUTE_ID, 1)
    assert bridge.aggregator.vehicle_count == 2


def test_atrasado_no_alarga_la_vida_del_vehiculo(continuity_feed, config):
    bridge = Bridge(config=config, feed=continuity_feed, publisher=CapturingPublisher())
    first = bridge_send(bridge, 0, NOW, now=NOW)
    delayed = bridge_send(bridge, 0, NOW - 10, now=NOW + 30)
    assert first.accepted and delayed.accepted
    assert first.vehicle_id == delayed.vehicle_id

    assert bridge.aggregator.expire(NOW + config.vehicle_ttl_s) == []
    assert bridge.aggregator.expire(NOW + config.vehicle_ttl_s + 0.001) == [first.vehicle_id]
    assert bridge.aggregator.vehicle_count == 0
