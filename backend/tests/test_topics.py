"""Pruebas de los filtros de tópicos MQTT.

Existen por un bug real: el backend se suscribía a `rutautp/observaciones/+`
(tres niveles) mientras el cliente publica en
`rutautp/observaciones/{sessionId}/posicion` (cuatro). El comodín `+` casa
exactamente un nivel y no cruza separadores, así que **no llegaba ni un
mensaje**.

Ninguna prueba unitaria podía detectarlo, porque todas inyectan el publicador y
nunca abren un socket. Lo encontró la prueba de humo con un broker real
(`tools/smoke_test.sh`). Estas pruebas son la red de seguridad barata para que
no vuelva a pasar.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from rutautp_backend.config import Config

REPO_ROOT = Path(__file__).resolve().parents[2]

MQTT_OBSERVATION_PUBLISHER = (
    REPO_ROOT / "RutaUTP/Services/Tracking/Publishers/MQTTObservationPublisher.swift"
)
MQTT_TRACKING_PROVIDER = (
    REPO_ROOT / "RutaUTP/Services/Tracking/Providers/MQTTTrackingProvider.swift"
)


def filter_matches(topic_filter: str, topic: str) -> bool:
    """Implementación mínima de las reglas de filtrado de MQTT.

    `+` casa exactamente un nivel; `#` casa el resto y solo puede ir al final.
    """
    filter_levels = topic_filter.split("/")
    topic_levels = topic.split("/")

    for index, filter_level in enumerate(filter_levels):
        if filter_level == "#":
            return index == len(filter_levels) - 1

        if index >= len(topic_levels):
            return False

        if filter_level == "+":
            continue

        if filter_level != topic_levels[index]:
            return False

    return len(filter_levels) == len(topic_levels)


class TestFiltroDeSuscripcion:
    def test_el_filtro_por_defecto_recibe_la_observacion_del_cliente(self):
        """El caso que falló: el filtro debe tener los mismos niveles."""
        topic = "rutautp/observaciones/3f2a1b/posicion"

        assert filter_matches(Config().observations_topic, topic) is True

    def test_el_filtro_viejo_no_habria_casado(self):
        """Deja constancia del bug para que no se reintroduzca."""
        topic = "rutautp/observaciones/3f2a1b/posicion"

        assert filter_matches("rutautp/observaciones/+", topic) is False

    def test_el_comodin_no_cruza_separadores(self):
        assert filter_matches("a/+", "a/b") is True
        assert filter_matches("a/+", "a/b/c") is False

    def test_el_filtro_por_defecto_no_recibe_otros_topicos(self):
        config = Config()

        assert filter_matches(config.observations_topic, "rutautp/observaciones/x") is False
        assert filter_matches(config.observations_topic, "rutautp/vehiculos/x/posicion") is False

    def test_el_filtro_por_defecto_solo_acepta_el_sufijo_posicion(self):
        assert (
            filter_matches(
                Config().observations_topic, "rutautp/observaciones/x/otra-cosa"
            )
            is False
        )


class TestContraElClienteSwift:
    """Comprueba que el formato asumido es el que publica de verdad el cliente."""

    def test_el_cliente_publica_en_cuatro_niveles(self):
        if not MQTT_OBSERVATION_PUBLISHER.is_file():
            pytest.skip("no se encontró el cliente Swift")

        source = MQTT_OBSERVATION_PUBLISHER.read_text(encoding="utf-8")

        # El tópico se arma en Swift como:
        #   "rutautp/observaciones/" + "\(sessionID)/posicion"
        # así que el prefijo y el sufijo aparecen como literales separados.
        assert '"rutautp/observaciones/"' in source
        assert '/posicion"' in source

        # Reconstruido, tiene cuatro niveles: `+` casaría solo tres.
        client_topic = "rutautp/observaciones/session-abc/posicion"

        assert len(client_topic.split("/")) == 4
        assert filter_matches("rutautp/observaciones/+", client_topic) is False
        assert filter_matches(Config().observations_topic, client_topic) is True

    def test_el_cliente_consume_el_topico_que_publicamos(self):
        if not MQTT_TRACKING_PROVIDER.is_file():
            pytest.skip("no se encontró el cliente Swift")

        source = MQTT_TRACKING_PROVIDER.read_text(encoding="utf-8")

        match = re.search(r'topic\s*=\s*"([^"]+)"', source)

        assert match is not None, "no se encontró el tópico de suscripción del cliente"

        client_filter = match.group(1)

        assert client_filter == "rutautp/vehiculos/+/posicion"

        # Lo que publicamos debe casar con lo que el cliente escucha.
        topic = Config().vehicles_topic("17350695-01")

        assert filter_matches(client_filter, topic) is True
