"""Pruebas de extremo a extremo del puente, sin broker.

`Bridge.handle_message` es el mismo camino que se ejecuta en producción: el
publicador se inyecta, así que se puede comprobar exactamente qué habría salido
hacia el broker sin levantar Mosquitto.
"""

from __future__ import annotations

import json
import logging
import sys
from dataclasses import replace

import pytest

import rutautp_backend.bridge as bridge_module
import rutautp_backend.validation as validation_module
from rutautp_backend.bridge import Bridge, _sleep_until_reconnect
from rutautp_backend.config import Config
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.models import RejectReason
from rutautp_backend.persistence import ObservationStore

from .conftest import SAMPLE_ROUTE_ID, offset_meters, vehicle_id

NOW = 1_700_000_000.0
TOPIC = "rutautp/observaciones/device-001/session-0001/posicion"


def topic_for(session: str = "session-0001", principal: str = "device-001") -> str:
    return f"rutautp/observaciones/{principal}/{session}/posicion"


class TestEsperaDeReconexion:
    """B02: el backoff debe ceder CPU cuando no existe un socket MQTT."""

    def test_duerme_hasta_un_tick_mientras_espera(self, monkeypatch):
        sleeps: list[float] = []
        monkeypatch.setattr("rutautp_backend.bridge.time.sleep", sleeps.append)

        _sleep_until_reconnect(
            now=10.0,
            next_attempt_at=18.0,
            max_sleep_s=1.0,
        )

        assert sleeps == [1.0]

    def test_no_duerme_si_ya_corresponde_reconectar(self, monkeypatch):
        sleeps: list[float] = []
        monkeypatch.setattr("rutautp_backend.bridge.time.sleep", sleeps.append)

        _sleep_until_reconnect(
            now=18.0,
            next_attempt_at=18.0,
            max_sleep_s=1.0,
        )

        assert sleeps == []


class CapturingPublisher:
    """Publicador de mentira que guarda lo que se habría enviado."""

    def __init__(self, accept: bool = True) -> None:
        self.messages: list[tuple[str, str]] = []
        self.accept = accept

    def __call__(self, topic: str, payload: str) -> bool:
        """Devuelve si el broker habría aceptado el mensaje."""
        if not self.accept:
            return False

        self.messages.append((topic, payload))
        return True

    @property
    def count(self) -> int:
        return len(self.messages)

    def payloads(self) -> list[dict]:
        return [json.loads(payload) for _, payload in self.messages]

    def last(self) -> dict:
        return self.payloads()[-1]


def payload_for(
    route,
    *,
    now: float = NOW,
    session: str = "session-0001",
    progress: float = 0.5,
    offset_north_m: float = 0.0,
    **overrides,
) -> str:
    """Mensaje JSON tal como lo publicaría la baliza."""
    index = min(int(progress * (len(route.shape) - 1)), len(route.shape) - 2)
    latitude, longitude = route.shape[index]

    latitude, longitude = offset_meters(
        latitude, longitude, north_m=offset_north_m
    )

    body = {
        "schemaVersion": 1,
        "sessionId": session,
        "routeId": route.route_id,
        "linea": route.linea,
        "lat": latitude,
        "lon": longitude,
        "speed": 8.0,
        "heading": segment_bearing_deg(list(route.shape), index),
        "accuracy": 8.0,
        "motionActivity": "automotive",
        "timestamp": now,
    }

    body.update(overrides)

    return json.dumps(body)


@pytest.fixture
def publisher() -> CapturingPublisher:
    return CapturingPublisher()


@pytest.fixture
def bridge(config: Config, feed: GtfsFeed, publisher: CapturingPublisher) -> Bridge:
    return Bridge(config=config, feed=feed, publisher=publisher)


