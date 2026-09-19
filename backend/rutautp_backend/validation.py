"""Validación de observaciones entrantes.

El cliente ya filtra antes de publicar, pero el servidor no puede confiar en
él: el broker es un canal compartido y cualquiera con credenciales válidas
puede publicar en `rutautp/observaciones/#`. Este módulo es la frontera de
confianza.

Dos decisiones que no son obvias y conviene entender antes de tocar los
umbrales:

1. **No se exige una velocidad mínima ni una actividad vehicular concreta.**
   El cliente sigue publicando mientras está a bordo aunque el vehículo esté
   detenido en un semáforo, y en ese momento la velocidad es ~0 y el rumbo
   puede llegar como `-1` (desconocido). Si el servidor exigiera "velocidad de
   vehículo" como hace el detector del teléfono, haría desaparecer del mapa a
   todos los buses parados. Esa comprobación pertenece a la detección, no aquí.

2. **Rumbo y velocidad desconocidos (`-1`) se omiten, no se rechazan.** Un `-1`
   es un valor legítimo del contrato, no una señal de manipulación. Solo se
   valida el rumbo cuando viene informado, y en ese caso debe ser coherente con
   el sentido del recorrido.
"""

from __future__ import annotations

import json
import logging
import math
from collections import deque
from dataclasses import dataclass
from typing import Any

from .config import Config
from .geo import (
    haversine_m,
    heading_difference_deg,
    is_valid_coordinate,
    match_point_to_polyline,
    sanitize_heading,
    sanitize_speed,
    segment_bearing_deg,
)
from .gtfs import GtfsFeed
from .models import (
    OBSERVATION_FIELDS,
    SCHEMA_VERSION,
    Observation,
    RejectReason,
    is_number,
)

logger = logging.getLogger(__name__)

# Longitud máxima razonable de un identificador de sesión. El cliente genera un
# UUID (36 caracteres); se deja margen para no atar el servidor al formato.
MAX_SESSION_ID_LENGTH = 128

#: Clave del contador global. No puede coincidir con un `sessionId` real porque
#: `sessionId` se valida como cadena no vacía sin restringir su contenido: una
#: sesión llamada igual compartiría contador con el servicio entero. El prefijo
#: con carácter nulo lo hace imposible en la práctica, y el límite por sesión
#: seguiría aplicándose por separado en cualquier caso.
GLOBAL_RATE_KEY = "\x00global"


def _reject_json_constant(name: str):
    """Rechaza `NaN`, `Infinity` y `-Infinity` durante la decodificación.

    El estándar JSON no admite esas constantes, pero el decodificador de Python
    las acepta por defecto. Dejarlas entrar convierte un mensaje en una excepción
    más adelante, cuando ya se está operando con el valor.
    """
    raise ValueError(f"constante no permitida en JSON: {name}")


@dataclass(frozen=True)
class ValidationResult:
    """Resultado de validar un mensaje."""

    observation: Observation | None = None
    reason: RejectReason | None = None
    detail: str = ""

    @property
    def ok(self) -> bool:
        return self.observation is not None

    @classmethod
    def accept(cls, observation: Observation) -> "ValidationResult":
        return cls(observation=observation)

    @classmethod
    def reject(cls, reason: RejectReason, detail: str = "") -> "ValidationResult":
        return cls(reason=reason, detail=detail)


class RateLimiter:
    """Límite de mensajes por sesión en una ventana deslizante.

    Sin esto, un cliente comprometido puede inundar el broker y forzar al
    servidor a validar geometría millones de veces por minuto.
    """

    def __init__(self, max_per_minute: int, window_s: float = 60.0) -> None:
        self.max_per_minute = max(1, max_per_minute)
        self.window_s = window_s
        self._events: dict[str, deque[float]] = {}

    def allow(self, key: str, now: float) -> bool:
        """Registra el intento y dice si está dentro del límite."""
        events = self._events.setdefault(key, deque())

        cutoff = now - self.window_s

        while events and events[0] < cutoff:
            events.popleft()

        if len(events) >= self.max_per_minute:
            return False

        events.append(now)

        return True

    def prune(self, now: float) -> None:
        """Olvida las sesiones que dejaron de publicar."""
        cutoff = now - self.window_s

        empty = [
            key
            for key, events in self._events.items()
            if not events or events[-1] < cutoff
        ]

        for key in empty:
            del self._events[key]

    @property
    def tracked_sessions(self) -> int:
        return len(self._events)


