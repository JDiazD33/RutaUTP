"""E17: los identificadores aceptados deben ser los mismos de principio a fin.

No se corrige el JSON silenciosamente: el espacio marginal de sesión, ruta o
línea se rechaza, y cuerpo/tópico deben coincidir exactamente. El principal
MQTT se conserva tal cual. Feed, reloj, publicador y SQLite son aislados; estas
pruebas no conectan a un broker ni usan configuración o datos de la instalación.
"""

from __future__ import annotations

import json
from dataclasses import replace

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.models import RejectReason
from rutautp_backend.persistence import ObservationStore
from rutautp_backend.validation import ObservationValidator

from .conftest import vehicle_id
from .test_bridge import CapturingPublisher, topic_for

NOW = 1_700_000_000.0
ROUTE_ID = "e17-norte"
LINE = "E 17"
NON_CANONICAL = "non_canonical_identifier"


@pytest.fixture
def identifier_feed() -> GtfsFeed:
    route = RouteGeometry(
        route_id=ROUTE_ID,
        linea=LINE,
        variante="",
        empresa="Prueba aislada",
        shape=((-8.11, -79.006), (-8.08, -79.006)),
    )
    return GtfsFeed(routes={ROUTE_ID: route})


def body(**overrides) -> dict:
    value = {
        "schemaVersion": 1,
        "sessionId": "e17",
        "routeId": ROUTE_ID,
        "linea": LINE,
        "lat": -8.105,
        "lon": -79.006,
        "speed": 8.0,
        "heading": 0.0,
        "accuracy": 8.0,
        "motionActivity": "automotive",
        "timestamp": NOW,
    }
    value.update(overrides)
    return value


def encoded(**overrides) -> str:
    return json.dumps(body(**overrides), ensure_ascii=False)


@pytest.mark.parametrize("field", ["sessionId", "routeId", "linea"])
@pytest.mark.parametrize(
    "left,right", [(" ", " "), ("\t", ""), ("", "\n"), ("\u00a0", "\u00a0")]
)
def test_validador_rechaza_padding_sin_crear_referencia_ni_consumir_dedupe(
    identifier_feed, config, field, left, right
):
    validator = ObservationValidator(identifier_feed, config)
    invalid = body()
    invalid[field] = left + invalid[field] + right

    rejected = validator.validate(json.dumps(invalid), NOW)

    assert not rejected.ok
    assert rejected.observation is None
    assert rejected.reason is not None
    assert rejected.reason.value == NON_CANONICAL
    assert validator.tracked_continuity_sessions == 0
    assert validator.deduplicator.tracked_keys == 0
    # Corregir solo el identificador permite aceptar el mismo instante.
    assert validator.validate(encoded(), NOW).ok


@pytest.mark.parametrize(
    "body_session,topic_session",
    [(" e17", "e17"), ("e17 ", "e17"), ("e17", " e17"), (" e17", "e17 ")],
)
def test_puente_no_autoriza_igualdad_obtenida_con_strip(
    identifier_feed, config, body_session, topic_session
):
    publisher = CapturingPublisher()
    bridge = Bridge(config=config, feed=identifier_feed, publisher=publisher)

    rejected = bridge.handle_message(
        topic_for(session=topic_session), encoded(sessionId=body_session), NOW
    )

    assert not rejected.accepted
    assert rejected.reason is RejectReason.SESSION_MISMATCH
    assert bridge.aggregator.vehicle_count == 0
    assert bridge.validator.tracked_continuity_sessions == 0
    assert bridge.validator.deduplicator.tracked_keys == 0
    assert publisher.count == 0


@pytest.mark.parametrize("session", [" e17 ", "\u00a0e17\u00a0"])
def test_sesion_padded_igual_en_cuerpo_y_topico_tambien_se_rechaza(
    identifier_feed, config, session
):
    bridge = Bridge(config=config, feed=identifier_feed, publisher=CapturingPublisher())

    rejected = bridge.handle_message(topic_for(session=session), encoded(sessionId=session), NOW)

    assert not rejected.accepted
    assert rejected.reason is not None
    assert rejected.reason.value == NON_CANONICAL
    assert bridge.aggregator.vehicle_count == 0
    assert bridge.validator.deduplicator.tracked_keys == 0