class TestCaminoFeliz:
    def test_acepta_y_publica(self, bridge, publisher, sample_route):
        outcome = bridge.handle_message(
            TOPIC,
            payload_for(sample_route),
            NOW,
        )

        assert outcome.accepted is True
        assert outcome.created_vehicle is True
        assert outcome.published is True
        assert publisher.count == 1

    def test_un_principal_no_publica_rotando_sesiones(
        self, config, feed, publisher, sample_route
    ):
        secure_config = Config(
            **{**config.__dict__, "min_publish_principals": 2}
        )
        bridge = Bridge(config=secure_config, feed=feed, publisher=publisher)

        first = bridge.handle_message(
            topic_for(session="sesion-a", principal="device-001"),
            payload_for(sample_route, session="sesion-a"),
            NOW,
        )
        second = bridge.handle_message(
            topic_for(session="sesion-b", principal="device-001"),
            payload_for(sample_route, session="sesion-b", now=NOW + 1),
            NOW + 1,
        )

        assert first.accepted is True
        assert second.accepted is True
        assert first.published is False
        assert second.published is False
        assert publisher.count == 0

        corroborated = bridge.handle_message(
            topic_for(session="sesion-c", principal="device-002"),
            payload_for(sample_route, session="sesion-c", now=NOW + 2),
            NOW + 2,
        )

        assert corroborated.published is True
        assert publisher.count == 1

    def test_el_topico_de_salida_tiene_el_formato_esperado(
        self, bridge, publisher, sample_route
    ):
        bridge.handle_message(TOPIC, payload_for(sample_route), NOW)

        topic, _ = publisher.messages[0]

        assert topic == f"rutautp/vehiculos/{vehicle_id(SAMPLE_ROUTE_ID, 1)}/posicion"

    def test_lo_publicado_encaja_con_el_contrato(
        self, bridge, publisher, sample_route
    ):
        bridge.handle_message(TOPIC, payload_for(sample_route), NOW)

        body = publisher.last()

        assert set(body.keys()) == {
            "vehicleId",
            "routeId",
            "linea",
            "lat",
            "lon",
            "speed",
            "heading",
            "timestamp",
        }
        assert body["vehicleId"] == vehicle_id(SAMPLE_ROUTE_ID, 1)
        assert body["routeId"] == SAMPLE_ROUTE_ID
        assert body["linea"] == sample_route.linea

    def test_la_marca_de_tiempo_publicada_es_la_de_la_observacion(
        self, bridge, publisher, sample_route
    ):
        """No la de publicación.

        Si se refrescara al publicar, un vehículo que dejó de transmitir
        seguiría pareciendo vivo y nunca se podaría del mapa.
        """
        bridge.handle_message(
            TOPIC, payload_for(sample_route, now=NOW - 3), NOW
        )

        assert publisher.last()["timestamp"] == NOW - 3


class TestRechazos:
    def test_rechaza_un_mensaje_grande_antes_de_parsear(
        self, bridge, monkeypatch
    ):
        def json_no_debe_ejecutarse(*_args, **_kwargs):
            raise AssertionError("json.loads no debe ejecutarse")

        monkeypatch.setattr(
            "rutautp_backend.bridge.json.loads",
            json_no_debe_ejecutarse,
        )

        payload = b"{" + b"x" * int(bridge.config.max_message_bytes)

        outcome = bridge.handle_message(
            "rutautp/observaciones/device-001/sesion/posicion",
            payload,
            NOW,
        )

        assert outcome.accepted is False
        assert outcome.reason is RejectReason.MESSAGE_TOO_LARGE
        assert bridge.metrics.snapshot()["internalErrors"] == 0

    def test_un_mensaje_invalido_no_publica(self, bridge, publisher):
        outcome = bridge.handle_message(TOPIC, "{no es json", NOW)

        assert outcome.accepted is False
        assert outcome.reason is RejectReason.MALFORMED_JSON
        assert publisher.count == 0

    def test_se_contabiliza_el_motivo(self, bridge, sample_route):
        bridge.handle_message(TOPIC, "{no es json", NOW)
        bridge.handle_message(
            TOPIC, payload_for(sample_route, routeId="no-existe"), NOW
        )

        snapshot = bridge.metrics.snapshot()

        assert snapshot["received"] == 2
        assert snapshot["accepted"] == 0
        assert snapshot["rejected"] == 2
        assert snapshot["reasons"]["malformed_json"] == 1
        assert snapshot["reasons"]["unknown_route"] == 1

    def test_una_observacion_lejos_del_recorrido_no_publica(
        self, bridge, publisher, sample_route
    ):
        index = len(sample_route.shape) // 2
        latitude, longitude = sample_route.shape[index]
        lejos_lat, lejos_lon = offset_meters(latitude, longitude, north_m=3000)

        outcome = bridge.handle_message(
            TOPIC,
            payload_for(sample_route, lat=lejos_lat, lon=lejos_lon),
            NOW,
        )

        assert outcome.reason is RejectReason.TOO_FAR_FROM_ROUTE
        assert publisher.count == 0


