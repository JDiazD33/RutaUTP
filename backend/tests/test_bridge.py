"""Pruebas de extremo a extremo del puente, sin broker.

`Bridge.handle_message` es el mismo camino que se ejecuta en producción: el
publicador se inyecta, así que se puede comprobar exactamente qué habría salido
hacia el broker sin levantar Mosquitto.
"""

from __future__ import annotations

import json
import logging

import pytest

from rutautp_backend.bridge import Bridge, _sleep_until_reconnect
from rutautp_backend.config import Config
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.models import RejectReason

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