@pytest.mark.parametrize("field", ["sessionId", "routeId", "linea"])
def test_rechazo_no_altera_unidad_historial_quorum_y_admite_corregido_mismo_instante(
    identifier_feed, config, tmp_path, field
):
    publisher = CapturingPublisher()
    store = ObservationStore(tmp_path / "e17.sqlite")
    try:
        bridge = Bridge(
            config=replace(config, min_publish_principals=2),
            feed=identifier_feed,
            publisher=publisher,
            store=store,
        )
        initial = bridge.handle_message(topic_for(session="e17", principal="cuenta-a"), encoded(), NOW)
        assert initial.accepted and initial.created_vehicle and not initial.published
        expected_id = vehicle_id(ROUTE_ID, 1)
        assert initial.vehicle_id == expected_id
        vehicle = bridge.aggregator.snapshot()[0]
        before = (
            vehicle.to_vehicle_position(),
            vehicle.sample_count,
            set(vehicle.sessions),
            dict(vehicle.principals),
        )

        invalid = body(sessionId="corrobora", timestamp=NOW + 1)
        invalid[field] = " " + invalid[field] + " "
        rejected = bridge.handle_message(
            topic_for(session=invalid["sessionId"], principal="cuenta-b"),
            json.dumps(invalid),
            NOW + 1,
        )

        assert not rejected.accepted
        assert rejected.reason is not None
        assert rejected.reason.value == NON_CANONICAL
        assert bridge.aggregator.vehicle_count == 1
        assert (
            vehicle.to_vehicle_position(),
            vehicle.sample_count,
            vehicle.sessions,
            vehicle.principals,
        ) == before
        assert bridge.validator.tracked_continuity_sessions == 1
        assert bridge.validator.deduplicator.tracked_keys == 1
        assert publisher.count == 0
        assert store.query("SELECT session_id, route_id, linea, vehicle_id FROM observations") == [
            ("e17", ROUTE_ID, LINE, expected_id)
        ]
        assert store.query("SELECT * FROM vehicle_positions") == []

        recovered = bridge.handle_message(
            topic_for(session="corrobora", principal="cuenta-b"),
            encoded(sessionId="corrobora", timestamp=NOW + 1),
            NOW + 1,
        )
        assert recovered.accepted and recovered.published and not recovered.created_vehicle
        assert recovered.vehicle_id == expected_id
        assert vehicle.sessions == {"e17", "corrobora"}
        assert vehicle.principals == {"cuenta-a": NOW, "cuenta-b": NOW + 1}
        assert vehicle.sample_count == 2
        assert publisher.count == 1
        assert publisher.last()["routeId"] == ROUTE_ID
        assert publisher.last()["linea"] == LINE
        assert publisher.last()["vehicleId"] == expected_id
        assert store.query("SELECT session_id, route_id, linea, vehicle_id FROM observations ORDER BY id") == [
            ("e17", ROUTE_ID, LINE, expected_id),
            ("corrobora", ROUTE_ID, LINE, expected_id),
        ]
        assert store.query("SELECT route_id, linea, vehicle_id FROM vehicle_positions") == [
            (ROUTE_ID, LINE, expected_id)
        ]
        assert store.query("SELECT reason FROM rejections") == [(NON_CANONICAL,)]
        assert store.counts.write_errors == 0
    finally:
        store.close()


def test_identificadores_validos_y_espacios_internos_se_conservan_en_todas_las_capas(
    identifier_feed, config, tmp_path
):
    session = "viaje 17"
    raw = encoded(sessionId=session)
    result = ObservationValidator(identifier_feed, config).validate(raw, NOW)
    assert result.ok
    assert result.observation is not None
    assert (result.observation.session_id, result.observation.route_id, result.observation.linea) == (
        session, ROUTE_ID, LINE
    )
    publisher = CapturingPublisher()
    store = ObservationStore(tmp_path / "e17-roundtrip.sqlite")
    try:
        bridge = Bridge(config=config, feed=identifier_feed, publisher=publisher, store=store)
        accepted = bridge.handle_message(topic_for(session=session), raw, NOW)
        expected_id = vehicle_id(ROUTE_ID, 1)
        assert accepted.accepted and accepted.published
        assert accepted.vehicle_id == expected_id
        vehicle = bridge.aggregator.snapshot()[0]
        assert vehicle.sessions == {session}
        assert (vehicle.route_id, vehicle.linea) == (ROUTE_ID, LINE)
        position = publisher.last()
        assert set(position) == {"vehicleId", "routeId", "linea", "lat", "lon", "speed", "heading", "timestamp"}
        assert (position["vehicleId"], position["routeId"], position["linea"]) == (expected_id, ROUTE_ID, LINE)
        assert publisher.messages[0][0] == config.vehicle_topic(expected_id)
        assert store.query("SELECT session_id, route_id, linea, vehicle_id FROM observations") == [
            (session, ROUTE_ID, LINE, expected_id)
        ]
        assert store.query("SELECT route_id, linea, vehicle_id FROM vehicle_positions") == [
            (ROUTE_ID, LINE, expected_id)
        ]
        assert store.query("SELECT * FROM rejections") == []
    finally:
        store.close()


