"""Motor puro: trayectorias analíticas y pasajeros, sin MQTT ni base implícita."""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import asdict, dataclass
import hashlib
import heapq
import json
import math
from pathlib import Path
import random
from typing import TextIO
import uuid

from rutautp_backend.geo import haversine_m
from rutautp_backend.simulation_models import SimulationActorRecord, canonical_uuid
from rutautp_backend.simulation_profile import SimulationProfile
from .clock import Clock, ClockDiscontinuity, ClockGuard, ClockSample, RealtimeClock
from .geometry import TripGeometry, load_trip_geometries, number


def _seed(seed: int, label: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}:{label}".encode()).digest()[:16], "big")


@dataclass(frozen=True)
class MotionSettings:
    cruise_min: float
    cruise_max: float
    acceleration: float
    deceleration: float
    dwell_min: float
    dwell_max: float
    terminal_min: float
    terminal_max: float
    accuracy_min: float
    accuracy_max: float
    noise_max: float
    noise_period: float

    def __post_init__(self):
        for field in ("cruise_min", "cruise_max", "acceleration", "deceleration", "noise_period"):
            number(getattr(self, field), field, minimum=1e-6)
        for field in ("dwell_min", "dwell_max", "terminal_min", "terminal_max", "accuracy_min", "accuracy_max", "noise_max"):
            number(getattr(self, field), field)
        if (self.cruise_min > self.cruise_max or self.cruise_max > 30
                or self.dwell_min > self.dwell_max or self.terminal_min > self.terminal_max
                or self.accuracy_min > self.accuracy_max or self.accuracy_max > 50
                or self.noise_max > self.accuracy_min):
            raise ValueError("rangos de movimiento/GPS incoherentes")

    @classmethod
    def from_profile(cls, profile: SimulationProfile) -> "MotionSettings":
        body = json.loads(profile.raw)
        motion, gps = body["movement"], body["gps"]
        if motion["routeEndPolicy"] != "finish_without_wrapping" or motion["unknownHeadingWhenStopped"] != -1:
            raise ValueError("política de final/rumbo incompatible")
        return cls(motion["cruiseSpeedMetersPerSecond"]["min"], motion["cruiseSpeedMetersPerSecond"]["max"],
                   motion["accelerationMetersPerSecondSquared"], motion["decelerationMetersPerSecondSquared"],
                   motion["stopDwellSeconds"]["min"], motion["stopDwellSeconds"]["max"],
                   motion["terminalPauseSeconds"]["min"], motion["terminalPauseSeconds"]["max"],
                   gps["declaredAccuracyMeters"]["min"], gps["declaredAccuracyMeters"]["max"],
                   gps["maxNoiseOffsetMeters"], gps["noiseSmoothingSeconds"])


@dataclass(frozen=True)
class MotionPhase:
    start: float
    duration: float
    distance: float
    speed: float
    acceleration: float
    kind: str


@dataclass(frozen=True)
class JourneyPoint:
    lat: float
    lon: float
    distance_m: float
    speed: float
    heading: float
    phase: str


class VehicleJourney:
    """Una trayectoria compartida. El resultado depende del tiempo, no del tick."""

    def __init__(self, geometry: TripGeometry, settings: MotionSettings, seed: int,
                 *, initial_progress: float = 0):
        number(initial_progress, "initialProgress", maximum=1)
        self.geometry, self.settings = geometry, settings
        rng = random.Random(seed)
        self.cruise_speed = rng.uniform(settings.cruise_min, settings.cruise_max)
        self.phases: list[MotionPhase] = []
        self.dwell_windows: list[tuple[float, float, str]] = []
        current_time, distance = 0.0, initial_progress * geometry.path.length_m
        stops = [s for s in geometry.stops if distance + 1e-6 < s.distance_m < geometry.path.length_m - 1e-6]
        targets = [(s.distance_m, s.stop_id) for s in stops] + [(geometry.path.length_m, None)]
        for target, stop_id in targets:
            length = target - distance
            a, b = settings.acceleration, settings.deceleration
            peak = min(self.cruise_speed, math.sqrt(max(0, 2 * length / (1 / a + 1 / b))))
            acceleration_time, braking_time = peak / a, peak / b
            cruise_distance = max(0, length - peak * peak / (2 * a) - peak * peak / (2 * b))
            for duration, speed, acceleration, kind in (
                (acceleration_time, 0, a, "accelerating"),
                (cruise_distance / peak if peak else 0, peak, 0, "cruising"),
                (braking_time, peak, -b, "braking"),
            ):
                if duration > 1e-9:
                    self.phases.append(MotionPhase(current_time, duration, distance, speed, acceleration, kind))
                    distance += speed * duration + 0.5 * acceleration * duration * duration
                    current_time += duration
            distance = target
            if stop_id is not None:
                duration = rng.uniform(settings.dwell_min, settings.dwell_max)
                if duration > 0:
                    self.phases.append(MotionPhase(current_time, duration, distance, 0, 0, "dwell"))
                    self.dwell_windows.append((current_time, duration, stop_id))
                    current_time += duration
        self.arrival_time = current_time
        self.terminal_duration = rng.uniform(settings.terminal_min, settings.terminal_max)
        self.finished_at = current_time + self.terminal_duration
        self._ends = tuple(p.start + p.duration for p in self.phases)

    def at(self, elapsed: float) -> JourneyPoint:
        number(elapsed, "elapsed")
        path = self.geometry.path
        if elapsed >= self.arrival_time:
            point = path.at(path.length_m)
            return JourneyPoint(point.lat, point.lon, point.distance_m, 0, -1,
                                "terminal" if elapsed < self.finished_at else "finished")
        phase = self.phases[bisect_right(self._ends, elapsed)]
        delta = min(max(elapsed - phase.start, 0), phase.duration)
        distance = phase.distance + phase.speed * delta + 0.5 * phase.acceleration * delta * delta
        point = path.at(distance)
        speed = max(0.0, phase.speed + phase.acceleration * delta)
        return JourneyPoint(point.lat, point.lon, point.distance_m, speed,
                            point.heading if speed > 1e-8 else -1, phase.kind)


