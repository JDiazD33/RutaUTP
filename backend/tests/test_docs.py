"""Coherencia entre la documentación y el código (Q02).

Existen porque el README ya mintió una vez de forma silenciosa: documentaba
`BACKEND_MERGE_WINDOW_S` con valor `90` mientras el código usaba `60`. Y no era
un detalle inocente: la configuración exige `MERGE_WINDOW_S ≤ VEHICLE_TTL_S`, así
que el valor documentado describía un ajuste que el propio código **rechaza**.

Una tabla de configuración desactualizada es peor que no tenerla: alguien la
lee, ajusta un valor esperando un comportamiento, y obtiene otro sin ningún
error. Estas pruebas convierten ese desfase en un fallo de la suite.
"""

from __future__ import annotations

import dataclasses
import re
from pathlib import Path

from rutautp_backend.config import Config

README = Path(__file__).resolve().parents[1] / "README.md"

#: Campo de `Config` -> nombre de la variable de entorno que lo alimenta.
#:
#: Es explícito y no derivado del nombre a propósito: la correspondencia no es
#: mecánica (`host` -> `MQTT_HOST`, `database_path` -> `BACKEND_DB_PATH`), y una
#: heurística daría falsos positivos justo donde más importa.
VARIABLES: dict[str, str] = {
    "host": "MQTT_HOST",
    "port": "MQTT_PORT",
    "username": "MQTT_USERNAME",
    "password": "MQTT_PASSWORD",
    "use_tls": "MQTT_TLS",
    "ca_cert": "MQTT_CA_CERT",
    "client_id": "MQTT_CLIENT_ID",
    "gtfs_dir": "GTFS_DIR",
    "observations_topic": "BACKEND_OBSERVATIONS_TOPIC",
    "vehicles_topic_prefix": "BACKEND_VEHICLES_TOPIC_PREFIX",
    "database_path": "BACKEND_DB_PATH",
    "retention_days": "BACKEND_DB_RETENTION_DAYS",
    "health_file": "BACKEND_HEALTH_FILE",
    "health_max_age_s": "BACKEND_HEALTH_MAX_AGE_S",
    "max_message_bytes": "BACKEND_MAX_MESSAGE_BYTES",
    "max_accuracy_m": "BACKEND_MAX_ACCURACY_M",
    "max_age_s": "BACKEND_MAX_AGE_S",
    "max_clock_skew_s": "BACKEND_MAX_CLOCK_SKEW_S",
    "max_distance_to_route_m": "BACKEND_MAX_DISTANCE_TO_ROUTE_M",
    "max_heading_diff_deg": "BACKEND_MAX_HEADING_DIFF_DEG",
    "max_speed_ms": "BACKEND_MAX_SPEED_MS",
    "max_messages_per_minute": "BACKEND_MAX_MSGS_PER_MINUTE",
    "max_messages_per_minute_global": "BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL",
    "max_displacement_margin_m": "BACKEND_MAX_DISPLACEMENT_MARGIN_M",
    "dedupe_window_s": "BACKEND_DEDUPE_WINDOW_S",
    "merge_radius_m": "BACKEND_MERGE_RADIUS_M",
    "merge_window_s": "BACKEND_MERGE_WINDOW_S",
    "merge_max_heading_diff_deg": "BACKEND_MERGE_MAX_HEADING_DIFF_DEG",
    "vehicle_ttl_s": "BACKEND_VEHICLE_TTL_S",
    "publish_interval_s": "BACKEND_PUBLISH_INTERVAL_S",
    "vehicle_namespace": "BACKEND_VEHICLE_NAMESPACE",
    "log_level": "BACKEND_LOG_LEVEL",
    "log_json": "BACKEND_LOG_JSON",
}

#: Variables sin valor por defecto literal. Se documentan con «—» o con una
#: descripción («aleatorio»), así que no hay nada que comparar: lo que se
#: comprueba es que la fila exista.
SIN_VALOR_FIJO = {
    "MQTT_USERNAME",
    "MQTT_PASSWORD",
    "MQTT_CA_CERT",
    "MQTT_CLIENT_ID",
    "BACKEND_VEHICLE_NAMESPACE",
}

#: Campos que el código guarda **resueltos** (ruta absoluta) y el README
#: documenta **relativos**, porque es lo útil para quien configura el servicio.
#: Se compara el nombre del archivo o directorio, que es la parte significativa.
RUTAS = {"gtfs_dir", "database_path", "health_file"}