class TestSinPublicador:
    def test_sin_publicador_procesa_pero_no_publica(
        self, config: Config, feed: GtfsFeed, sample_route
    ):
        """Es el modo `--dry-run` contra un broker real."""
        bridge = Bridge(config=config, feed=feed, publisher=None)

        outcome = bridge.handle_message(TOPIC, payload_for(sample_route), NOW)

        assert outcome.accepted is True
        assert outcome.published is False
        assert bridge.metrics.snapshot()["published"] == 0


class TestRitmoDePublicacion:
    def test_no_publica_dos_veces_en_el_mismo_intervalo(
        self, bridge, publisher, sample_route, config
    ):
        for index in range(3):
            bridge.handle_message(
                topic_for(session=f"s-{index}"),
                payload_for(
                    sample_route,
                    session=f"s-{index}",
                    offset_north_m=index * 5,
                ),
                NOW + index * 0.1,
            )

        assert bridge.metrics.snapshot()["accepted"] == 3
        assert publisher.count == 1, "los tres mensajes son del mismo vehículo"

    def test_publica_de_nuevo_pasado_el_intervalo(
        self, bridge, publisher, sample_route, config
    ):
        bridge.handle_message(TOPIC, payload_for(sample_route), NOW)

        bridge.handle_message(
            TOPIC,
            payload_for(sample_route, now=NOW + config.publish_interval_s),
            NOW + config.publish_interval_s,
        )

        assert publisher.count == 2

    def test_pasajeros_de_rutas_distintas_publican_cada_uno(
        self, bridge, publisher, feed, sample_route
    ):
        otra = next(
            route
            for route in feed.routes_with_geometry()
            if route.route_id != sample_route.route_id
        )

        # Sesiones distintas: dos mensajes de la misma sesión y con la misma
        # marca de tiempo serían un duplicado de QoS 1 y el segundo se
        # descartaría, que es justo lo que debe pasar.
        bridge.handle_message(
            topic_for("sesion-a"), payload_for(sample_route, session="sesion-a"), NOW
        )
        bridge.handle_message(
            topic_for("sesion-b"), payload_for(otra, session="sesion-b"), NOW + 1
        )

        assert publisher.count == 2

    def test_diez_pasajeros_del_mismo_bus_producen_un_vehiculo(
        self, bridge, publisher, sample_route
    ):
        """Es el caso que justifica que exista el backend."""
        for index in range(10):
            bridge.handle_message(
                topic_for(session=f"pasajero-{index:02d}"),
                payload_for(
                    sample_route,
                    session=f"pasajero-{index:02d}",
                    offset_north_m=index * 5,
                ),
                NOW + index * 0.1,
            )

        assert bridge.aggregator.vehicle_count == 1
        assert len(
            bridge.aggregator.sessions_on(vehicle_id(SAMPLE_ROUTE_ID, 1))
        ) == 10
        assert publisher.count == 1


