"""Pruebas de los límites que no dependen de una sola sesión (B05).

Cubren las dos defensas que se añadieron al comprobar que la geometría **no**
demuestra por sí sola que exista un vehículo:

1. **Techo global.** El `sessionId` lo elige el cliente, así que el límite por
   sesión se elude rotándolo. Sin un tope del servicio entero, el trabajo del
   servidor no tiene cota.
2. **Continuidad de trayectoria.** Una posición inventada puede estar sobre el
   recorrido; lo que no puede es encajar con la anterior de su propia sesión si
   implicaría un desplazamiento imposible.
"""

from __future__ import annotations

import json

import pytest

from rutautp_backend.config import Config, ConfigError
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.models import RejectReason
from rutautp_backend.validation import ObservationValidator

from .conftest import SAMPLE_ROUTE_ID

NOW = 1_700_000_000.0


def payload_at(route, index: int, *, now: float = NOW, session: str = "s-1") -> str:
    """Observación sobre el vértice `index` del recorrido real."""
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


@pytest.fixture
def validator(feed: GtfsFeed) -> ObservationValidator:
    """Límites altos para que las pruebas de continuidad no topen con el de tasa."""
    config = Config(
        gtfs_dir=feed.source_dir,
        database_path="",
        health_file="",
        max_messages_per_minute=100_000,
        max_messages_per_minute_global=1_000_000,
    )

    return ObservationValidator(feed, config)


class TestTechoGlobal:
    """Rotar sesiones no debe permitir un crecimiento ilimitado del trabajo."""

    def test_rotar_sesiones_no_elude_el_techo(self, feed: GtfsFeed, sample_route):
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file="",
            max_messages_per_minute=2,
            max_messages_per_minute_global=5,
        )
        validator = ObservationValidator(feed, config)

        motivos = []

        # Seis sesiones distintas, una observación cada una: ninguna agota su
        # propio límite, pero el servicio ya superó su techo.
        for index in range(6):
            resultado = validator.validate(
                payload_at(sample_route, 100 + index, session=f"rotada-{index}"),
                NOW,
            )
            motivos.append(resultado.reason)

        assert motivos[-1] is RejectReason.GLOBAL_RATE_LIMITED
        assert motivos[:5] == [None] * 5

    def test_el_motivo_es_distinto_del_de_sesion(self, feed: GtfsFeed, sample_route):
        """Para poder distinguir «una baliza se pasa» de «el servicio va a tope»."""
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file="",
            max_messages_per_minute=1,
            max_messages_per_minute_global=2,
        )
        validator = ObservationValidator(feed, config)

        validator.validate(payload_at(sample_route, 100, session="a"), NOW)

        # La segunda de la misma sesión agota su límite propio...
        propio = validator.validate(payload_at(sample_route, 101, session="a"), NOW)

        assert propio.reason is RejectReason.RATE_LIMITED

        # ...y la de otra sesión agota el global.
        validator.validate(payload_at(sample_route, 102, session="b"), NOW)
        global_ = validator.validate(payload_at(sample_route, 103, session="c"), NOW)

        assert global_.reason is RejectReason.GLOBAL_RATE_LIMITED

    def test_la_ventana_global_se_libera(self, feed: GtfsFeed, sample_route):
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file="",
            max_messages_per_minute=1,
            max_messages_per_minute_global=2,
        )
        validator = ObservationValidator(feed, config)

        validator.validate(payload_at(sample_route, 100, session="a"), NOW)
        validator.validate(payload_at(sample_route, 101, session="b"), NOW)

        assert (
            validator.validate(payload_at(sample_route, 102, session="c"), NOW).reason
            is RejectReason.GLOBAL_RATE_LIMITED
        )

        # Un minuto después la ventana ya no contiene aquellos mensajes.
        later = NOW + 61

        assert validator.validate(
            payload_at(sample_route, 103, session="d", now=later), later
        ).ok


