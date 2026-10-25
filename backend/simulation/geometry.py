"""Geometría/trip exactos y paraderos GTFS; preparación sin efectos externos."""

from __future__ import annotations

from bisect import bisect_right
from collections import Counter
import csv
from dataclasses import dataclass
import math
from pathlib import Path

from rutautp_backend.geo import bearing_deg, closest_point_on_segment, haversine_m, heading_difference_deg, is_valid_coordinate
from rutautp_backend.gtfs import GtfsFeed, load_feed
from rutautp_backend.simulation_profile import SimulationProfile


def number(value, name: str, *, minimum: float = 0, maximum: float = math.inf) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{name} debe ser numérico y finito")
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} fuera de rango")
    return float(value)


@dataclass(frozen=True)
class PathPoint:
    lat: float
    lon: float
    heading: float
    distance_m: float


@dataclass(frozen=True)
class Projection:
    along_m: float
    distance_m: float
    lat: float
    lon: float


class RoutePath:
    def __init__(self, coordinates):
        points = []
        original = []
        accumulated = [0.0]
        for lat, lon in coordinates:
            number(lat, "lat", minimum=-90, maximum=90)
            number(lon, "lon", minimum=-180, maximum=180)
            point = (float(lat), float(lon))
            original.append(point)
            if points:
                length = haversine_m(*points[-1], *point)
                if length <= 1e-6:
                    continue
                accumulated.append(accumulated[-1] + length)
            points.append(point)
        if len(points) < 2:
            raise ValueError("shape sin segmentos de longitud positiva")
        self.points = tuple(points)
        self.accumulated = tuple(accumulated)
        self.length_m = accumulated[-1]
        self._headings = tuple(bearing_deg(*a, *b) for a, b in zip(points, points[1:]))
        self._original = tuple(original)
        self._longitude_scale = 111_320 * math.cos(math.radians(points[0][0]))
        self._cells, self._long_segments = {}, []
        # Índice local del shape original: conserva orden/segmentos repetidos
        # para reconocer ambigüedad igual que el validador, sin recorrer todo
        # el shape por cada uno de los 30 pasajeros.
        for index, (a, b) in enumerate(zip(original, original[1:])):
            ax, ay = self._cell(*a)
            bx, by = self._cell(*b)
            if (abs(bx - ax) + 1) * (abs(by - ay) + 1) > 4096:
                self._long_segments.append(index)
                continue
            for x in range(min(ax, bx), max(ax, bx) + 1):
                for y in range(min(ay, by), max(ay, by) + 1):
                    self._cells.setdefault((x, y), []).append(index)

    def _cell(self, lat: float, lon: float) -> tuple[int, int]:
        return math.floor(lon * self._longitude_scale / 50), math.floor(lat * 111_320 / 50)

    def reported_heading(self, lat: float, lon: float, physical_heading: float, noise_max: float) -> tuple[float, str | None]:
        if physical_heading < 0:
            return -1, None
        x, y = self._cell(lat, lon)
        radius = math.ceil(noise_max / 50) + 1
        candidates = set(self._long_segments)
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                candidates.update(self._cells.get((x + dx, y + dy), ()))
        closest, best_gap = None, math.inf
        for index in sorted(candidates):
            a, b = self._original[index:index + 2]
            gap = closest_point_on_segment(lat, lon, *a, *b)[2]
            if gap < best_gap:
                closest, best_gap = index, gap
        if closest is None:
            return -1, "unavailable_gtfs_heading"
        a, b = self._original[closest:closest + 2]
        canonical = bearing_deg(*a, *b)
        if heading_difference_deg(physical_heading, canonical) > 60:
            # En un tramo superpuesto no inventar un rumbo contrario para
            # satisfacer al matching: conservarlo en verdad física y declarar
            # incertidumbre de la lectura con el -1 ya previsto en v1.
            return -1, "ambiguous_gtfs_heading"
        return physical_heading, None

    def at(self, distance_m: float) -> PathPoint:
        number(distance_m, "distancia", minimum=-math.inf)
        distance_m = min(max(distance_m, 0.0), self.length_m)
        index = min(bisect_right(self.accumulated, distance_m) - 1, len(self.points) - 2)
        a, b = self.points[index:index + 2]
        length = self.accumulated[index + 1] - self.accumulated[index]
        fraction = (distance_m - self.accumulated[index]) / length
        return PathPoint(a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1]),
                         self._headings[index], distance_m)

    def project_stop(self, lat: float, lon: float, after_m: float, max_distance_m: float) -> tuple[Projection | None, str]:
        candidates = []
        for index, (a, b) in enumerate(zip(self.points, self.points[1:])):
            snapped_lat, snapped_lon, gap, along, length = closest_point_on_segment(lat, lon, *a, *b)
            fraction = along / length
            distance = self.accumulated[index] + fraction * (self.accumulated[index + 1] - self.accumulated[index])
            candidates.append(Projection(distance, gap, snapped_lat, snapped_lon))
        best_gap = min(p.distance_m for p in candidates)
        if best_gap > max_distance_m:
            return None, "too_far_from_shape"
        # No adivinar un ramal en cruces/bucles. Los candidatos casi igual de
        # próximos deben representar el mismo entorno de distancia recorrida.
        near = [p for p in candidates if p.distance_m <= best_gap + 0.75 and p.along_m >= after_m - 1e-6]
        if not near:
            return None, "out_of_sequence"
        if max(p.along_m for p in near) - min(p.along_m for p in near) > 25:
            return None, "ambiguous_projection"
        best = min(near, key=lambda p: (p.distance_m, p.along_m))
        if best.along_m <= after_m + 1e-6:
            return None, "duplicate_projected_stop"
        return best, ""