class TestMantenimiento:
    def test_tick_caduca_los_vehiculos(self, bridge, sample_route, config):
        bridge.handle_message(TOPIC, payload_for(sample_route), NOW)

        assert bridge.tick(NOW + 1) == 0
        assert bridge.aggregator.vehicle_count == 1

        expired = bridge.tick(NOW + config.vehicle_ttl_s + 1)

        assert expired == 1
        assert bridge.aggregator.vehicle_count == 0
        assert bridge.metrics.snapshot()["vehiclesExpired"] == 1

    def test_tick_libera_el_estado_de_sesiones(self, bridge, sample_route):
        bridge.handle_message(TOPIC, payload_for(sample_route), NOW)

        bridge.tick(NOW + 10_000)

        assert bridge.validator.rate_limiter.tracked_sessions == 0


class TestSesionDelTopico:
    """B05: el tópico y el cuerpo deben declarar la misma sesión.

    Antes solo se advertía. Eso permitía publicar en el tópico de una sesión y
    declarar otra en el cuerpo, con lo que el límite de tasa se aplicaba a una
    identidad distinta de la que ve un operador al diagnosticar.
    """

    def test_rechaza_si_el_topico_y_el_cuerpo_no_concuerdan(
        self, bridge, publisher, sample_route
    ):
        outcome = bridge.handle_message(
            "rutautp/observaciones/device-001/otra-sesion/posicion",
            payload_for(sample_route, session="session-0001"),
            NOW,
        )

        assert outcome.accepted is False
        assert outcome.reason is RejectReason.SESSION_MISMATCH
        assert publisher.count == 0

    def test_se_contabiliza_el_motivo(self, bridge, sample_route):
        bridge.handle_message(
            "rutautp/observaciones/device-001/otra-sesion/posicion",
            payload_for(sample_route, session="session-0001"),
            NOW,
        )

        snapshot = bridge.metrics.snapshot()

        assert snapshot["reasons"]["session_mismatch"] == 1
        assert snapshot["accepted"] == 0

    def test_acepta_cuando_concuerdan(self, bridge, publisher, sample_route):
        outcome = bridge.handle_message(
            TOPIC,
            payload_for(sample_route, session="session-0001"),
            NOW,
        )

        assert outcome.accepted is True
        assert publisher.count == 1

    def test_un_topico_con_otra_forma_se_rechaza(self, bridge, sample_route):
        """Sin tópico canónico no existe una identidad autenticada que limitar."""
        outcome = bridge.handle_message(
            "otro/topico",
            payload_for(sample_route, session="session-0001"),
            NOW,
        )

        assert outcome.accepted is False
        assert outcome.reason is RejectReason.SESSION_MISMATCH


class TestIdentidadDelVehiculo:
    def test_el_identificador_no_proviene_del_cliente(
        self, bridge, publisher, sample_route
    ):
        """El cliente no envía `vehicleId`; el servidor lo deriva.

        Aunque un cliente malicioso añadiera un campo `vehicleId` al mensaje, el
        validador no lo mira y el identificador publicado sigue siendo el
        derivado.
        """
        mensaje = json.loads(payload_for(sample_route))
        mensaje["vehicleId"] = "yo-soy-el-bus-1"

        bridge.handle_message(TOPIC, json.dumps(mensaje), NOW)

        publicado = publisher.last()["vehicleId"]

        assert publicado == vehicle_id(SAMPLE_ROUTE_ID, 1)
        assert "yo-soy-el-bus-1" not in publicado