@dataclass(frozen=True)
class ActorEvent:
    kind: str
    principal: str
    session_id: str
    scenario_vehicle_id: str
    journey_id: str
    route_id: str
    at: float
    elapsed: float
    reason: str

    def boarding_record(self, run_id: str) -> SimulationActorRecord:
        if self.kind != "board":
            raise ValueError("solo un abordaje crea la referencia del actor")
        return SimulationActorRecord(run_id, self.principal, self.session_id,
                                     self.scenario_vehicle_id, self.route_id, self.at)


@dataclass(frozen=True)
class ActorObservation:
    principal: str
    session_id: str
    scenario_vehicle_id: str
    journey_id: str
    route_id: str
    linea: str
    lat: float
    lon: float
    speed: float
    heading: float
    accuracy: float
    timestamp: float
    noise_north_m: float
    noise_east_m: float
    heading_unknown_reason: str | None = None

    def payload(self) -> dict:
        return {"schemaVersion": 1, "sessionId": self.session_id, "routeId": self.route_id,
                "linea": self.linea, "lat": self.lat, "lon": self.lon, "speed": self.speed,
                "heading": self.heading, "accuracy": self.accuracy,
                "motionActivity": "automotive" if self.speed > 1e-8 else "stationary",
                "timestamp": self.timestamp}