class Deduplicator:
    """Descarta repeticiones exactas de una misma observación.

    La baliza publica con QoS 1, que garantiza entrega *al menos* una vez: el
    broker puede reenviar el mismo mensaje. La clave natural es
    `(sessionId, timestamp)`.
    """

    def __init__(self, window_s: float) -> None:
        self.window_s = window_s
        self._seen: dict[tuple[str, float], float] = {}

    def is_duplicate(self, key: tuple[str, float], now: float) -> bool:
        previous = self._seen.get(key)

        self._seen[key] = now

        if previous is None:
            return False

        return (now - previous) <= self.window_s

    def prune(self, now: float) -> None:
        cutoff = now - self.window_s

        stale = [key for key, seen_at in self._seen.items() if seen_at < cutoff]

        for key in stale:
            del self._seen[key]

    @property
    def tracked_keys(self) -> int:
        return len(self._seen)


class ObservationValidator:
    """Convierte un mensaje crudo del broker en una `Observation` o en un motivo."""

    def __init__(self, feed: GtfsFeed, config: Config) -> None:
        self.feed = feed
        self.config = config
        self.rate_limiter = RateLimiter(config.max_messages_per_minute)

        # Techo del servicio entero. `RateLimiter` se reutiliza con una única
        # clave: el límite por sesión no basta porque el `sessionId` lo elige
        # el cliente y se puede rotar.
        self.global_limiter = RateLimiter(config.max_messages_per_minute_global)

        self.deduplicator = Deduplicator(config.dedupe_window_s)

        #: Última observación aceptada de cada sesión, para comprobar que la
        #: siguiente es compatible con la trayectoria.
        self._last_seen: dict[str, tuple[float, float, float]] = {}

    def validate(self, raw: bytes | str, now: float) -> ValidationResult:
        """Valida un mensaje. `now` se inyecta para poder probar sin reloj real."""
        payload = self._decode(raw)

        if isinstance(payload, ValidationResult):
            return payload

        structural = self._check_structure(payload)

        if isinstance(structural, ValidationResult):
            return structural

        # A partir de aquí el mensaje tiene forma correcta. El límite de tasa se
        # aplica antes de cualquier geometría: es la defensa más barata.
        session_id = str(payload["sessionId"]).strip()

        if not self.rate_limiter.allow(session_id, now):
            return ValidationResult.reject(
                RejectReason.RATE_LIMITED,
                f"sesión {session_id[:8]} supera "
                f"{self.config.max_messages_per_minute} msg/min",
            )

        # El techo global se comprueba después del de sesión: así el motivo
        # registrado es el más específico cuando ambos aplican.
        if not self.global_limiter.allow(GLOBAL_RATE_KEY, now):
            return ValidationResult.reject(
                RejectReason.GLOBAL_RATE_LIMITED,
                f"el servicio supera "
                f"{self.config.max_messages_per_minute_global} msg/min",
            )

        semantic = self._check_semantics(payload, now)

        if isinstance(semantic, ValidationResult):
            return semantic

        timestamp = float(payload["timestamp"])

        if self.deduplicator.is_duplicate((session_id, timestamp), now):
            return ValidationResult.reject(
                RejectReason.DUPLICATE, f"({session_id[:8]}, {timestamp})"
            )

        continuity = self._check_continuity(payload, session_id)

        if isinstance(continuity, ValidationResult):
            return continuity

        self._remember(session_id, payload)

        return ValidationResult.accept(Observation.from_payload(payload))

    # ── Etapas ────────────────────────────────────────────────────────────

    def _decode(self, raw: bytes | str) -> dict[str, Any] | ValidationResult:
        """Convierte el mensaje en un objeto, o explica por qué no se puede.

        Todo lo que puede lanzar una excepción se comprueba **antes** de usarlo:
        un solo mensaje con `schemaVersion: NaN` bastaba para tumbar el servicio.
        """
        # Un mensaje legítimo ronda los 300 bytes. El límite se aplica antes de
        # decodificar para no gastar memoria en algo que se va a descartar.
        if len(raw) > self.config.max_message_bytes:
            return ValidationResult.reject(
                RejectReason.MESSAGE_TOO_LARGE,
                f"{len(raw)} bytes > {self.config.max_message_bytes}",
            )

        try:
            payload = json.loads(raw, parse_constant=_reject_json_constant)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            return ValidationResult.reject(
                RejectReason.MALFORMED_JSON, str(error)[:120]
            )
        except RecursionError:
            return ValidationResult.reject(
                RejectReason.TOO_DEEPLY_NESTED, "anidamiento excesivo"
            )
        except ValueError as error:
            # `parse_constant` señala así las constantes no permitidas.
            return ValidationResult.reject(
                RejectReason.NON_FINITE_NUMBER, str(error)[:120]
            )

        if not isinstance(payload, dict):
            return ValidationResult.reject(
                RejectReason.NOT_AN_OBJECT, type(payload).__name__
            )

        return payload

    def _check_structure(
        self, payload: dict[str, Any]
    ) -> None | ValidationResult:
        for field_name, expected_type in OBSERVATION_FIELDS.items():
            if field_name not in payload:
                return ValidationResult.reject(
                    RejectReason.MISSING_FIELD, field_name
                )

            value = payload[field_name]

            if not is_number(value) and expected_type is not str:
                return ValidationResult.reject(
                    RejectReason.BAD_FIELD_TYPE, f"{field_name}={value!r}"
                )

            if expected_type is float:
                # `1e309` se decodifica como infinito: es un número válido para
                # el decodificador pero no para el contrato.
                if not math.isfinite(value):
                    return ValidationResult.reject(
                        RejectReason.NON_FINITE_NUMBER, f"{field_name}={value!r}"
                    )
            elif expected_type is int:
                if not math.isfinite(value):
                    return ValidationResult.reject(
                        RejectReason.NON_FINITE_NUMBER, f"{field_name}={value!r}"
                    )

                # La comprobación de finitud va antes: `int(NaN)` y
                # `int(inf)` lanzan excepción en vez de devolver un valor.
                if float(value) != int(value):
                    return ValidationResult.reject(
                        RejectReason.BAD_FIELD_TYPE, f"{field_name}={value!r}"
                    )
            elif not isinstance(value, expected_type):
                return ValidationResult.reject(
                    RejectReason.BAD_FIELD_TYPE, f"{field_name}={value!r}"
                )

        if int(payload["schemaVersion"]) != SCHEMA_VERSION:
            return ValidationResult.reject(
                RejectReason.UNSUPPORTED_SCHEMA,
                f"schemaVersion={payload['schemaVersion']}",
            )

        session_id = str(payload["sessionId"]).strip()

        if not session_id or len(session_id) > MAX_SESSION_ID_LENGTH:
            return ValidationResult.reject(
                RejectReason.EMPTY_SESSION, f"len={len(session_id)}"
            )

        return None

    def _check_semantics(
        self, payload: dict[str, Any], now: float
    ) -> None | ValidationResult:
        latitude = float(payload["lat"])
        longitude = float(payload["lon"])

        if not is_valid_coordinate(latitude, longitude):
            return ValidationResult.reject(
                RejectReason.INVALID_COORDINATE, f"{latitude},{longitude}"
            )

        accuracy = float(payload["accuracy"])

        if not math.isfinite(accuracy) or accuracy < 0:
            return ValidationResult.reject(
                RejectReason.BAD_ACCURACY, f"{accuracy}"
            )

        if accuracy > self.config.max_accuracy_m:
            return ValidationResult.reject(
                RejectReason.BAD_ACCURACY,
                f"{accuracy:.1f} m > {self.config.max_accuracy_m:.0f} m",
            )

        timestamp = float(payload["timestamp"])

        if not math.isfinite(timestamp):
            return ValidationResult.reject(
                RejectReason.STALE_TIMESTAMP, "timestamp no finito"
            )

        if timestamp > now + self.config.max_clock_skew_s:
            return ValidationResult.reject(
                RejectReason.FUTURE_TIMESTAMP,
                f"{timestamp - now:.1f} s en el futuro",
            )

        if now - timestamp > self.config.max_age_s:
            return ValidationResult.reject(
                RejectReason.STALE_TIMESTAMP,
                f"{now - timestamp:.1f} s de antigüedad",
            )

        return self._check_against_route(payload, latitude, longitude)

    def _check_against_route(
        self, payload: dict[str, Any], latitude: float, longitude: float
    ) -> None | ValidationResult:
        route_id = str(payload["routeId"]).strip()

        route = self.feed.get(route_id)

        if route is None:
            return ValidationResult.reject(RejectReason.UNKNOWN_ROUTE, route_id)

        if route.point_count < 2:
            return ValidationResult.reject(
                RejectReason.UNKNOWN_ROUTE, f"{route_id} sin geometría"
            )

        # La línea que declara el cliente debe ser la de la ruta que dice usar.
        # Si no, el mapa de los demás mostraría un nombre y un color que no
        # corresponden al recorrido por el que va el vehículo.
        claimed_line = str(payload["linea"]).strip()

        if claimed_line != route.linea:
            return ValidationResult.reject(
                RejectReason.LINE_MISMATCH,
                f"dice {claimed_line!r}, la ruta {route_id} es {route.linea!r}",
            )

        match = match_point_to_polyline(
            latitude,
            longitude,
            list(route.shape),
            threshold_m=self.config.max_distance_to_route_m,
        )

        if match is None:
            return ValidationResult.reject(
                RejectReason.UNKNOWN_ROUTE, f"{route_id} sin geometría usable"
            )

        if match.distance_m > self.config.max_distance_to_route_m:
            return ValidationResult.reject(
                RejectReason.TOO_FAR_FROM_ROUTE,
                f"{match.distance_m:.1f} m de {route.linea}",
            )

        heading = float(payload["heading"])

        # Solo se comprueba el rumbo cuando viene informado. Un `-1` es el valor
        # de "desconocido" del contrato y ocurre de forma legítima con el
        # vehículo parado.
        if heading >= 0:
            route_bearing = segment_bearing_deg(
                list(route.shape), match.segment_index
            )
            difference = heading_difference_deg(heading, route_bearing)

            if difference > self.config.max_heading_diff_deg:
                return ValidationResult.reject(
                    RejectReason.HEADING_NOT_ALIGNED,
                    f"{difference:.0f}° respecto a {route.linea}",
                )

            payload["_headingDiffDeg"] = difference

        speed = float(payload["speed"])

        # Solo se rechaza lo imposible. Una velocidad baja o desconocida es
        # normal con el vehículo detenido.
        if speed >= 0 and speed > self.config.max_speed_ms:
            return ValidationResult.reject(
                RejectReason.SPEED_OUT_OF_RANGE, f"{speed:.1f} m/s"
            )

        payload["_distanceToRouteM"] = match.distance_m
        payload["_progress"] = match.progress

        # Normaliza al contrato de salida, que es más estricto que el de entrada.
        payload["speed"] = sanitize_speed(speed)
        payload["heading"] = sanitize_heading(heading)

        return None

    # ── Continuidad de la trayectoria ─────────────────────────────────────

    def _check_continuity(
        self, payload: dict[str, Any], session_id: str
    ) -> None | ValidationResult:
        """Comprueba que la observación sea compatible con la anterior.

        La geometría demuestra que un punto está sobre el recorrido, **no** que
        exista un vehículo ahí: basta con inventarse una posición sobre la
        línea. Esta comprobación añade la dimensión que faltaba —el tiempo— y
        rechaza el salto que no podría haber dado ningún vehículo real.

        Es una defensa parcial y conviene no exagerarla: una sesión nueva no
        tiene historial, así que la primera observación siempre pasa. Lo que
        impide es sostener una trayectoria incoherente dentro de una misma
        sesión, que es lo que hace falta para simular un recorrido creíble.
        """
        previous = self._last_seen.get(session_id)

        if previous is None:
            return None

        previous_timestamp, previous_latitude, previous_longitude = previous

        timestamp = float(payload["timestamp"])

        # Un mensaje desordenado no dice nada sobre la trayectoria: el
        # agregador ya ignora las lecturas más viejas.
        if timestamp <= previous_timestamp:
            return None

        elapsed = timestamp - previous_timestamp

        travelled = haversine_m(
            previous_latitude,
            previous_longitude,
            float(payload["lat"]),
            float(payload["lon"]),
        )

        # Lo que recorrería un vehículo al techo de velocidad, más margen para
        # el ruido del GPS de la medida anterior.
        allowed = (
            self.config.max_speed_ms * elapsed
            + self.config.max_accuracy_m
            + self.config.max_displacement_margin_m
        )

        if travelled > allowed:
            return ValidationResult.reject(
                RejectReason.IMPLAUSIBLE_JUMP,
                f"{travelled:.0f} m en {elapsed:.1f} s "
                f"(máximo {allowed:.0f} m)",
            )

        return None

    def _remember(self, session_id: str, payload: dict[str, Any]) -> None:
        """Guarda la observación aceptada como referencia de continuidad."""
        self._last_seen[session_id] = (
            float(payload["timestamp"]),
            float(payload["lat"]),
            float(payload["lon"]),
        )

    # ── Mantenimiento ─────────────────────────────────────────────────────

    def prune(self, now: float) -> None:
        """Libera el estado de sesiones y mensajes ya caducados."""
        self.rate_limiter.prune(now)
        self.global_limiter.prune(now)
        self.deduplicator.prune(now)

        # Una sesión que lleva sin publicar más de la ventana de deduplicación
        # ya no puede aportar continuidad útil: su próxima observación se
        # tratará como la primera, que es el comportamiento correcto tras un
        # viaje nuevo.
        cutoff = now - self.config.dedupe_window_s

        stale = [
            key for key, seen in self._last_seen.items() if seen[0] < cutoff
        ]

        for key in stale:
            del self._last_seen[key]

    @property
    def tracked_continuity_sessions(self) -> int:
        """Sesiones con historial de trayectoria. Para diagnóstico."""
        return len(self._last_seen)
