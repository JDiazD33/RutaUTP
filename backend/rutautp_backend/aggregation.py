"""Agregación de observaciones en vehículos estimados.

Varios pasajeros pueden ir en el mismo bus. Cada uno publica su propia
observación anónima con un `sessionId` distinto y sin ningún identificador de
unidad. Convertir ese montón de puntos en "un vehículo" es responsabilidad del
servidor, y es justo lo que el cliente no puede hacer.

**Nada de esto demuestra que exista un vehículo.** Produce una *estimación*: el
servidor agrupa observaciones y publica la posición resultante. Que un punto
esté sobre el recorrido del GTFS no significa que haya un bus ahí.

## Cómo se resuelve la identidad

Se aplican tres criterios, en este orden:

1. **Vínculo por sesión.** Si una sesión ya aportó a un vehículo y ese vehículo
   sigue vivo, sus siguientes observaciones van al mismo. Es el criterio más
   fuerte: un pasajero no cambia de bus a mitad de camino, así que sus lecturas
   no deben repartirse entre dos unidades.
2. **Ruta, proximidad y ventana temporal.** Un vehículo de la misma ruta, visto
   hace poco y a menos de `merge_radius_m`.
3. **Coherencia física.** Se descartan los candidatos que implicarían un
   desplazamiento imposible o un rumbo opuesto. Sin esto, dos buses que se
   cruzan en sentidos contrarios —a pocos metros y con rumbos opuestos— se
   fusionarían en uno solo.

Si ningún candidato supera los tres filtros, se crea un vehículo nuevo.
"""

from __future__ import annotations

import logging
import uuid

from .config import Config
from .geo import haversine_m, heading_difference_deg
from .gtfs import GtfsFeed
from .models import EstimatedVehicle, Observation

logger = logging.getLogger(__name__)