@dataclass
class PassengerActor:
    principal: str
    scenario_vehicle_id: str
    noise_seed: int
    accuracy: float
    session_id: str | None = None
    boarded_at: float | None = None
    boarding_count: int = 0

    def noise(self, elapsed: float, settings: MotionSettings) -> tuple[float, float]:
        slot = int(elapsed // settings.noise_period)
        fraction = (elapsed / settings.noise_period) - slot
        blend = fraction * fraction * (3 - 2 * fraction)
        targets = []
        for index in (slot, slot + 1):
            rng = random.Random(_seed(self.noise_seed, str(index)))
            radius, angle = settings.noise_max * math.sqrt(rng.random()), rng.uniform(0, 2 * math.pi)
            targets.append((radius * math.cos(angle), radius * math.sin(angle)))
        return tuple(a + blend * (b - a) for a, b in zip(*targets))


@dataclass(frozen=True)
class VehicleReference:
    scenario_vehicle_id: str
    journey_id: str
    route_id: str
    trip_id: str
    shape_id: str
    position: JourneyPoint
    contributors: int


@dataclass(frozen=True)
class ScenarioFrame:
    at: float
    elapsed: float
    state: str
    reason: str
    vehicles: tuple[VehicleReference, ...]
    observations: tuple[ActorObservation, ...]
    events: tuple[ActorEvent, ...]


class ScenarioEngine:
    def __init__(self, profile: SimulationProfile, geometries: dict[str, TripGeometry], run_id: str,
                 gtfs_dir: Path, *, clock: Clock | None = None, session_namespace: str | None = None):
        canonical_uuid(run_id)
        self.profile, self.geometries, self.run_id, self.gtfs_dir = profile, geometries, run_id, gtfs_dir
        self.clock = clock or RealtimeClock()
        self.session_namespace = session_namespace or str(uuid.uuid4())
        canonical_uuid(self.session_namespace)
        self.settings = MotionSettings.from_profile(profile)
        self.state, self.reason, self.elapsed = "ready", "", 0.0
        self._guard = ClockGuard()
        self._journeys, self._origins, self._ordinals, self._journey_ids = {}, {}, {}, {}
        self._passengers, self._groups = {}, {}
        self._scheduled = []
        self._event_order = 0
        for spec in json.loads(profile.raw)["vehicles"]:
            vehicle_id = spec["scenarioVehicleId"]
            geometry = geometries[spec["routeId"]]
            if (vehicle_id in self._groups or geometry.trip_id != spec["tripId"]
                    or geometry.shape_id != spec["shapeId"] or geometry.linea != spec["linea"]):
                raise ValueError("identidad del viaje no coincide con el perfil")
            self._groups[vehicle_id] = tuple(spec["principals"])
            if len(self._groups[vehicle_id]) < 2:
                raise ValueError("cada micro base necesita al menos dos principales")
            for principal in spec["principals"]:
                rng = random.Random(_seed(profile.seed, principal))
                if principal in self._passengers:
                    raise ValueError("principal asignado a más de un micro")
                self._passengers[principal] = PassengerActor(principal, vehicle_id,
                    _seed(profile.seed, "noise:" + principal), rng.uniform(self.settings.accuracy_min, self.settings.accuracy_max))
            self._plan(vehicle_id, geometry, spec["initialProgress"], 0)
        expected_groups = json.loads(profile.raw)['limits']['nominalVehicleCount']
        if len(self._groups) != expected_groups or set(self._passengers) != profile.principals:
            raise ValueError('el escenario no coincide con los grupos y whitelist del perfil')

    @classmethod
    def from_profile(cls, profile: SimulationProfile, gtfs_dir: Path, run_id: str, **kwargs):
        return cls(profile, load_trip_geometries(profile, gtfs_dir), run_id, gtfs_dir, **kwargs)

    def _schedule(self, at: float, kind: str, principal: str, vehicle_id: str):
        self._event_order += 1
        heapq.heappush(self._scheduled, (at, self._event_order, kind, principal, vehicle_id))

    def _plan(self, vehicle_id: str, geometry: TripGeometry, progress: float, origin: float):
        ordinal = self._ordinals.get(vehicle_id, -1) + 1
        self._ordinals[vehicle_id] = ordinal
        journey = VehicleJourney(geometry, self.settings, _seed(self.profile.seed, f"{vehicle_id}:{ordinal}"),
                                 initial_progress=progress)
        self._journeys[vehicle_id], self._origins[vehicle_id] = journey, origin
        self._journey_ids[vehicle_id] = str(uuid.uuid5(uuid.UUID(self.session_namespace), f"journey:{vehicle_id}:{ordinal}"))
        group = self._groups[vehicle_id]
        for principal in group:
            self._schedule(origin, "board", principal, vehicle_id)
        for index, (arrival, duration, _) in enumerate(journey.dwell_windows):
            if len(group) >= 3 and duration > 2:
                # Una sola cuenta fuera, dos corroborantes permanecen a bordo.
                principal = group[index % len(group)]
                self._schedule(origin + arrival, "leave", principal, vehicle_id)
                self._schedule(origin + arrival + 2, "board", principal, vehicle_id)
        for principal in group:
            self._schedule(origin + journey.arrival_time, "leave", principal, vehicle_id)

    def _actor_event(self, kind: str, principal: str, vehicle_id: str, at: float,
                     elapsed: float, reason: str) -> ActorEvent | None:
        actor = self._passengers[principal]
        if kind == "board":
            if actor.session_id is not None:
                return None
            actor.boarding_count += 1
            actor.session_id = str(uuid.uuid5(uuid.UUID(self.session_namespace),
                f"{self.run_id}:{principal}:{self._journey_ids[vehicle_id]}:{actor.boarding_count}"))
            actor.boarded_at = at
        elif actor.session_id is None:
            return None
        event = ActorEvent(kind, principal, actor.session_id, vehicle_id, self._journey_ids[vehicle_id],
                           self._journeys[vehicle_id].geometry.route_id, max(at, actor.boarded_at), elapsed, reason)
        if kind == "leave":
            actor.session_id, actor.boarded_at = None, None
        return event

    def _frame(self, sample: ClockSample, events: list[ActorEvent]) -> ScenarioFrame:
        vehicles, observations = [], []
        for vehicle_id, journey in self._journeys.items():
            point = journey.at(max(0, self.elapsed - self._origins[vehicle_id]))
            actors = [self._passengers[p] for p in self._groups[vehicle_id] if self._passengers[p].session_id is not None]
            vehicles.append(VehicleReference(vehicle_id, self._journey_ids[vehicle_id], journey.geometry.route_id,
                journey.geometry.trip_id, journey.geometry.shape_id, point, len(actors)))
            if self.state != "running":
                continue
            for actor in actors:
                north, east = actor.noise(self.elapsed, self.settings)
                lat = point.lat + north / 111_320.0
                lon = point.lon + east / (111_320.0 * math.cos(math.radians(point.lat)))
                heading, unknown_reason = journey.geometry.path.reported_heading(lat, lon, point.heading, self.settings.noise_max)
                observations.append(ActorObservation(actor.principal, actor.session_id, vehicle_id,
                    self._journey_ids[vehicle_id], journey.geometry.route_id, journey.geometry.linea,
                    lat, lon, point.speed, heading, actor.accuracy, sample.unix, north, east, unknown_reason))
        return ScenarioFrame(sample.unix, self.elapsed, self.state, self.reason, tuple(vehicles), tuple(observations), tuple(events))

    def stop(self, sample: ClockSample, reason: str, *, paused: bool = False) -> ScenarioFrame:
        events = []
        for principal, actor in self._passengers.items():
            event = self._actor_event("leave", principal, actor.scenario_vehicle_id, sample.unix, self.elapsed, reason)
            if event is not None:
                events.append(event)
        self._scheduled.clear()
        self.state, self.reason = ("paused" if paused else "stopped"), reason
        return self._frame(sample, events)

    def advance(self, sample: ClockSample | None = None) -> ScenarioFrame:
        sample = sample or self.clock.read()
        if self.state in ("paused", "stopped", "finished"):
            return self._frame(sample, [])
        try:
            delta = self._guard.elapsed(sample)
        except ClockDiscontinuity as error:
            return self.stop(sample, str(error), paused=True)
        try:
            if self.profile.signatures(self.gtfs_dir) != self.profile.verified_signatures:
                return self.stop(sample, "profile_or_feed_changed", paused=True)
            if not self.profile.window(sample.unix)[0]:
                return self.stop(sample, "outside_service")
        except (OSError, ValueError, KeyError):
            return self.stop(sample, "profile_or_feed_unavailable", paused=True)
        self.elapsed += delta
        if self.elapsed >= self.profile.max_run_seconds:
            return self.stop(sample, "max_run_duration")
        self.state = "running"
        events = []
        while self._scheduled and self._scheduled[0][0] <= self.elapsed:
            elapsed, _, kind, principal, vehicle_id = heapq.heappop(self._scheduled)
            terminal = elapsed >= self._origins[vehicle_id] + self._journeys[vehicle_id].arrival_time - 1e-8
            event = self._actor_event(kind, principal, vehicle_id, sample.unix, elapsed,
                                      "boarding" if kind == "board" else ("terminal_arrival" if terminal else "alighting_at_stop"))
            if event is not None:
                events.append(event)
        if all(journey.at(self.elapsed - self._origins[key]).phase == "finished" for key, journey in self._journeys.items()):
            self.state = "finished"
        return self._frame(sample, events)

    def continue_trip(self, vehicle_id: str, route_id: str) -> None:
        if self.state not in ("running", "finished"):
            raise ValueError("el motor no admite continuar en este estado")
        current = self._journeys[vehicle_id]
        if self.elapsed - self._origins[vehicle_id] < current.finished_at:
            raise ValueError("falta finalizar viaje y pausa de terminal")
        next_geometry = self.geometries[route_id]  # solo catálogo verificado del perfil
        end = current.geometry.path.at(current.geometry.path.length_m)
        start = next_geometry.path.at(0)
        if haversine_m(end.lat, end.lon, start.lat, start.lon) > 1:
            raise ValueError("el siguiente trip no conecta físicamente con la terminal")
        for key, other in self._journeys.items():
            if key == vehicle_id or other.geometry.route_id != route_id:
                continue
            point = other.at(self.elapsed - self._origins[key])
            if point.phase != "finished" and (point.distance_m <= 300 or haversine_m(start.lat, start.lon, point.lat, point.lon) <= 300):
                raise ValueError("otro micro de la ruta está a menos de 300 m")
        self._plan(vehicle_id, next_geometry, 0, self.elapsed)
        self.state = "running"

    def write_reference(self, output: TextIO, frame: ScenarioFrame, *, include_header: bool = False) -> None:
        """Salida JSONL explícita a un stream del llamador; nunca abre una ruta."""
        common = {"dataOrigin": "simulated", "simulationRunId": self.run_id}
        if include_header:
            output.write(json.dumps({**common, "kind": "scenario", "seed": self.profile.seed,
                "scenarioVersion": self.profile.version, "manifestSha256": self.profile.sha256,
                "feedSha256": self.profile.feed_hashes, "sessionNamespace": self.session_namespace,
                "stopIssues": [asdict(issue) for geometry in self.geometries.values() for issue in geometry.issues]},
                allow_nan=False) + "\n")
        output.write(json.dumps({**common, "kind": "frame", **asdict(frame)}, allow_nan=False) + "\n")