class TestRepresentabilidadNumerica:
    @pytest.mark.parametrize("field_name", ["schemaVersion", "lat"])
    @pytest.mark.parametrize("sign", ["", "-"], ids=["positivo", "negativo"])
    @pytest.mark.parametrize("as_bytes", [False, True], ids=["texto", "bytes"])
    def test_rechazo_predecible_permite_entrada_valida_posterior(
        self, config, feed, publisher, sample_route, tmp_path, field_name, sign, as_bytes
    ):
        config = replace(
            config,
            database_path="",
            health_file="",
            simulation_ingress_enabled=False,
            max_message_bytes=8192,
            max_messages_per_minute=1,
            max_messages_per_minute_global=1,
        )
        store = ObservationStore(tmp_path / "n1.sqlite3")
        try:
            local_bridge = Bridge(
                config=config, feed=feed, publisher=publisher, store=store
            )
            assert store.enabled
            marker = "__entero_extremo_n1__"
            raw = payload_for(sample_route, **{field_name: marker})
            assert raw.count(marker) == 1
            raw = raw.replace('"__entero_extremo_n1__"', sign + "9" * 400)
            if as_bytes:
                raw = raw.encode("utf-8")
            assert len(raw) <= 8192

            rejected = local_bridge.handle_message(TOPIC, raw, NOW)

            assert rejected.accepted is False
            assert rejected.reason is RejectReason.NON_FINITE_NUMBER
            assert rejected.detail == f"{field_name}: fuera de rango numérico"
            assert len(rejected.detail) < 80
            assert local_bridge.metrics.received == 1
            assert local_bridge.metrics.accepted == 0
            assert local_bridge.metrics.internal_errors == 0
            assert local_bridge.metrics.rejected == {"non_finite_number": 1}
            assert local_bridge.metrics.publish_attempts == 0
            assert local_bridge.metrics.vehicles_created == 0
            assert local_bridge.aggregator.vehicle_count == 0
            assert publisher.messages == []
            assert local_bridge.validator.rate_limiter.tracked_sessions == 0
            assert local_bridge.validator.global_limiter.tracked_sessions == 0
            assert local_bridge.validator.deduplicator.tracked_keys == 0
            assert local_bridge.validator.tracked_continuity_sessions == 0
            assert store.query("SELECT COUNT(*) FROM observations") == [(0,)]
            assert store.query("SELECT COUNT(*) FROM vehicle_positions") == [(0,)]
            assert store.query("SELECT reason, detail FROM rejections") == [
                ("non_finite_number", f"{field_name}: fuera de rango numérico")
            ]

            # Mismo principal, sesión y reloj; ambos cupos son de un solo mensaje.
            accepted = local_bridge.handle_message(
                TOPIC, payload_for(sample_route), NOW
            )

            assert accepted.accepted is True
            assert accepted.reason is None
            assert accepted.created_vehicle is True
            assert accepted.published is True
            assert accepted.vehicle_id == vehicle_id(SAMPLE_ROUTE_ID, 1)
            assert local_bridge.metrics.received == 2
            assert local_bridge.metrics.accepted == 1
            assert local_bridge.metrics.internal_errors == 0
            assert local_bridge.metrics.rejected == {"non_finite_number": 1}
            assert local_bridge.aggregator.vehicle_count == 1
            assert publisher.count == 1
            assert local_bridge.validator.rate_limiter.tracked_sessions == 1
            assert local_bridge.validator.global_limiter.tracked_sessions == 1
            assert local_bridge.validator.deduplicator.tracked_keys == 1
            assert local_bridge.validator.tracked_continuity_sessions == 1
            assert store.query("SELECT session_id, route_id FROM observations") == [
                ("session-0001", SAMPLE_ROUTE_ID)
            ]
            assert store.query("SELECT COUNT(*) FROM vehicle_positions") == [(1,)]
            assert store.query("SELECT COUNT(*) FROM rejections") == [(1,)]
            assert store.counts.write_errors == 0
        finally:
            store.close()
        assert store.enabled is False


class _JSONPrelecturaProxy:
    """Falla solo para un centinela y conserva el JSON estándar sin modificarlo."""

    def __init__(self, sentinel: bytes | str, error_type: type[Exception]):
        self._original = json
        self._sentinel = sentinel
        self._error_type = error_type
        self.loads_calls = []

    def loads(self, raw, *args, **kwargs):
        self.loads_calls.append((raw, args, dict(kwargs)))
        if raw == self._sentinel:
            raise self._error_type("error de prelectura controlado P10")
        return self._original.loads(raw, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._original, name)