def test_principales_del_topico_son_exactos_y_cuentas_distintas_corroboran(
    identifier_feed, config
):
    bridge = Bridge(
        config=replace(config, min_publish_principals=2),
        feed=identifier_feed,
        publisher=CapturingPublisher(),
    )
    first = bridge.handle_message(topic_for(session="a", principal="cuenta"), encoded(sessionId="a"), NOW)
    second = bridge.handle_message(
        topic_for(session="b", principal=" cuenta "), encoded(sessionId="b", timestamp=NOW + 1), NOW + 1
    )
    assert first.accepted and not first.published
    assert second.accepted and second.published and not second.created_vehicle
    assert second.vehicle_id == first.vehicle_id
    assert bridge.aggregator.snapshot()[0].principals == {"cuenta": NOW, " cuenta ": NOW + 1}


def test_limite_por_principal_no_recorta_ni_confunde_cuentas(identifier_feed, config):
    validator = ObservationValidator(identifier_feed, replace(config, max_messages_per_minute=1))
    assert validator.validate(encoded(sessionId="a"), NOW, principal="cuenta").ok
    assert validator.validate(encoded(sessionId="b"), NOW, principal=" cuenta ").ok
    rejected = validator.validate(encoded(sessionId="c"), NOW, principal=" cuenta ")
    assert rejected.reason is RejectReason.RATE_LIMITED
    assert validator.rate_limiter.tracked_sessions == 2


@pytest.mark.parametrize(
    "field,value,reason",
    [
        ("sessionId", "", RejectReason.EMPTY_SESSION),
        ("sessionId", "\t\n", RejectReason.EMPTY_SESSION),
        ("sessionId", "x" * 129, RejectReason.EMPTY_SESSION),
        ("sessionId", 42, RejectReason.BAD_FIELD_TYPE),
        ("routeId", "", RejectReason.UNKNOWN_ROUTE),
        ("linea", "", RejectReason.LINE_MISMATCH),
        ("routeId", 42, RejectReason.BAD_FIELD_TYPE),
        ("linea", None, RejectReason.BAD_FIELD_TYPE),
    ],
)
def test_guardas_previas_de_vacios_longitud_y_tipos_siguen_rechazando(
    identifier_feed, config, field, value, reason
):
    rejected = ObservationValidator(identifier_feed, config).validate(encoded(**{field: value}), NOW)
    assert not rejected.ok
    assert rejected.observation is None
    assert rejected.reason is reason


def test_identificadores_canonicos_conservan_rumbo_e15_y_continuidad_e16(
    identifier_feed, config
):
    publisher = CapturingPublisher()
    bridge = Bridge(config=config, feed=identifier_feed, publisher=publisher)
    topic = topic_for(session="e17")
    first = bridge.handle_message(topic, encoded(heading=1080.0), NOW)
    delayed = bridge.handle_message(topic, encoded(lat=-8.090, timestamp=NOW - 10), NOW + 1)
    following = bridge.handle_message(topic, encoded(lat=-8.1049, timestamp=NOW + 1), NOW + 6)
    contrary = bridge.handle_message(topic, encoded(heading=1260.0, timestamp=NOW + 2), NOW + 7)

    assert first.accepted and first.published
    assert delayed.accepted and not delayed.published
    assert following.accepted and following.published and not following.created_vehicle
    assert first.vehicle_id == delayed.vehicle_id == following.vehicle_id
    assert publisher.count == 2
    assert publisher.last()["lat"] == pytest.approx(-8.1049)
    assert publisher.last()["timestamp"] == NOW + 1
    assert publisher.last()["heading"] == 0.0
    assert not contrary.accepted
    assert contrary.reason is RejectReason.HEADING_NOT_ALIGNED
    assert bridge.aggregator.vehicle_count == 1