def tabla_documentada() -> dict[str, str]:
    """`VARIABLE -> valor por defecto` tal como figura en el README.

    La celda puede contener un valor entrecomillado, un guion o una frase
    («aleatorio por arranque»). Se toma el primer valor entrecomillado; las
    filas que no tienen ninguno se omiten, porque documentan precisamente que no
    hay valor por defecto.
    """
    filas = re.findall(
        r"^\|\s*`([A-Z_]+)`\s*\|([^|]*)\|",
        README.read_text(encoding="utf-8"),
        re.MULTILINE,
    )

    documentadas: dict[str, str] = {}

    for nombre, celda in filas:
        valor = re.search(r"`([^`]+)`", celda)

        if valor:
            documentadas[nombre] = valor.group(1)

    return documentadas


def como_texto(valor) -> str:
    """Representación del valor tal como se escribe en la tabla."""
    if isinstance(valor, bool):
        return "1" if valor else "0"

    if isinstance(valor, float) and valor == int(valor):
        return str(int(valor))

    return str(valor)


class TestCobertura:
    def test_todos_los_campos_de_config_estan_mapeados(self):
        """Un campo nuevo obliga a decidir su nombre de variable."""
        campos = {campo.name for campo in dataclasses.fields(Config)}
        mapeados = set(VARIABLES)

        assert campos == mapeados, (
            f"campos de Config sin entrada en VARIABLES: {campos - mapeados}"
        )

    def test_todas_las_variables_estan_documentadas(self):
        documentadas = tabla_documentada()

        faltan = [
            variable
            for variable in VARIABLES.values()
            if variable not in documentadas
            and variable not in SIN_VALOR_FIJO
        ]

        assert faltan == [], (
            "variables de configuración sin documentar en backend/README.md: "
            f"{faltan}"
        )

    def test_las_variables_sin_valor_fijo_tambien_aparecen(self):
        """Que no tengan valor por defecto no las exime de estar en la tabla."""
        filas = set(
            re.findall(
                r"^\|\s*`([A-Z_]+)`\s*\|",
                README.read_text(encoding="utf-8"),
                re.MULTILINE,
            )
        )

        faltan = sorted(SIN_VALOR_FIJO - filas)

        assert faltan == [], (
            "variables documentadas sin valor por defecto que no aparecen en "
            f"ninguna fila: {faltan}"
        )

    def test_no_hay_variables_documentadas_que_ya_no_existan(self):
        """Una variable retirada no debe seguir en la tabla."""
        documentadas = tabla_documentada()

        sobrantes = [
            nombre
            for nombre in documentadas
            if nombre.startswith("BACKEND_") and nombre not in VARIABLES.values()
        ]

        assert sobrantes == [], (
            f"el README documenta variables que ya no existen: {sobrantes}"
        )

    def test_la_tabla_se_parsea_entera(self):
        """Si cambiara el formato del README, esta prueba lo delata.

        Sin ella, un cambio de formato dejaría la tabla vacía y todas las demás
        comprobaciones pasarían por no encontrar nada que comparar: el fallo más
        silencioso posible en una prueba de documentación.
        """
        documentadas = tabla_documentada()
        esperadas = len(VARIABLES) - len(SIN_VALOR_FIJO)

        assert len(documentadas) == esperadas, (
            f"se esperaban {esperadas} valores documentados y se leyeron "
            f"{len(documentadas)}; puede haber cambiado el formato de la tabla"
        )


class TestValores:
    def test_los_valores_por_defecto_coinciden_con_el_codigo(self):
        """El error que motivó esta prueba: la tabla decía 90 y el código 60."""
        config = Config()
        documentadas = tabla_documentada()

        discrepancias = []

        for campo, variable in VARIABLES.items():
            if variable not in documentadas:
                continue

            real = getattr(config, campo)
            documentado = documentadas[variable]

            if campo in RUTAS:
                coincide = Path(como_texto(real)).name == Path(documentado).name
            else:
                coincide = documentado == como_texto(real)

            if not coincide:
                discrepancias.append(
                    f"{variable}: README={documentado!r} "
                    f"código={como_texto(real)!r}"
                )

        assert discrepancias == [], (
            "la tabla de configuración no coincide con el código:\n  "
            + "\n  ".join(discrepancias)
        )
