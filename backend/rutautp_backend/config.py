"""Configuración del backend, leída de variables de entorno.

Las variables del broker (`MQTT_*`) usan los mismos nombres que el Scheme de
Xcode del cliente, para que copiar la configuración de un lado al otro no
requiera traducciones. Los ajustes propios del backend llevan el prefijo
`BACKEND_`.

Ninguna credencial vive en el repositorio.

**Un valor inválido detiene el arranque con un mensaje que lo nombra.** Antes se
usaba el valor por defecto en silencio, lo que convertía un error de tecleo en un
comportamiento distinto al esperado sin que nadie se enterara: un puerto mal
escrito conectaba al 1883, y un TTL negativo desactivaba la caducidad.
"""

from __future__ import annotations

import math
import os
import uuid
from dataclasses import dataclass, field
from pathlib import Path

# `backend/rutautp_backend/config.py` -> raíz del repositorio
REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_GTFS_DIR = REPO_ROOT / "gtfs"

DEFAULT_DATABASE_PATH = REPO_ROOT / "backend" / "data" / "rutautp.sqlite"

#: Latido que escribe el puente para que un supervisor pueda saber si está vivo.
DEFAULT_HEALTH_PATH = REPO_ROOT / "backend" / "data" / "health.json"

TRUTHY = {"1", "true", "yes", "on"}

#: Un mensaje de observación legítimo ronda los 300 bytes.
DEFAULT_MAX_MESSAGE_BYTES = 8192

MIN_PORT = 1
MAX_PORT = 65_535


class ConfigError(ValueError):
    """Una variable de entorno tiene un valor que no se puede usar."""


def _flag(env: dict[str, str], name: str, default: bool = False) -> bool:
    raw = env.get(name)

    if raw is None:
        return default

    return raw.strip().lower() in TRUTHY


def _number(
    env: dict[str, str],
    name: str,
    default: float,
    *,
    minimum: float | None = None,
    maximum: float | None = None,
    allow_zero: bool = False,
) -> float:
    """Lee un número, o falla nombrando la variable.

    Se comprueba la finitud: `NaN` e `Infinity` son valores que `float()` acepta
    y que rompen cualquier comparación más adelante.
    """
    raw = env.get(name)

    if raw is None or not raw.strip():
        return default

    try:
        value = float(raw)
    except ValueError as error:
        raise ConfigError(f"{name}={raw!r} no es un número") from error

    if not math.isfinite(value):
        raise ConfigError(f"{name}={raw!r} no es finito")

    if allow_zero:
        if value < 0:
            raise ConfigError(f"{name}={value} no puede ser negativo")
    elif value <= 0:
        raise ConfigError(f"{name}={value} debe ser mayor que cero")

    if minimum is not None and value < minimum:
        raise ConfigError(f"{name}={value} es menor que el mínimo {minimum}")

    if maximum is not None and value > maximum:
        raise ConfigError(f"{name}={value} supera el máximo {maximum}")

    return value