class _RegistroPrelecturaEnMemoria:
    """Espía de llamadas del Bridge, sin conexión o archivos que cerrar."""

    def __init__(self):
        self.rejections = []
        self.observations = []
        self.vehicles = []

    def record_rejection(self, reason, detail, now, *, source):
        self.rejections.append((reason, detail, now, source))

    def record_observation(self, observation, vehicle_id, now, *, source):
        self.observations.append((observation, vehicle_id, now, source))

    def record_vehicle(self, vehicle, now, *, source):
        self.vehicles.append((vehicle, now, source))


def _bridge_para_prelectura(config, feed, publisher):
    isolated_config = replace(
        config,
        database_path="",
        health_file="",
        simulation_ingress_enabled=False,
        simulation_occupancy_enabled=False,
        simulation_control_path="",
        vehicle_position_schema_version=1,
        max_message_bytes=8192,
        max_messages_per_minute=1,
        max_messages_per_minute_global=1,
        min_publish_principals=1,
    )
    store = _RegistroPrelecturaEnMemoria()
    bridge = Bridge(isolated_config, feed, publisher, store=store)
    return bridge, store


def _comprobar_rechazo_prelectura_y_recuperacion(
    bridge, store, publisher, sample_route, raw, reason, *, expected_detail=None
):
    """Observa rechazo y dato válido posterior por la entrada pública real."""
    assert type(bridge.validator) is validation_module.ObservationValidator
    assert len(raw) <= bridge.config.max_message_bytes
    rejected = bridge.handle_message(TOPIC, raw, NOW)

    assert rejected.accepted is False
    assert rejected.reason is reason
    assert rejected.vehicle_id is None
    assert rejected.created_vehicle is False
    assert rejected.published is False
    assert rejected.detail and len(rejected.detail) <= 120
    if expected_detail is not None:
        assert rejected.detail == expected_detail
    assert bridge.metrics.received == 1
    assert bridge.metrics.accepted == 0
    assert bridge.metrics.internal_errors == 0
    assert bridge.metrics.rejected == {reason.value: 1}
    assert bridge.metrics.vehicles_created == 0
    assert bridge.metrics.publish_attempts == 0
    assert bridge.metrics.publish_failures == 0
    assert bridge.metrics.published == 0
    assert bridge.aggregator.vehicle_count == 0
    assert publisher.messages == []
    assert bridge.validator.rate_limiter.tracked_sessions == 0
    assert bridge.validator.global_limiter.tracked_sessions == 0
    assert bridge.validator.deduplicator.tracked_keys == 0
    assert bridge.validator.tracked_continuity_sessions == 0
    assert store.observations == []
    assert store.vehicles == []
    assert len(store.rejections) == 1
    recorded_reason, detail, at, source = store.rejections[0]
    assert recorded_reason is reason
    assert detail == rejected.detail
    assert at == NOW
    assert source.origin.value == "observed"
    assert source.run_id is None
    assert source.principal == "device-001"

    valid = payload_for(sample_route)
    accepted = bridge.handle_message(TOPIC, valid, NOW)

    assert accepted.accepted is True
    assert accepted.reason is None
    assert accepted.created_vehicle is True
    assert accepted.published is True
    assert accepted.vehicle_id == vehicle_id(SAMPLE_ROUTE_ID, 1)
    assert bridge.metrics.received == 2
    assert bridge.metrics.accepted == 1
    assert bridge.metrics.internal_errors == 0
    assert bridge.metrics.rejected == {reason.value: 1}
    assert bridge.metrics.vehicles_created == 1
    assert bridge.metrics.publish_attempts == 1
    assert bridge.metrics.publish_failures == 0
    assert bridge.metrics.published == 1
    assert bridge.aggregator.vehicle_count == 1
    assert bridge.validator.rate_limiter.tracked_sessions == 1
    assert bridge.validator.global_limiter.tracked_sessions == 1
    assert bridge.validator.deduplicator.tracked_keys == 1
    assert bridge.validator.tracked_continuity_sessions == 1
    assert publisher.count == 1
    assert publisher.last()["vehicleId"] == vehicle_id(SAMPLE_ROUTE_ID, 1)
    assert publisher.last()["timestamp"] == NOW
    assert len(store.rejections) == 1
    assert len(store.observations) == 1
    observation, recorded_id, at, recorded_source = store.observations[0]
    assert observation.session_id == "session-0001"
    assert observation.route_id == SAMPLE_ROUTE_ID
    assert observation.timestamp == NOW
    assert recorded_id == accepted.vehicle_id
    assert at == NOW and recorded_source == source
    assert len(store.vehicles) == 1
    vehicle, at, recorded_source = store.vehicles[0]
    assert vehicle.vehicle_id == accepted.vehicle_id
    assert vehicle.last_published_at == NOW
    assert at == NOW and recorded_source == source
    return valid


