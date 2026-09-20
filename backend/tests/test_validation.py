"""Pruebas de la validación.

Cada motivo de rechazo tiene su caso. Además hay dos pruebas que fijan
comportamientos deliberados y fáciles de romper sin darse cuenta: que un bus
detenido se acepte (velocidad ~0, rumbo desconocido) y que un `-1` en rumbo no
se trate como manipulación.
"""

from __future__ import annotations

import json
import math

import pytest

from rutautp_backend.config import Config
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.models import RejectReason
from rutautp_backend.validation import ObservationValidator

from .conftest import SAMPLE_ROUTE_ID, offset_meters

NOW = 1_700_000_000.0


def on_route_payload(
    route,
    *,
    now: float = NOW,
    progress: float = 0.5,
    **overrides,
) -> dict:
    """Observación válida sobre el recorrido real de `route`.

    El rumbo se toma del propio segmento, así que pasa la comprobación de
    alineación sin trucos. Cualquier campo se puede sobrescribir con `overrides`.
    """
    index = min(int(progress * (len(route.shape) - 1)), len(route.shape) - 2)
    latitude, longitude = route.shape[index]

    payload = {
        "schemaVersion": 1,
        "sessionId": "session-0001",
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

    payload.update(overrides)

    return payload


@pytest.fixture
def validator(feed: GtfsFeed, config: Config) -> ObservationValidator:
    return ObservationValidator(feed, config)


def validate(validator: ObservationValidator, payload, now: float = NOW):
    return validator.validate(json.dumps(payload), now)


class TestAcepta:
    def test_observacion_valida(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route))

        assert result.ok
        assert result.observation.route_id == SAMPLE_ROUTE_ID
        assert result.observation.session_id == "session-0001"
        assert result.observation.distance_to_route_m < 1.0

    def test_acepta_bytes_ademas_de_texto(self, validator, sample_route):
        payload = json.dumps(on_route_payload(sample_route)).encode()

        assert validator.validate(payload, NOW).ok

    def test_bus_detenido_en_un_semaforo(self, validator, sample_route):
        """Velocidad ~0 y rumbo desconocido son normales con el vehículo parado.

        Si el servidor exigiera "velocidad de vehículo" como hace el detector
        del teléfono, todos los buses parados desaparecerían del mapa.
        """
        result = validate(
            validator,
            on_route_payload(sample_route, speed=0.0, heading=-1),
        )

        assert result.ok

    def test_rumbo_desconocido_no_bloquea(self, validator, sample_route):
        assert validate(validator, on_route_payload(sample_route, heading=-1)).ok

    def test_velocidad_desconocida_no_bloquea(self, validator, sample_route):
        assert validate(validator, on_route_payload(sample_route, speed=-1)).ok

    def test_actividad_caminando_no_se_rechaza(self, validator, sample_route):
        """La actividad la decide el detector del teléfono, no el servidor.

        Rechazarla aquí solo añadiría falsos negativos: no aporta nada a la
        seguridad, porque el consumidor del mapa la ignora.
        """
        result = validate(
            validator, on_route_payload(sample_route, motionActivity="walking")
        )

        assert result.ok

    def test_desfase_de_reloj_tolerado(self, validator, sample_route):
        result = validate(
            validator,
            on_route_payload(sample_route, timestamp=NOW + 5),
        )

        assert result.ok


class TestFormaDelMensaje:
    def test_json_invalido(self, validator):
        result = validator.validate("{esto no es json", NOW)

        assert result.reason is RejectReason.MALFORMED_JSON

    def test_json_que_no_es_objeto(self, validator):
        result = validator.validate("[1, 2, 3]", NOW)

        assert result.reason is RejectReason.NOT_AN_OBJECT

    def test_campo_ausente(self, validator, sample_route):
        payload = on_route_payload(sample_route)
        del payload["accuracy"]

        result = validate(validator, payload)

        assert result.reason is RejectReason.MISSING_FIELD
        assert result.detail == "accuracy"

    def test_tipo_de_campo_incorrecto(self, validator, sample_route):
        result = validate(
            validator, on_route_payload(sample_route, lat="no soy un número")
        )

        assert result.reason is RejectReason.BAD_FIELD_TYPE

    def test_booleano_no_pasa_como_numero(self, validator, sample_route):
        """`True` es subclase de `int` en Python; no debe colarse como latitud."""
        result = validate(validator, on_route_payload(sample_route, lat=True))

        assert result.reason is RejectReason.BAD_FIELD_TYPE

    def test_version_de_esquema_no_soportada(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route, schemaVersion=99))

        assert result.reason is RejectReason.UNSUPPORTED_SCHEMA

    def test_sesion_vacia(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route, sessionId="   "))

        assert result.reason is RejectReason.EMPTY_SESSION

    def test_sesion_demasiado_larga(self, validator, sample_route):
        result = validate(
            validator, on_route_payload(sample_route, sessionId="x" * 500)
        )

        assert result.reason is RejectReason.EMPTY_SESSION