class VehicleAggregator:
    """Mantiene el estado de los vehículos estimados."""

    def __init__(self, config: Config, feed: GtfsFeed | None = None) -> None:
        self.config = config

        #: Feed GTFS, solo para conocer la longitud de cada recorrido. Es
        #: opcional: sin él, la comprobación de avance se omite y quedan las
        #: demás.
        self.feed = feed
        self._route_lengths: dict[str, float] = {}

        self._vehicles: dict[str, EstimatedVehicle] = {}

        # Contador por ruta. Nunca se reutiliza un ordinal dentro del mismo
        # proceso: si un vehículo expira y aparece otro en la misma ruta, recibe
        # un identificador nuevo. Reutilizarlo haría que el mapa de la app
        # saltara de posición al reaparecer el mismo id en otro punto.
        self._ordinals: dict[str, int] = {}

        #: Espacio de nombres de este arranque.
        #:
        #: Los ordinales se pierden al reiniciar el proceso, así que un
        #: `{ruta}-01` de este arranque podría coincidir con el `{ruta}-01` del
        #: anterior, que todavía puede estar dibujado en el mapa de los usuarios
        #: hasta que caduque. El espacio de nombres hace que sean
        #: identificadores distintos, sin afirmar continuidad física entre
        #: arranques.
        self.namespace = (
            config.vehicle_namespace.strip() or uuid.uuid4().hex[:4]
        )

        #: `sessionId` -> `vehicle_id`. Permite que un pasajero no cambie de
        #: unidad a mitad de viaje.
        self._vehicle_by_session: dict[str, str] = {}

    # ── Entrada ───────────────────────────────────────────────────────────

    def ingest(
        self, observation: Observation, now: float
    ) -> tuple[EstimatedVehicle, bool]:
        """Incorpora una observación.

        Devuelve el vehículo afectado y si se creó uno nuevo, para poder
        contabilizarlo sin inspeccionar su estado interno.
        """
        vehicle = self._find_match(observation, now)
        created = vehicle is None

        if created:
            vehicle = self._create(observation)
            self._vehicles[vehicle.vehicle_id] = vehicle

            logger.debug(
                "Vehículo nuevo %s en la línea %s",
                vehicle.vehicle_id,
                vehicle.linea,
            )

        self._apply(vehicle, observation)

        self._vehicle_by_session[observation.session_id] = vehicle.vehicle_id

        return vehicle, created

    def _find_match(
        self, observation: Observation, now: float
    ) -> EstimatedVehicle | None:
        """Vehículo al que pertenece esta observación, o `None` si es nuevo."""
        bound = self._bound_vehicle(observation, now)

        if bound is not None:
            return bound

        best: EstimatedVehicle | None = None
        best_distance = float("inf")

        for vehicle in self._vehicles.values():
            if vehicle.route_id != observation.route_id:
                continue

            if now - vehicle.last_seen > self.config.merge_window_s:
                continue

            distance = haversine_m(
                vehicle.lat,
                vehicle.lon,
                observation.lat,
                observation.lon,
            )

            if distance > self.config.merge_radius_m:
                continue

            if not self._is_coherent(vehicle, observation, distance):
                continue

            if distance < best_distance:
                best = vehicle
                best_distance = distance

        return best

    def _bound_vehicle(
        self, observation: Observation, now: float
    ) -> EstimatedVehicle | None:
        """Vehículo al que ya está vinculada esta sesión, si sigue vivo.

        Se exige la misma ventana temporal que en la vía por proximidad: un
        vínculo a un vehículo que ya no se considera reciente no debe resucitarlo.
        """
        vehicle_id = self._vehicle_by_session.get(observation.session_id)

        if vehicle_id is None:
            return None

        vehicle = self._vehicles.get(vehicle_id)

        # El vehículo expiró, la sesión pasó a otra ruta o el vínculo ya no es
        # reciente: se olvida, para que no arrastre una identidad equivocada.
        if (
            vehicle is None
            or vehicle.route_id != observation.route_id
            or now - vehicle.last_seen > self.config.merge_window_s
        ):
            self._vehicle_by_session.pop(observation.session_id, None)

            return None

        return vehicle

    def _is_coherent(
        self,
        vehicle: EstimatedVehicle,
        observation: Observation,
        distance: float,
    ) -> bool:
        """¿Puede esta observación ser de este vehículo?

        Comprueba tres cosas que la distancia por sí sola no distingue:

        - **Desplazamiento posible.** Entre la última lectura del vehículo y
          esta, la distancia no puede superar lo que permitiría su velocidad
          máxima en el tiempo transcurrido.
        - **Avance coherente sobre el recorrido.** Dos lecturas pueden estar a
          pocos metros y pertenecer a unidades distintas si el recorrido pasa
          dos veces por el mismo sitio: la distancia en línea recta no lo
          distingue, pero el avance sobre el trazado sí.
        - **Sentido compatible.** Una misma línea se recorre en los dos
          sentidos; dos unidades que se cruzan están a metros y llevan rumbos
          opuestos. Fusionarlas haría desaparecer una de las dos del mapa.
        """
        elapsed = observation.timestamp - vehicle.timestamp

        # Sin tiempo transcurrido no hay nada que comprobar: los mensajes
        # desordenados los resuelve `_apply`, que no retrocede la posición.
        if elapsed > 0:
            allowed = (
                self.config.max_speed_ms * elapsed
                + self.config.max_accuracy_m
            )

            if distance > allowed:
                return False

            if vehicle.route_length_m > 0:
                avance = (
                    abs(observation.progress - vehicle.progress)
                    * vehicle.route_length_m
                )

                if avance > allowed:
                    return False

        # Solo se compara el rumbo cuando ambos lo conocen: `-1` es un valor
        # legítimo del contrato con el vehículo parado.
        if vehicle.heading >= 0 and observation.heading >= 0:
            difference = heading_difference_deg(
                observation.heading, vehicle.heading
            )

            if difference > self.config.merge_max_heading_diff_deg:
                return False

        return True

    def _route_length(self, route_id: str) -> float:
        """Longitud del recorrido, calculada una sola vez por ruta.

        `RouteGeometry.length_m` suma haversine sobre todos los vértices: es
        O(n) y se llamaría en cada observación si no se guardara. `0` significa
        «no se conoce», y en ese caso la comprobación de avance se omite.
        """
        if route_id in self._route_lengths:
            return self._route_lengths[route_id]

        length = 0.0

        if self.feed is not None:
            route = self.feed.get(route_id)

            if route is not None:
                length = route.length_m

        self._route_lengths[route_id] = length

        return length

    def _create(self, observation: Observation) -> EstimatedVehicle:
        ordinal = self._ordinals.get(observation.route_id, 0) + 1
        self._ordinals[observation.route_id] = ordinal

        return EstimatedVehicle(
            vehicle_id=(
                f"{observation.route_id}-{self.namespace}-{ordinal:02d}"
            ),
            route_id=observation.route_id,
            linea=observation.linea,
            lat=observation.lat,
            lon=observation.lon,
            speed=observation.speed,
            heading=observation.heading,
            timestamp=observation.timestamp,
            last_seen=observation.timestamp,
            progress=observation.progress,
            route_length_m=self._route_length(observation.route_id),
        )

    def _apply(self, vehicle: EstimatedVehicle, observation: Observation) -> None:
        """Actualiza el vehículo con la observación.

        La posición solo se reemplaza si la observación es más reciente: los
        mensajes pueden llegar desordenados y una lectura vieja no debe mover
        el vehículo hacia atrás.
        """
        if observation.timestamp >= vehicle.timestamp:
            vehicle.lat = observation.lat
            vehicle.lon = observation.lon
            vehicle.speed = observation.speed
            vehicle.heading = observation.heading
            vehicle.timestamp = observation.timestamp
            vehicle.progress = observation.progress

        vehicle.last_seen = max(vehicle.last_seen, observation.timestamp)
        vehicle.sessions.add(observation.session_id)
        vehicle.sample_count += 1

    # ── Salida ────────────────────────────────────────────────────────────

    def should_publish(self, vehicle: EstimatedVehicle, now: float) -> bool:
        """Aplica el ritmo de publicación por vehículo.

        Sin esto, diez pasajeros en el mismo bus producirían diez publicaciones
        por ciclo para una sola unidad.
        """
        return (now - vehicle.last_published_at) >= self.config.publish_interval_s

    def mark_published(self, vehicle: EstimatedVehicle, now: float) -> None:
        vehicle.last_published_at = now

    def expire(self, now: float) -> list[str]:
        """Retira los vehículos que dejaron de recibir observaciones.

        Se mide contra el `timestamp` de la última observación, no contra el
        momento en que se procesó: así una ráfaga de mensajes viejos no mantiene
        vivo un vehículo que ya no transmite.
        """
        expired = [
            vehicle_id
            for vehicle_id, vehicle in self._vehicles.items()
            if now - vehicle.last_seen > self.config.vehicle_ttl_s
        ]

        for vehicle_id in expired:
            del self._vehicles[vehicle_id]

        if expired:
            self._forget_sessions_of(expired)

        return expired

    def _forget_sessions_of(self, vehicle_ids: list[str]) -> None:
        """Olvida los vínculos de las sesiones que apuntaban a esos vehículos.

        Si se dejaran, la siguiente observación de esa sesión buscaría un
        vehículo que ya no existe y el vínculo se descartaría igualmente; pero
        olvidarlos aquí evita que el diccionario crezca con sesiones muertas.
        """
        retirados = set(vehicle_ids)

        huerfanos = [
            session
            for session, vehicle_id in self._vehicle_by_session.items()
            if vehicle_id in retirados
        ]

        for session in huerfanos:
            del self._vehicle_by_session[session]

    def snapshot(self) -> list[EstimatedVehicle]:
        """Vehículos actuales, ordenados por identificador para que sea estable."""
        return sorted(self._vehicles.values(), key=lambda vehicle: vehicle.vehicle_id)

    # ── Diagnóstico ───────────────────────────────────────────────────────

    @property
    def vehicle_count(self) -> int:
        return len(self._vehicles)

    @property
    def route_count(self) -> int:
        return len(self._ordinals)

    @property
    def bound_session_count(self) -> int:
        """Sesiones con vínculo a un vehículo vivo."""
        return len(self._vehicle_by_session)

    def sessions_on(self, vehicle_id: str) -> set[str]:
        vehicle = self._vehicles.get(vehicle_id)

        return set(vehicle.sessions) if vehicle else set()