@dataclass(frozen=True)
class RouteStop:
    stop_id: str
    sequence: int
    distance_m: float
    lat: float
    lon: float


@dataclass(frozen=True)
class StopIssue:
    route_id: str
    trip_id: str
    stop_id: str
    sequence: int | None
    reason: str


@dataclass(frozen=True)
class TripGeometry:
    route_id: str
    trip_id: str
    shape_id: str
    linea: str
    path: RoutePath
    stops: tuple[RouteStop, ...]
    issues: tuple[StopIssue, ...] = ()


def _rows(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        yield from csv.DictReader(handle)


def load_trip_geometries(profile: SimulationProfile, gtfs_dir: Path,
                         feed: GtfsFeed | None = None) -> dict[str, TripGeometry]:
    import json
    body = json.loads(profile.raw)
    if profile.signatures(gtfs_dir) != profile.verified_signatures:
        raise ValueError("perfil/feed cambiados desde su verificación")
    feed = feed or load_feed(gtfs_dir)
    specs = body["vehicles"]
    selected_shapes = {v["shapeId"] for v in specs}
    trips = {}
    for row in _rows(gtfs_dir / "trips.txt"):
        trip_id = row["trip_id"].strip()
        if trip_id in trips:
            raise ValueError("trip_id duplicado")
        trips[trip_id] = (row["route_id"].strip(), row.get("shape_id", "").strip())
    shapes = {shape: [] for shape in selected_shapes}
    for row in _rows(gtfs_dir / "shapes.txt"):
        shape_id = row["shape_id"].strip()
        if shape_id in shapes:
            shapes[shape_id].append((int(row["shape_pt_sequence"]), float(row["shape_pt_lat"]), float(row["shape_pt_lon"])))
    stops = {}
    for row in _rows(gtfs_dir / "stops.txt"):
        try:
            point = (float(row["stop_lat"]), float(row["stop_lon"]))
            if is_valid_coordinate(*point):
                stops[row["stop_id"].strip()] = point
        except (ValueError, KeyError):
            continue
    selected_trips = {v["tripId"] for v in specs}
    stop_times = {trip: [] for trip in selected_trips}
    invalid_times = {trip: [] for trip in selected_trips}
    for row in _rows(gtfs_dir / "stop_times.txt"):
        trip_id = row["trip_id"].strip()
        if trip_id in stop_times:
            stop_id = row.get("stop_id", "").strip()
            try:
                sequence = int(row["stop_sequence"])
                if sequence < 0:
                    raise ValueError("secuencia negativa")
                stop_times[trip_id].append((sequence, stop_id))
            except (ValueError, KeyError):
                invalid_times[trip_id].append(stop_id)
    geometries = {}
    max_gap = number(body["movement"]["maxStopProjectionDistanceMeters"], "proyección", minimum=0, maximum=50)
    for spec in specs:
        route_id, trip_id, shape_id = spec["routeId"], spec["tripId"], spec["shapeId"]
        trip = trips.get(trip_id)
        route = feed.get(route_id)
        first_trip = min((key for key, (route_key, _) in trips.items() if route_key == route_id), default=None)
        if (trip is None or trip[0] != route_id or (trip[1] or route_id) != shape_id
                or trip_id != first_trip or route is None or route.linea != spec["linea"]):
            raise ValueError("route/trip/shape/línea no coinciden con el feed del backend")
        rows = sorted(shapes[shape_id])
        if len({r[0] for r in rows}) != len(rows):
            raise ValueError("shape_pt_sequence duplicado")
        coordinates = tuple((lat, lon) for _, lat, lon in rows)
        if coordinates != route.shape:
            raise ValueError("el shape elegido difiere del que valida el backend")
        path = RoutePath(coordinates)
        counts = Counter(seq for seq, _ in stop_times[trip_id])
        accepted, issues = [], [StopIssue(route_id, trip_id, stop, None, "invalid_stop_sequence") for stop in invalid_times[trip_id]]
        after = -1.0
        for sequence, stop_id in sorted(stop_times[trip_id]):
            reason = ""
            if counts[sequence] > 1:
                reason = "duplicate_stop_sequence"
            elif stop_id not in stops:
                reason = "missing_or_invalid_stop"
            else:
                projection, reason = path.project_stop(*stops[stop_id], after, max_gap)
                if projection is not None:
                    accepted.append(RouteStop(stop_id, sequence, projection.along_m, projection.lat, projection.lon))
                    after = projection.along_m
            if reason:
                issues.append(StopIssue(route_id, trip_id, stop_id, sequence, reason))
        geometries[route_id] = TripGeometry(route_id, trip_id, shape_id, route.linea, path,
                                            tuple(accepted), tuple(issues))
    if len(geometries) != len(specs):
        raise ValueError("el escenario inicial necesita una ruta distinta por micro")
    if profile.signatures(gtfs_dir) != profile.verified_signatures:
        raise ValueError("perfil/feed cambiados durante la adaptación")
    return geometries
