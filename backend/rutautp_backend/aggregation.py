"""Agregación de observaciones en vehículos estimados.

Varios pasajeros pueden ir en el mismo bus. Cada uno publica su propia
observación anónima con un `sessionId` distinto y sin ningún identificador de
unidad. Convertir ese montón de puntos en "un vehículo" es responsabilidad del
servidor, y es justo lo que el cliente no puede hacer.

La identidad se resuelve por proximidad y tiempo: si llega una observación de la
misma ruta cerca de un vehículo ya conocido y reciente, se considera el mismo
vehículo. Si no, se crea uno nuevo.
"""

from __future__ import annotations

import logging

from .config import Config
from .geo import haversine_m
from .models import EstimatedVehicle, Observation

logger = logging.getLogger(__name__)


class VehicleAggregator:
    """Mantiene el estado de los vehículos estimados."""

    def __init__(self, config: Config) -> None:
        self.config = config
        self._vehicles: dict[str, EstimatedVehicle] = {}

        # Contador por ruta. Nunca se reutiliza un ordinal: si un vehículo
        # expira y aparece otro en la misma ruta, recibe un identificador
        # nuevo. Reutilizarlo haría que el mapa de la app saltara de posición
        # al reaparecer el mismo id en otro punto.
        self._ordinals: dict[str, int] = {}

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

        return vehicle, created

    def _find_match(
        self, observation: Observation, now: float
    ) -> EstimatedVehicle | None:
        """Vehículo de la misma ruta, reciente y cerca de esta observación."""
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

            if distance <= self.config.merge_radius_m and distance < best_distance:
                best = vehicle
                best_distance = distance

        return best

    def _create(self, observation: Observation) -> EstimatedVehicle:
        ordinal = self._ordinals.get(observation.route_id, 0) + 1
        self._ordinals[observation.route_id] = ordinal

        return EstimatedVehicle(
            vehicle_id=f"{observation.route_id}-{ordinal:02d}",
            route_id=observation.route_id,
            linea=observation.linea,
            lat=observation.lat,
            lon=observation.lon,
            speed=observation.speed,
            heading=observation.heading,
            timestamp=observation.timestamp,
            last_seen=observation.timestamp,
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

        return expired

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

    def sessions_on(self, vehicle_id: str) -> set[str]:
        vehicle = self._vehicles.get(vehicle_id)

        return set(vehicle.sessions) if vehicle else set()
