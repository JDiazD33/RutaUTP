"""Configuración del backend, leída de variables de entorno.

Las variables del broker (`MQTT_*`) usan los mismos nombres que el Scheme de
Xcode del cliente, para que copiar la configuración de un lado al otro no
requiera traducciones. Los ajustes propios del backend llevan el prefijo
`BACKEND_`.

Ninguna credencial vive en el repositorio.
"""

from __future__ import annotations

import os
import uuid
from dataclasses import dataclass, field
from pathlib import Path

# `backend/rutautp_backend/config.py` -> raíz del repositorio
REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_GTFS_DIR = REPO_ROOT / "gtfs"

TRUTHY = {"1", "true", "yes", "on"}


def _flag(env: dict[str, str], name: str, default: bool = False) -> bool:
    raw = env.get(name)

    if raw is None:
        return default

    return raw.strip().lower() in TRUTHY


def _number(
    env: dict[str, str],
    name: str,
    default: float,
    minimum: float | None = None,
) -> float:
    raw = env.get(name)

    if raw is None or not raw.strip():
        return default

    try:
        value = float(raw)
    except ValueError:
        return default

    if minimum is not None and value < minimum:
        return default

    return value


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

    # ── Validación ────────────────────────────────────────────────────────
    max_accuracy_m: float = 50.0
    max_age_s: float = 45.0
    max_clock_skew_s: float = 10.0
    max_distance_to_route_m: float = 50.0
    max_heading_diff_deg: float = 60.0
    min_speed_ms: float = 4.0
    max_speed_ms: float = 30.0
    max_messages_per_minute: int = 20
    dedupe_window_s: float = 120.0

    # ── Agregación ────────────────────────────────────────────────────────
    merge_radius_m: float = 300.0
    merge_window_s: float = 90.0
    vehicle_ttl_s: float = 60.0
    publish_interval_s: float = 5.0

    # ── Observabilidad ────────────────────────────────────────────────────
    log_level: str = "INFO"
    log_json: bool = True

    @property
    def port_default_for_tls(self) -> int:
        return 8883 if self.use_tls else 1883

    def vehicles_topic(self, vehicle_id: str) -> str:
        return f"{self.vehicles_topic_prefix}/{vehicle_id}/posicion"

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Config":
        env = dict(os.environ if env is None else env)

        use_tls = _flag(env, "MQTT_TLS")

        # Igual que el cliente: activar TLS sin fijar puerto lleva al 8883.
        default_port = 8883 if use_tls else 1883
        port = int(_number(env, "MQTT_PORT", default_port, minimum=1))

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
            max_accuracy_m=_number(env, "BACKEND_MAX_ACCURACY_M", 50.0),
            max_age_s=_number(env, "BACKEND_MAX_AGE_S", 45.0),
            max_clock_skew_s=_number(env, "BACKEND_MAX_CLOCK_SKEW_S", 10.0),
            max_distance_to_route_m=_number(
                env, "BACKEND_MAX_DISTANCE_TO_ROUTE_M", 50.0
            ),
            max_heading_diff_deg=_number(env, "BACKEND_MAX_HEADING_DIFF_DEG", 60.0),
            min_speed_ms=_number(env, "BACKEND_MIN_SPEED_MS", 4.0),
            max_speed_ms=_number(env, "BACKEND_MAX_SPEED_MS", 30.0),
            max_messages_per_minute=int(
                _number(env, "BACKEND_MAX_MSGS_PER_MINUTE", 20, minimum=1)
            ),
            dedupe_window_s=_number(env, "BACKEND_DEDUPE_WINDOW_S", 120.0),
            merge_radius_m=_number(env, "BACKEND_MERGE_RADIUS_M", 300.0),
            merge_window_s=_number(env, "BACKEND_MERGE_WINDOW_S", 90.0),
            vehicle_ttl_s=_number(env, "BACKEND_VEHICLE_TTL_S", 60.0),
            publish_interval_s=_number(env, "BACKEND_PUBLISH_INTERVAL_S", 5.0),
            log_level=env.get("BACKEND_LOG_LEVEL", "INFO").strip().upper() or "INFO",
            log_json=_flag(env, "BACKEND_LOG_JSON", default=True),
        )
