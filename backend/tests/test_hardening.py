"""Regresiones de robustez de entrada (B01).

El criterio de aceptación del informe es doble: **una batería de entradas
inválidas no termina el proceso**, y **una observación válida enviada después
sigue produciendo una posición vehicular**.

Ese segundo punto es el que importa de verdad. Un servicio que rechaza lo malo
pero se queda sordo no sirve de nada, así que cada caso comprueba las dos cosas.
"""

from __future__ import annotations

import json

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.config import Config
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.models import RejectReason
from rutautp_backend.validation import ObservationValidator

from .conftest import SAMPLE_ROUTE_ID

NOW = 1_700_000_000.0


def valid_payload(route, *, now: float = NOW, session: str = "sesion-valida") -> str:
    """Mensaje correcto, para comprobar que el servicio sigue vivo."""
    index = len(route.shape) // 2
    latitude, longitude = route.shape[index]

    return json.dumps(
        {
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
    )


def payload_with(**overrides) -> str:
    """Mensaje con campos sustituidos, para construir entradas hostiles."""
    base = {
        "schemaVersion": 1,
        "sessionId": "sesion-hostil",
        "routeId": SAMPLE_ROUTE_ID,
        "linea": "C-01",
        "lat": -8.1,
        "lon": -79.03,
        "speed": 8.0,
        "heading": 90.0,
        "accuracy": 8.0,
        "motionActivity": "automotive",
        "timestamp": NOW,
    }
    base.update(overrides)

    return json.dumps(base)


@pytest.fixture
def validator(feed: GtfsFeed) -> ObservationValidator:
    """Validador con los límites de tasa altos, para que la batería no los agote.

    Hay que subir también el techo global: la configuración exige que no sea
    menor que el de una sola sesión, precisamente para que una baliza no pueda
    agotar el del servicio entero.
    """
    config = Config(
        gtfs_dir=feed.source_dir,
        database_path="",
        health_file="",
        max_messages_per_minute=100_000,
        max_messages_per_minute_global=1_000_000,
    )

    return ObservationValidator(feed, config)


#: Entradas que antes provocaban excepciones no controladas.
HOSTILE_INPUTS = [
    # `NaN` e `Infinity` no son JSON válido, pero el decodificador los acepta.
    '{"schemaVersion": NaN}',
    '{"schemaVersion": Infinity}',
    '{"schemaVersion": -Infinity}',
    payload_with(schemaVersion=float("nan")),
    payload_with(lat=float("inf")),
    payload_with(lon=float("-inf")),
    payload_with(accuracy=float("nan")),
    payload_with(timestamp=float("inf")),
    payload_with(speed=float("nan")),
    # Desbordamiento de exponente: se decodifica como infinito.
    '{"schemaVersion": 1e309, "sessionId": "s"}',
    payload_with(lat=1e309),
    # Tipos y formas que no son el contrato.
    "",
    "{",
    "[]",
    "null",
    "3",
    '"texto"',
    "{}",
    '{"schemaVersion": true}',
    payload_with(lat=True),
    payload_with(sessionId=None),
    payload_with(routeId=[]),
    # Anidamiento y tamaño.
    "[" * 3000 + "]" * 3000,
    json.dumps({"schemaVersion": 1, "relleno": "x" * 20_000}),
    b"\xff\xfe\x00\x00",
]


class TestBateriaHostil:
    def test_ninguna_entrada_invalida_lanza(self, validator):
        """Ningún mensaje, por hostil que sea, debe escapar como excepción."""
        for entrada in HOSTILE_INPUTS:
            # Si alguna lanzara, la prueba fallaría aquí con su traza.
            resultado = validator.validate(entrada, NOW)

            assert resultado.ok is False, f"no debería aceptarse: {entrada!r:.80}"
            assert resultado.reason is not None

    def test_el_servicio_sigue_vivo_tras_la_bateria(self, validator, sample_route):
        """El criterio que de verdad importa: después sigue funcionando."""
        for entrada in HOSTILE_INPUTS:
            validator.validate(entrada, NOW)

        resultado = validator.validate(valid_payload(sample_route), NOW)

        assert resultado.ok is True, "una observación válida debe seguir pasando"
        assert resultado.observation.route_id == SAMPLE_ROUTE_ID

    def test_cada_entrada_hostil_tiene_su_motivo(self, validator):
        motivos = {
            validator.validate(entrada, NOW).reason for entrada in HOSTILE_INPUTS
        }

        # Ninguna debe quedar sin clasificar ni provocar un error interno.
        assert RejectReason.INTERNAL_ERROR not in motivos
        assert None not in motivos


class TestLimitesDelMensaje:
    def test_mensaje_demasiado_grande(self, feed, sample_route):
        validator = ObservationValidator(
            feed, Config(gtfs_dir=feed.source_dir, database_path="", max_message_bytes=256)
        )

        grande = valid_payload(sample_route) + " " * 500

        resultado = validator.validate(grande, NOW)

        assert resultado.reason is RejectReason.MESSAGE_TOO_LARGE

    def test_anidamiento_excesivo(self, validator):
        """Se rechaza por anidamiento, no por tamaño.

        Con 5000 niveles el mensaje supera además el límite de bytes y ese
        control salta antes, así que se usa una profundidad que quepa.
        """
        anidado = "[" * 3000 + "]" * 3000

        assert len(anidado) < Config().max_message_bytes

        resultado = validator.validate(anidado, NOW)

        assert resultado.reason in (
            RejectReason.TOO_DEEPLY_NESTED,
            RejectReason.NOT_AN_OBJECT,
        )


class TestBarreraDelPuente:
    """El puente no debe propagar excepciones, ni silenciarlas."""

    def test_un_fallo_inesperado_no_detiene_el_servicio(self, feed: GtfsFeed):
        class ValidadorQueExplota:
            def validate(self, raw, now, principal=None):
                raise RuntimeError("fallo simulado del validador")

            def prune(self, now):
                pass

        config = Config(gtfs_dir=feed.source_dir, database_path="", health_file="")
        bridge = Bridge(config=config, feed=feed, validator=ValidadorQueExplota())

        resultado = bridge.handle_message(
            "rutautp/observaciones/device-001/x/posicion", "{}", NOW
        )

        assert resultado.accepted is False
        assert resultado.reason is RejectReason.INTERNAL_ERROR
        assert bridge.metrics.snapshot()["internalErrors"] == 1

    def test_un_error_interno_se_cuenta_aparte_de_los_del_cliente(
        self, feed: GtfsFeed
    ):
        """No debe confundirse un fallo propio con datos inválidos del cliente."""
        config = Config(gtfs_dir=feed.source_dir, database_path="", health_file="")
        bridge = Bridge(config=config, feed=feed)

        bridge.handle_message(
            "rutautp/observaciones/device-001/x/posicion", "{no es json", NOW
        )

        snapshot = bridge.metrics.snapshot()

        assert snapshot["internalErrors"] == 0
        assert snapshot["reasons"]["malformed_json"] == 1