class TestContinuidad:
    def test_la_primera_observacion_de_una_sesion_siempre_pasa(
        self, validator, sample_route
    ):
        """No hay historial con el que comparar, así que no hay nada que rechazar."""
        assert validator.validate(payload_at(sample_route, 100), NOW).ok

    def test_un_salto_imposible_se_rechaza(self, validator, sample_route):
        """17 km en un segundo no los hace ningún vehículo urbano."""
        assert validator.validate(payload_at(sample_route, 100), NOW).ok

        resultado = validator.validate(
            payload_at(sample_route, 400, now=NOW + 1), NOW + 1
        )

        assert resultado.reason is RejectReason.IMPLAUSIBLE_JUMP

    def test_un_avance_normal_se_acepta(self, validator, sample_route):
        """Un vértice del shape son ~57 m: perfectamente posible en un segundo."""
        assert validator.validate(payload_at(sample_route, 100), NOW).ok

        assert validator.validate(
            payload_at(sample_route, 101, now=NOW + 1), NOW + 1
        ).ok

    def test_una_espera_larga_permite_un_desplazamiento_mayor(
        self, validator, sample_route
    ):
        """El margen crece con el tiempo transcurrido, no es un radio fijo."""
        assert validator.validate(payload_at(sample_route, 100), NOW).ok

        # 60 s después, 300 vértices (~17 km) siguen siendo demasiado, pero el
        # mismo salto que se rechazaba en 1 s debe evaluarse contra 60 s.
        resultado = validator.validate(
            payload_at(sample_route, 130, now=NOW + 60), NOW + 60
        )

        assert resultado.ok

    def test_un_mensaje_desordenado_no_se_rechaza_por_continuidad(
        self, validator, sample_route
    ):
        """Un mensaje viejo no dice nada de la trayectoria: lo ignora el agregador."""
        assert validator.validate(
            payload_at(sample_route, 400, now=NOW + 10), NOW + 10
        ).ok

        resultado = validator.validate(payload_at(sample_route, 100, now=NOW), NOW)

        assert resultado.reason is not RejectReason.IMPLAUSIBLE_JUMP
        assert resultado.ok

    def test_sesiones_distintas_no_comparten_trayectoria(
        self, validator, sample_route
    ):
        """El historial es por sesión: dos pasajeros no se estorban."""
        assert validator.validate(payload_at(sample_route, 100, session="a"), NOW).ok

        assert validator.validate(
            payload_at(sample_route, 400, session="b", now=NOW + 1), NOW + 1
        ).ok

    def test_solo_se_recuerda_lo_aceptado(self, validator, sample_route):
        """Una observación rechazada no debe convertirse en referencia."""
        assert validator.validate(payload_at(sample_route, 100), NOW).ok

        # Salto imposible: se rechaza y NO debe quedar como referencia.
        assert (
            validator.validate(payload_at(sample_route, 400, now=NOW + 1), NOW + 1).reason
            is RejectReason.IMPLAUSIBLE_JUMP
        )

        # Desde el vértice 100, avanzar 300 sigue siendo imposible en 1 s.
        assert (
            validator.validate(payload_at(sample_route, 300, now=NOW + 2), NOW + 2).reason
            is RejectReason.IMPLAUSIBLE_JUMP
        )

    def test_el_estado_se_poda(self, validator, sample_route):
        validator.validate(payload_at(sample_route, 100), NOW)

        assert validator.tracked_continuity_sessions == 1

        validator.prune(NOW + 10_000)

        assert validator.tracked_continuity_sessions == 0

    def test_la_ruta_sigue_comprobando_se(self, validator, sample_route):
        """La continuidad no sustituye a las comprobaciones anteriores."""
        assert validator.validate(payload_at(sample_route, 100), NOW).ok

        fuera = json.loads(payload_at(sample_route, 101, now=NOW + 1))
        fuera["lat"] = -8.9

        assert validator.validate(
            json.dumps(fuera), NOW + 1
        ).reason is RejectReason.TOO_FAR_FROM_ROUTE


class TestConfiguracionDeLosLimites:
    def test_el_techo_global_no_puede_ser_menor_que_el_de_sesion(self):
        """Una sola baliza agotaría el techo del servicio entero."""
        with pytest.raises(ConfigError, match="MAX_MSGS_PER_MINUTE_GLOBAL"):
            Config(
                max_messages_per_minute=20,
                max_messages_per_minute_global=10,
            )

    def test_los_valores_por_defecto_son_coherentes(self):
        config = Config()

        assert config.max_messages_per_minute_global >= config.max_messages_per_minute
        assert config.max_displacement_margin_m > 0

    @pytest.mark.parametrize(
        "variable,valor",
        [
            ("BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL", "0"),
            ("BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL", "NaN"),
            ("BACKEND_MAX_DISPLACEMENT_MARGIN_M", "-1"),
            ("BACKEND_MAX_DISPLACEMENT_MARGIN_M", "mucho"),
        ],
    )
    def test_valores_invalidos_detienen_el_arranque(self, variable, valor):
        with pytest.raises(ConfigError, match=variable):
            Config.from_env({variable: valor})