class TestErroresDePrelectura:
    @pytest.mark.parametrize(
        "error_type,reason,detail",
        [
            (ValueError, RejectReason.NON_FINITE_NUMBER, "error de prelectura controlado P10"),
            (RecursionError, RejectReason.TOO_DEEPLY_NESTED, "anidamiento excesivo"),
        ],
        ids=["valor", "recursion"],
    )
    @pytest.mark.parametrize("as_bytes", [False, True], ids=["texto", "bytes"])
    def test_errores_de_prelectura_llegan_al_validador_y_permiten_recuperacion(
        self, config, feed, publisher, sample_route, monkeypatch,
        error_type, reason, detail, as_bytes,
    ):
        bridge, store = _bridge_para_prelectura(config, feed, publisher)
        sentinel = '{"sessionId":"session-0001","centinela":"P10"}'
        raw = sentinel.encode("ascii") if as_bytes else sentinel
        proxy = _JSONPrelecturaProxy(raw, error_type)
        original_bridge_json = bridge_module.json
        original_validation_json = validation_module.json
        original_loads = json.loads

        with monkeypatch.context() as patch:
            patch.setattr(bridge_module, "json", proxy)
            patch.setattr(validation_module, "json", proxy)
            valid = _comprobar_rechazo_prelectura_y_recuperacion(
                bridge, store, publisher, sample_route, raw, reason,
                expected_detail=detail,
            )
            assert len(proxy.loads_calls) == 4
            assert proxy.loads_calls[0] == (raw, (), {})
            assert proxy.loads_calls[1] == (
                raw, (), {"parse_constant": validation_module._reject_json_constant}
            )
            assert proxy.loads_calls[2] == (valid, (), {})
            assert proxy.loads_calls[3] == (
                valid, (), {"parse_constant": validation_module._reject_json_constant}
            )
            assert json.loads is original_loads

        assert bridge_module.json is original_bridge_json
        assert validation_module.json is original_validation_json
        assert json.loads is original_loads

    @pytest.mark.parametrize("as_bytes", [False, True], ids=["texto", "bytes"])
    def test_decimal_real_se_difiere_con_limite_activo_4300(
        self, config, feed, publisher, sample_route, as_bytes
    ):
        if sys.implementation.name != "cpython":
            pytest.skip("requiere CPython con API de límite decimal y valor activo 4300")
        get_limit = getattr(sys, "get_int_max_str_digits", None)
        if get_limit is None or get_limit() != 4300:
            pytest.skip("requiere API de límite decimal disponible y valor activo 4300")

        bridge, store = _bridge_para_prelectura(config, feed, publisher)
        raw = "9" * 5000
        if as_bytes:
            raw = raw.encode("ascii")
        _comprobar_rechazo_prelectura_y_recuperacion(
            bridge, store, publisher, sample_route, raw, RejectReason.NON_FINITE_NUMBER,
        )
