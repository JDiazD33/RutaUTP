"""Modelos del puente: lo que entra y lo que sale.

Ambos contratos están copiados de los tipos Swift que ya existen, y esa
correspondencia es la parte más importante de este archivo:

- Entrada: `PassengerObservationPayload` (MQTTObservationPublisher.swift)
- Salida:  `VehiclePositionMessage` (MQTTTrackingProvider.swift)

Si el servidor publicara un campo de más, un campo de menos o con otro nombre,
la app descartaría el mensaje en el `JSONDecoder` sin decir por qué. Por eso
hay pruebas que fijan las claves exactas en ambos sentidos.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

SCHEMA_VERSION = 1


class RejectReason(str, Enum):
    """Motivo por el que una observación no se convirtió en posición vehicular.

    Se registran por separado a propósito: para el análisis posterior importa
    mucho más *por qué* se descartó que cuántas se descartaron.
    """

    MALFORMED_JSON = "malformed_json"
    NOT_AN_OBJECT = "not_an_object"
    MESSAGE_TOO_LARGE = "message_too_large"
    TOO_DEEPLY_NESTED = "too_deeply_nested"
    UNSUPPORTED_SCHEMA = "unsupported_schema"
    MISSING_FIELD = "missing_field"
    BAD_FIELD_TYPE = "bad_field_type"
    NON_FINITE_NUMBER = "non_finite_number"
    EMPTY_SESSION = "empty_session"
    UNKNOWN_ROUTE = "unknown_route"
    LINE_MISMATCH = "line_mismatch"
    INVALID_COORDINATE = "invalid_coordinate"
    BAD_ACCURACY = "bad_accuracy"
    STALE_TIMESTAMP = "stale_timestamp"
    FUTURE_TIMESTAMP = "future_timestamp"
    TOO_FAR_FROM_ROUTE = "too_far_from_route"
    HEADING_NOT_ALIGNED = "heading_not_aligned"
    SPEED_OUT_OF_RANGE = "speed_out_of_range"
    ACTIVITY_NOT_VEHICULAR = "activity_not_vehicular"
    RATE_LIMITED = "rate_limited"
    DUPLICATE = "duplicate"
    SESSION_MISMATCH = "session_mismatch"

    #: El servicio, en conjunto, supera su techo de mensajes por minuto. Es
    #: distinto de `RATE_LIMITED`: aquel aísla un principal MQTT autenticado;
    #: este acota el trabajo agregado de todas las identidades.
    GLOBAL_RATE_LIMITED = "global_rate_limited"

    #: La observación es incompatible con la trayectoria previa de su propia
    #: sesión: implicaría un desplazamiento imposible entre dos instantes.
    IMPLAUSIBLE_JUMP = "implausible_jump"

    #: Fallo inesperado al procesar el mensaje. No es culpa del cliente: sirve
    #: para que un error interno descarte ese mensaje sin detener el servicio,
    #: pero quede registrado en lugar de silenciarse.
    INTERNAL_ERROR = "internal_error"


@dataclass(frozen=True)
class Observation:
    """Observación ya validada, lista para agregar."""

    session_id: str
    route_id: str
    linea: str
    lat: float
    lon: float
    speed: float
    heading: float
    accuracy: float
    motion_activity: str
    timestamp: float
    distance_to_route_m: float
    heading_diff_deg: float
    progress: float

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "Observation":
        """Construye desde el JSON ya validado.

        Solo se usa después de que el validador comprobó tipos y rangos.
        """
        return cls(
            session_id=str(payload["sessionId"]),
            route_id=str(payload["routeId"]),
            linea=str(payload["linea"]),
            lat=float(payload["lat"]),
            lon=float(payload["lon"]),
            speed=float(payload["speed"]),
            heading=float(payload["heading"]),
            accuracy=float(payload["accuracy"]),
            motion_activity=str(payload["motionActivity"]),
            timestamp=float(payload["timestamp"]),
            distance_to_route_m=float(payload.get("_distanceToRouteM", 0.0)),
            heading_diff_deg=float(payload.get("_headingDiffDeg", 0.0)),
            progress=float(payload.get("_progress", 0.0)),
        )


@dataclass
class EstimatedVehicle:
    """Unidad estimada a partir de una o varias observaciones.

    El `vehicle_id` lo deriva el servidor. Nunca se toma del mensaje del
    cliente: si se aceptara un identificador enviado por el teléfono, cualquiera
    con credenciales válidas podría suplantar a un vehículo ante los demás
    usuarios.
    """

    vehicle_id: str
    route_id: str
    linea: str
    lat: float
    lon: float
    speed: float
    heading: float
    timestamp: float
    last_seen: float

    #: Fracción del recorrido (0..1) en la que está el vehículo.
    #:
    #: No se publica: sirve para agrupar. Dos observaciones de la misma ruta
    #: pueden estar a pocos metros y pertenecer a unidades distintas (dos
    #: sentidos, dos buses en paralelo); el avance sobre el recorrido y el
    #: tiempo transcurrido permiten descartar esas fusiones.
    progress: float = 0.0

    #: Longitud total del recorrido, en metros. `0` si no se conoce.
    #:
    #: Es lo que convierte una diferencia de `progress` en metros, y así en una
    #: velocidad comparable con el techo permitido. Se guarda en el vehículo
    #: para no recalcularla: `RouteGeometry.length_m` recorre todos los vértices
    #: con haversine.
    route_length_m: float = 0.0

    sessions: set[str] = field(default_factory=set)
    sample_count: int = 0
    last_published_at: float = 0.0

    def to_vehicle_position(self) -> dict[str, Any]:
        """Carga útil que consume la app.

        Las claves y el orden de los tipos son exactamente los de
        `VehiclePositionMessage`. `timestamp` es el de la observación, no el de
        publicación: si se refrescara al publicar, un vehículo que dejó de
        transmitir seguiría pareciendo vivo y nunca se podaría del mapa.

        `routeId` viaja explícito (D04). Antes el mapa deducía los metadatos de
        la ruta a partir de `linea`, que es el nombre público: dos ramales de la
        misma línea comparten `linea`, así que quedaban indistinguibles, y una
        línea fuera del pequeño catálogo precargado por la app se quedaba sin
        empresa ni recorrido. El identificador de ruta sí es único.
        """
        return {
            "vehicleId": self.vehicle_id,
            "routeId": self.route_id,
            "linea": self.linea,
            "lat": self.lat,
            "lon": self.lon,
            "speed": self.speed,
            "heading": self.heading,
            "timestamp": self.timestamp,
        }

    def encode(self) -> str:
        return json.dumps(self.to_vehicle_position(), ensure_ascii=False)


# Claves exigidas en la observación entrante y su tipo esperado.
# `bool` es subclase de `int` en Python, así que se excluye explícitamente al
# comprobar números: un `true` no debe pasar como coordenada.
OBSERVATION_FIELDS: dict[str, type] = {
    "schemaVersion": int,
    "sessionId": str,
    "routeId": str,
    "linea": str,
    "lat": float,
    "lon": float,
    "speed": float,
    "heading": float,
    "accuracy": float,
    "motionActivity": str,
    "timestamp": float,
}


def is_number(value: Any) -> bool:
    """Número real, excluyendo booleanos."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)
