"""Regresiones de validación de configuración (B07).

Antes, un valor inválido se sustituía por el de por defecto en silencio: un
puerto mal escrito conectaba al 1883 y un TTL negativo desactivaba la caducidad,
sin que nadie se enterara. Ahora el arranque falla nombrando la variable.
"""

from __future__ import annotations

import pytest

from rutautp_backend.config import Config, ConfigError


class TestValoresPorDefecto:
    def test_la_configuracion_por_defecto_es_valida(self):
        config = Config()

        assert config.port == 1883
        assert config.vehicle_ttl_s >= config.merge_window_s
        assert config.min_publish_principals == 2

    def test_entorno_vacio_da_los_valores_por_defecto(self):
        config = Config.from_env({})

        assert config.host == "127.0.0.1"
        assert config.port == 1883
        assert config.use_tls is False


class TestPuerto:
    def test_tls_implica_8883(self):
        assert Config.from_env({"MQTT_TLS": "1"}).port == 8883

    def test_puerto_explicito_gana(self):
        config = Config.from_env({"MQTT_TLS": "1", "MQTT_PORT": "1234"})

        assert config.port == 1234

    @pytest.mark.parametrize("valor", ["0", "-1", "70000", "abc", "NaN", "Infinity"])
    def test_puerto_invalido_detiene_el_arranque(self, valor):
        with pytest.raises(ConfigError, match="MQTT_PORT"):
            Config.from_env({"MQTT_PORT": valor})

    def test_puerto_fuera_de_rango_en_construccion_directa(self):
        with pytest.raises(ConfigError, match="MQTT_PORT"):
            Config(port=0)

    def test_puerto_decimal_no_se_trunca(self):
        with pytest.raises(ConfigError, match="MQTT_PORT"):
            Config.from_env({"MQTT_PORT": "1883.9"})


class TestNumerosInvalidos:
    @pytest.mark.parametrize(
        "variable",
        [
            "BACKEND_MAX_ACCURACY_M",
            "BACKEND_MAX_AGE_S",
            "BACKEND_MAX_DISTANCE_TO_ROUTE_M",
            "BACKEND_MERGE_RADIUS_M",
            "BACKEND_VEHICLE_TTL_S",
            "BACKEND_PUBLISH_INTERVAL_S",
        ],
    )
    def test_no_finito_detiene_el_arranque(self, variable):
        with pytest.raises(ConfigError, match=variable):
            Config.from_env({variable: "NaN"})

    @pytest.mark.parametrize(
        "variable",
        ["BACKEND_MAX_ACCURACY_M", "BACKEND_MERGE_RADIUS_M", "BACKEND_MAX_AGE_S"],
    )
    def test_valor_no_numerico_detiene_el_arranque(self, variable):
        with pytest.raises(ConfigError, match=variable):
            Config.from_env({variable: "mucho"})

    def test_ttl_negativo_detiene_el_arranque(self):
        with pytest.raises(ConfigError, match="BACKEND_VEHICLE_TTL_S"):
            Config.from_env({"BACKEND_VEHICLE_TTL_S": "-5"})

    def test_limite_de_mensajes_menor_que_uno(self):
        with pytest.raises(ConfigError, match="BACKEND_MAX_MSGS_PER_MINUTE"):
            Config.from_env({"BACKEND_MAX_MSGS_PER_MINUTE": "0"})

    def test_retencion_negativa(self):
        with pytest.raises(ConfigError, match="BACKEND_DB_RETENTION_DAYS"):
            Config.from_env({"BACKEND_DB_RETENTION_DAYS": "-1"})

    def test_desfase_de_reloj_cero_es_valido(self):
        assert Config.from_env({"BACKEND_MAX_CLOCK_SKEW_S": "0"}).max_clock_skew_s == 0

    @pytest.mark.parametrize(
        "variable",
        [
            "BACKEND_MAX_MESSAGE_BYTES",
            "BACKEND_MAX_MSGS_PER_MINUTE",
            "BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL",
            "BACKEND_MIN_PUBLISH_PRINCIPALS",
        ],
    )
    def test_los_limites_enteros_no_truncan_decimales(self, variable):
        with pytest.raises(ConfigError, match=variable):
            Config.from_env({variable: "20.9"})

    @pytest.mark.parametrize(
        ("field_name", "variable"),
        [
            ("port", "MQTT_PORT"),
            ("max_message_bytes", "BACKEND_MAX_MESSAGE_BYTES"),
            ("max_messages_per_minute", "BACKEND_MAX_MSGS_PER_MINUTE"),
            (
                "max_messages_per_minute_global",
                "BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL",
            ),
            ("min_publish_principals", "BACKEND_MIN_PUBLISH_PRINCIPALS"),
        ],
    )
    def test_construccion_directa_tambien_exige_enteros(
        self, field_name, variable
    ):
        with pytest.raises(ConfigError, match=variable):
            Config(**{field_name: 20.5})

    def test_quorum_menor_que_uno_se_rechaza(self):
        with pytest.raises(ConfigError, match="BACKEND_MIN_PUBLISH_PRINCIPALS"):
            Config.from_env({"BACKEND_MIN_PUBLISH_PRINCIPALS": "0"})


class TestRelacionesEntreParametros:
    def test_el_ttl_no_puede_ser_menor_que_la_ventana_de_agrupacion(self):
        """Un vehículo que caduca antes de cerrar su ventana se recrea siempre.

        Es el defecto que tenían los valores por defecto: 60 s de TTL contra
        90 s de ventana, así que la ventana nunca llegaba a aplicarse entera.
        """
        with pytest.raises(ConfigError, match="BACKEND_VEHICLE_TTL_S"):
            Config.from_env(
                {
                    "BACKEND_VEHICLE_TTL_S": "30",
                    "BACKEND_MERGE_WINDOW_S": "90",
                }
            )

    def test_la_antiguedad_maxima_debe_superar_el_desfase_de_reloj(self):
        with pytest.raises(ConfigError, match="BACKEND_MAX_AGE_S"):
            Config.from_env(
                {
                    "BACKEND_MAX_AGE_S": "5",
                    "BACKEND_MAX_CLOCK_SKEW_S": "10",
                }
            )

    def test_la_ventana_de_agrupacion_por_defecto_es_alcanzable(self):
        """El valor por defecto debe ser coherente consigo mismo."""
        config = Config()

        assert config.merge_window_s <= config.vehicle_ttl_s


class TestParametrosRetirados:
    def test_ya_no_existe_la_velocidad_minima(self):
        """No se exigía en la validación, así que era un mando que no hacía nada.

        El servidor no puede exigir una velocidad mínima: el bus parado en un
        semáforo publica ~0 y desaparecería del mapa.
        """
        assert not hasattr(Config(), "min_speed_ms")

        # Aunque alguien la defina en el entorno, no debe cambiar nada.
        config = Config.from_env({"BACKEND_MIN_SPEED_MS": "4"})

        assert not hasattr(config, "min_speed_ms")