class TestRangos:
    def test_latitud_fuera_de_rango(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route, lat=999))

        assert result.reason is RejectReason.INVALID_COORDINATE

    def test_coordenada_no_finita(self, validator, sample_route):
        """Se rechaza al decodificar, antes de llegar a comprobar el rango.

        El motivo es más preciso que `INVALID_COORDINATE`: el problema no es que
        la coordenada esté fuera de rango, sino que `NaN` ni siquiera es un
        número válido para el contrato JSON.
        """
        result = validate(
            validator, on_route_payload(sample_route, lon=float("nan"))
        )

        assert result.reason is RejectReason.NON_FINITE_NUMBER

    def test_precision_negativa(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route, accuracy=-1))

        assert result.reason is RejectReason.BAD_ACCURACY

    def test_precision_peor_que_el_maximo(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route, accuracy=120))

        assert result.reason is RejectReason.BAD_ACCURACY

    def test_marca_de_tiempo_del_futuro(self, validator, sample_route):
        result = validate(
            validator, on_route_payload(sample_route, timestamp=NOW + 600)
        )

        assert result.reason is RejectReason.FUTURE_TIMESTAMP

    def test_marca_de_tiempo_obsoleta(self, validator, sample_route):
        result = validate(
            validator, on_route_payload(sample_route, timestamp=NOW - 300)
        )

        assert result.reason is RejectReason.STALE_TIMESTAMP


class TestContraElRecorrido:
    def test_ruta_desconocida(self, validator, sample_route):
        result = validate(
            validator, on_route_payload(sample_route, routeId="no-existe")
        )

        assert result.reason is RejectReason.UNKNOWN_ROUTE

    def test_linea_que_no_corresponde_a_la_ruta(self, validator, sample_route):
        """Evita que un vehículo se anuncie con el nombre de otra línea.

        El mapa de los demás usa `linea` para el nombre y el color, así que una
        discrepancia mostraría un vehículo con la identidad equivocada.
        """
        result = validate(validator, on_route_payload(sample_route, linea="X-99"))

        assert result.reason is RejectReason.LINE_MISMATCH

    def test_punto_lejos_del_recorrido(self, validator, sample_route):
        index = len(sample_route.shape) // 2
        latitude, longitude = sample_route.shape[index]
        lejos_lat, lejos_lon = offset_meters(latitude, longitude, north_m=2000)

        result = validate(
            validator,
            on_route_payload(sample_route, lat=lejos_lat, lon=lejos_lon),
        )

        assert result.reason is RejectReason.TOO_FAR_FROM_ROUTE

    def test_rumbo_contrario_al_recorrido(self, validator, sample_route):
        index = len(sample_route.shape) // 2
        bearing = segment_bearing_deg(list(sample_route.shape), index)

        result = validate(
            validator,
            on_route_payload(sample_route, heading=(bearing + 180) % 360),
        )

        assert result.reason is RejectReason.HEADING_NOT_ALIGNED

    def test_velocidad_imposible(self, validator, sample_route):
        result = validate(validator, on_route_payload(sample_route, speed=400))

        assert result.reason is RejectReason.SPEED_OUT_OF_RANGE


class TestLimiteDeTasa:
    def test_acepta_hasta_el_limite(self, validator, sample_route, config):
        for index in range(config.max_messages_per_minute):
            result = validate(
                validator,
                on_route_payload(sample_route, timestamp=NOW + index * 0.01),
                now=NOW + index * 0.01,
            )

            assert result.ok, f"el mensaje {index} debería aceptarse"

    def test_rechaza_al_superar_el_limite(self, validator, sample_route, config):
        for index in range(config.max_messages_per_minute):
            validate(
                validator,
                on_route_payload(sample_route, timestamp=NOW + index * 0.01),
                now=NOW + index * 0.01,
            )

        result = validate(
            validator,
            on_route_payload(sample_route, timestamp=NOW + 0.5),
            now=NOW + 0.5,
        )

        assert result.reason is RejectReason.RATE_LIMITED

    def test_la_ventana_se_libera_con_el_tiempo(self, validator, sample_route, config):
        for index in range(config.max_messages_per_minute):
            validate(
                validator,
                on_route_payload(sample_route, timestamp=NOW),
                now=NOW,
            )

        # Un minuto después la ventana ya no contiene aquellos mensajes.
        later = NOW + 61
        result = validate(
            validator,
            on_route_payload(sample_route, timestamp=later),
            now=later,
        )

        assert result.ok

    def test_sesiones_distintas_no_se_estorban(self, validator, sample_route, config):
        for index in range(config.max_messages_per_minute):
            validate(
                validator,
                on_route_payload(
                    sample_route, sessionId="sesion-a", timestamp=NOW + index * 0.01
                ),
                now=NOW + index * 0.01,
            )

        result = validate(
            validator,
            on_route_payload(sample_route, sessionId="sesion-b", timestamp=NOW + 0.5),
            now=NOW + 0.5,
        )

        assert result.ok


class TestDuplicados:
    def test_el_mismo_mensaje_dos_veces(self, validator, sample_route):
        payload = on_route_payload(sample_route)

        assert validate(validator, payload).ok

        result = validate(validator, payload, now=NOW + 1)

        assert result.reason is RejectReason.DUPLICATE

    def test_mismo_timestamp_en_sesiones_distintas(self, validator, sample_route):
        assert validate(validator, on_route_payload(sample_route)).ok

        result = validate(
            validator,
            on_route_payload(sample_route, sessionId="otra-sesion"),
            now=NOW + 1,
        )

        assert result.ok

    def test_una_marca_de_tiempo_nueva_no_es_duplicado(self, validator, sample_route):
        assert validate(validator, on_route_payload(sample_route)).ok

        result = validate(
            validator,
            on_route_payload(sample_route, timestamp=NOW + 5),
            now=NOW + 5,
        )

        assert result.ok


class TestLimpieza:
    def test_prune_libera_el_estado_de_sesiones(self, validator, sample_route):
        validate(validator, on_route_payload(sample_route))

        assert validator.rate_limiter.tracked_sessions == 1

        validator.prune(NOW + 10_000)

        assert validator.rate_limiter.tracked_sessions == 0
        assert validator.deduplicator.tracked_keys == 0