def _integer(
    env: dict[str, str],
    name: str,
    default: int,
    *,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int:
    """Lee un entero sin truncar silenciosamente una parte decimal."""
    value = _number(
        env,
        name,
        float(default),
        minimum=minimum,
        maximum=maximum,
    )

    if not value.is_integer():
        raise ConfigError(f"{name}={value} debe ser un número entero")

    return int(value)


@dataclass(frozen=True)
class Config:
    """Parámetros de ejecución del puente."""

    # ── Broker ────────────────────────────────────────────────────────────
    host: str = "127.0.0.1"
    port: int = 1883
    username: str = ""
    password: str = ""
    use_tls: bool = False
    ca_cert: str = ""
    client_id: str = field(default_factory=lambda: f"rutautp-backend-{uuid.uuid4()}")

    # ── Tópicos ───────────────────────────────────────────────────────────
    # El filtro debe tener los MISMOS niveles que el tópico real. El cliente
    # publica en `rutautp/observaciones/{sessionId}/posicion` (cuatro niveles);
    # suscribir a `rutautp/observaciones/+` (tres) no recibe nada, porque `+`
    # casa exactamente un nivel y no cruza separadores.
    observations_topic: str = "rutautp/observaciones/+/posicion"
    vehicles_topic_prefix: str = "rutautp/vehiculos"

    # ── Feed ──────────────────────────────────────────────────────────────
    gtfs_dir: Path = DEFAULT_GTFS_DIR

    # ── Persistencia ──────────────────────────────────────────────────────
    #: Ruta del histórico. Vacío desactiva la persistencia por completo.
    database_path: str = str(DEFAULT_DATABASE_PATH)
    #: Días de histórico conservados. `0` significa no borrar nunca.
    retention_days: float = 0.0

    # ── Validación ────────────────────────────────────────────────────────
    max_message_bytes: int = DEFAULT_MAX_MESSAGE_BYTES
    max_accuracy_m: float = 50.0
    max_age_s: float = 45.0
    max_clock_skew_s: float = 10.0
    max_distance_to_route_m: float = 50.0
    max_heading_diff_deg: float = 60.0
    max_speed_ms: float = 30.0
    max_messages_per_minute: int = 20
    #: Techo del servicio entero, independiente de la sesión.
    #:
    #: El `sessionId` lo elige el cliente, así que el límite por sesión se elude
    #: rotándolo: sin un tope global, un cliente comprometido puede forzar al
    #: servidor a validar geometría sin límite real. El valor por defecto (1800)
    #: da margen a unas 150 balizas legítimas publicando cada 5 s.
    max_messages_per_minute_global: int = 1800
    #: Margen, en metros, tolerado al comprobar la continuidad de una sesión.
    #:
    #: La comprobación compara la distancia recorrida con la que permitiría el
    #: techo de velocidad; este margen absorbe el ruido del GPS (que en la
    #: medida anterior puede ser de decenas de metros) para no rechazar
    #: observaciones legítimas.
    max_displacement_margin_m: float = 250.0
    dedupe_window_s: float = 120.0

    # ── Agregación ────────────────────────────────────────────────────────
    merge_radius_m: float = 300.0
    #: Cuánto tiempo después de su última observación un vehículo puede seguir
    #: absorbiendo observaciones de la misma unidad.
    #:
    #: Antes valía 90 s mientras el TTL valía 60 s, así que la ventana real
    #: nunca pasaba de 60: el vehículo caducaba antes de que se cerrara. Ahora
    #: vale lo que de verdad se aplicaba, y el invariante de abajo impide que
    #: vuelvan a divergir.
    merge_window_s: float = 60.0
    #: Cuánto sobrevive un vehículo sin recibir observaciones.
    #:
    #: Ojo: esto **no** retrasa lo que ve el usuario. La app poda las posiciones
    #: a los 45 s por su cuenta, así que el TTL solo decide durante cuánto
    #: tiempo un pasajero que vuelve a publicar recupera el mismo identificador
    #: en lugar de crear uno nuevo.
    vehicle_ttl_s: float = 60.0
    publish_interval_s: float = 5.0

    #: Diferencia de rumbo máxima para considerar que dos observaciones pueden
    #: ser del mismo vehículo.
    #:
    #: Una misma línea se recorre en los dos sentidos, así que dos unidades que
    #: se cruzan están a pocos metros y llevan rumbos opuestos. Sin este
    #: criterio, la de vuelta se fusionaría con la de ida.
    merge_max_heading_diff_deg: float = 90.0

    #: Espacio de nombres de los identificadores de vehículo.
    #:
    #: Vacío significa uno nuevo por arranque. Los ordinales se pierden al
    #: reiniciar, así que sin esto un `{ruta}-01` nuevo heredaría la identidad
    #: visible del `{ruta}-01` anterior, que puede seguir en el mapa de los
    #: usuarios hasta que caduque. Ver D02 del informe de correcciones.
    vehicle_namespace: str = ""

    # ── Salud ─────────────────────────────────────────────────────────────
    #: Ruta del latido que escribe el puente en cada ciclo de mantenimiento.
    #:
    #: Vacío lo desactiva. Existe para que un supervisor (systemd, Docker,
    #: cron) pueda distinguir tres situaciones que antes se confundían:
    #: el servicio está sano, está desconectado del broker, o se murió.
    health_file: str = str(DEFAULT_HEALTH_PATH)
    #: Antigüedad máxima tolerada del latido, en segundos.
    health_max_age_s: float = 30.0

    # ── Observabilidad ────────────────────────────────────────────────────
    log_level: str = "INFO"
    log_json: bool = True

    def __post_init__(self) -> None:
        """Comprueba los invariantes, también para una construcción directa."""
        integer_fields = {
            "port": "MQTT_PORT",
            "max_message_bytes": "BACKEND_MAX_MESSAGE_BYTES",
            "max_messages_per_minute": "BACKEND_MAX_MSGS_PER_MINUTE",
            "max_messages_per_minute_global":
                "BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL",
        }

        for field_name, variable_name in integer_fields.items():
            value = getattr(self, field_name)

            # `bool` es subclase de `int` en Python, pero `True` no es una
            # configuración válida para un puerto o un límite cuantitativo.
            if isinstance(value, bool) or not isinstance(value, int):
                raise ConfigError(
                    f"{variable_name}={value!r} debe ser un número entero"
                )

        if not MIN_PORT <= self.port <= MAX_PORT:
            raise ConfigError(
                f"MQTT_PORT fuera de rango: {self.port} "
                f"(debe estar entre {MIN_PORT} y {MAX_PORT})"
            )

        if self.max_messages_per_minute < 1:
            raise ConfigError(
                f"BACKEND_MAX_MSGS_PER_MINUTE={self.max_messages_per_minute} "
                "debe ser al menos 1"
            )

        if self.max_messages_per_minute_global < 1:
            raise ConfigError(
                f"BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL="
                f"{self.max_messages_per_minute_global} debe ser al menos 1"
            )

        # Un techo global por debajo del de una sola sesión haría que una baliza
        # legítima pudiera agotarlo por sí sola: la configuración sería
        # incoherente aunque cada valor sea válido por separado.
        if self.max_messages_per_minute_global < self.max_messages_per_minute:
            raise ConfigError(
                f"BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL="
                f"{self.max_messages_per_minute_global} es menor que "
                f"BACKEND_MAX_MSGS_PER_MINUTE={self.max_messages_per_minute}; "
                "una sola sesión podría agotar el techo global"
            )

        for name in (
            "max_message_bytes",
            "max_accuracy_m",
            "max_age_s",
            "max_distance_to_route_m",
            "max_heading_diff_deg",
            "max_speed_ms",
            "max_displacement_margin_m",
            "dedupe_window_s",
            "merge_radius_m",
            "merge_window_s",
            "vehicle_ttl_s",
            "publish_interval_s",
            "merge_max_heading_diff_deg",
            "health_max_age_s",
        ):
            value = getattr(self, name)

            if not math.isfinite(value) or value <= 0:
                raise ConfigError(f"{name}={value} debe ser finito y positivo")

        if not math.isfinite(self.max_clock_skew_s) or self.max_clock_skew_s < 0:
            raise ConfigError(
                f"max_clock_skew_s={self.max_clock_skew_s} no puede ser negativo"
            )

        if not math.isfinite(self.retention_days) or self.retention_days < 0:
            raise ConfigError(
                f"retention_days={self.retention_days} no puede ser negativo"
            )

        # Un vehículo que caduca antes de que se cierre su ventana de agrupación
        # se recrearía en cada observación, con un identificador nuevo cada vez.
        if self.vehicle_ttl_s < self.merge_window_s:
            raise ConfigError(
                f"BACKEND_VEHICLE_TTL_S={self.vehicle_ttl_s} es menor que "
                f"BACKEND_MERGE_WINDOW_S={self.merge_window_s}; el vehículo "
                "caducaría antes de que termine su propia ventana de agrupación"
            )

        if self.max_age_s <= self.max_clock_skew_s:
            raise ConfigError(
                f"BACKEND_MAX_AGE_S={self.max_age_s} debe ser mayor que "
                f"BACKEND_MAX_CLOCK_SKEW_S={self.max_clock_skew_s}"
            )

    def vehicle_topic(self, vehicle_id: str) -> str:
        return f"{self.vehicles_topic_prefix}/{vehicle_id}/posicion"

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Config":
        env = dict(os.environ if env is None else env)

        use_tls = _flag(env, "MQTT_TLS")

        # Igual que el cliente: activar TLS sin fijar puerto lleva al 8883.
        default_port = 8883 if use_tls else 1883
        port = _integer(
            env,
            "MQTT_PORT",
            default_port,
            minimum=1,
            maximum=MAX_PORT,
        )

        gtfs_dir = env.get("GTFS_DIR", "").strip()

        return cls(
            host=env.get("MQTT_HOST", "127.0.0.1").strip() or "127.0.0.1",
            port=port,
            username=env.get("MQTT_USERNAME", "").strip(),
            password=env.get("MQTT_PASSWORD", ""),
            use_tls=use_tls,
            ca_cert=env.get("MQTT_CA_CERT", "").strip(),
            client_id=env.get("MQTT_CLIENT_ID", "").strip()
            or f"rutautp-backend-{uuid.uuid4()}",
            observations_topic=env.get(
                "BACKEND_OBSERVATIONS_TOPIC", "rutautp/observaciones/+/posicion"
            ).strip(),
            vehicles_topic_prefix=env.get(
                "BACKEND_VEHICLES_TOPIC_PREFIX", "rutautp/vehiculos"
            ).strip(),
            gtfs_dir=Path(gtfs_dir) if gtfs_dir else DEFAULT_GTFS_DIR,
            database_path=env.get(
                "BACKEND_DB_PATH", str(DEFAULT_DATABASE_PATH)
            ).strip(),
            retention_days=_number(
                env, "BACKEND_DB_RETENTION_DAYS", 0.0, allow_zero=True
            ),
            health_file=env.get("BACKEND_HEALTH_FILE", str(DEFAULT_HEALTH_PATH)).strip(),
            health_max_age_s=_number(env, "BACKEND_HEALTH_MAX_AGE_S", 30.0),
            max_message_bytes=_integer(
                env, "BACKEND_MAX_MESSAGE_BYTES", DEFAULT_MAX_MESSAGE_BYTES,
                minimum=256,
            ),
            max_accuracy_m=_number(env, "BACKEND_MAX_ACCURACY_M", 50.0),
            max_age_s=_number(env, "BACKEND_MAX_AGE_S", 45.0),
            max_clock_skew_s=_number(
                env, "BACKEND_MAX_CLOCK_SKEW_S", 10.0, allow_zero=True
            ),
            max_distance_to_route_m=_number(
                env, "BACKEND_MAX_DISTANCE_TO_ROUTE_M", 50.0
            ),
            max_heading_diff_deg=_number(env, "BACKEND_MAX_HEADING_DIFF_DEG", 60.0),
            max_speed_ms=_number(env, "BACKEND_MAX_SPEED_MS", 30.0),
            max_messages_per_minute=_integer(
                env, "BACKEND_MAX_MSGS_PER_MINUTE", 20, minimum=1
            ),
            max_messages_per_minute_global=_integer(
                env,
                "BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL",
                1800,
                minimum=1,
            ),
            max_displacement_margin_m=_number(
                env, "BACKEND_MAX_DISPLACEMENT_MARGIN_M", 250.0, allow_zero=True
            ),
            dedupe_window_s=_number(env, "BACKEND_DEDUPE_WINDOW_S", 120.0),
            merge_radius_m=_number(env, "BACKEND_MERGE_RADIUS_M", 300.0),
            merge_window_s=_number(env, "BACKEND_MERGE_WINDOW_S", 60.0),
            vehicle_ttl_s=_number(env, "BACKEND_VEHICLE_TTL_S", 60.0),
            publish_interval_s=_number(env, "BACKEND_PUBLISH_INTERVAL_S", 5.0),
            merge_max_heading_diff_deg=_number(
                env, "BACKEND_MERGE_MAX_HEADING_DIFF_DEG", 90.0
            ),
            vehicle_namespace=env.get("BACKEND_VEHICLE_NAMESPACE", "").strip(),
            log_level=env.get("BACKEND_LOG_LEVEL", "INFO").strip().upper() or "INFO",
            log_json=_flag(env, "BACKEND_LOG_JSON", default=True),
        )
