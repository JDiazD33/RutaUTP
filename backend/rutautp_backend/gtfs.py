"""Lectura del feed GTFS estático.

El servidor necesita los recorridos para comprobar que una observación cae
sobre una ruta real. Se apoya en el mismo feed que embebe la app
(`gtfs/*.txt`), así que ambos lados validan contra la misma geometría.

El parseo de `route_short_name` replica `GTFSNombreParser` del cliente: los
nombres del feed vienen como `C-01 "B"`, y la línea pública es la parte previa
a la primera comilla. Esa coincidencia importa, porque el servidor comprueba
que la `linea` que declara el cliente sea la de la ruta que dice estar usando.
"""

from __future__ import annotations

import csv
import logging
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

# Archivos del feed que se leen. Si falta alguno, se avisa y se sigue: el
# backend puede arrancar con un feed parcial y rechazar lo que no pueda validar.
REQUIRED_FILES = ("routes.txt", "trips.txt", "shapes.txt")
OPTIONAL_FILES = ("agency.txt", "stops.txt", "stop_times.txt", "frequencies.txt")


class GtfsError(RuntimeError):
    """El feed no se pudo leer."""


@dataclass(frozen=True)
class RouteGeometry:
    """Recorrido de una ruta, listo para validar observaciones."""

    route_id: str
    linea: str
    variante: str
    empresa: str
    shape: tuple[tuple[float, float], ...]

    @property
    def point_count(self) -> int:
        return len(self.shape)

    @property
    def length_m(self) -> float:
        from .geo import haversine_m

        total = 0.0
        for index in range(len(self.shape) - 1):
            total += haversine_m(*self.shape[index], *self.shape[index + 1])

        return total


@dataclass
class GtfsFeed:
    """Feed cargado en memoria, indexado por `route_id`."""

    routes: dict[str, RouteGeometry] = field(default_factory=dict)
    source_dir: Path | None = None

    @property
    def route_count(self) -> int:
        return len(self.routes)

    def get(self, route_id: str) -> RouteGeometry | None:
        return self.routes.get(route_id)

    def routes_with_geometry(self) -> list[RouteGeometry]:
        return [route for route in self.routes.values() if route.point_count >= 2]

    def summary(self) -> str:
        usable = len(self.routes_with_geometry())
        points = sum(route.point_count for route in self.routes.values())

        return (
            f"{self.route_count} rutas ({usable} con geometría usable), "
            f"{points} vértices"
        )


def parse_short_name(short_name: str) -> tuple[str, str]:
    """`C-01 "B"` -> `("C-01", "B")`.

    Port de `GTFSNombreParser.lineaYVariante`. Si no hay comillas, la variante
    queda vacía y la línea es el nombre completo.
    """
    parts = short_name.split('"')

    linea = parts[0].strip() if parts else short_name.strip()
    variante = parts[1].strip() if len(parts) > 1 else ""

    return (linea or short_name, variante)


def _read_table(path: Path) -> list[dict[str, str]]:
    """Lee un `.txt` del feed como lista de diccionarios.

    `utf-8-sig` tolera el BOM que algunos exportadores añaden.
    """
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)

        return [row for row in reader]


def load_feed(gtfs_dir: Path) -> GtfsFeed:
    """Carga el feed desde `gtfs_dir`.

    Lanza `GtfsError` si el directorio no existe o falta un archivo esencial.
    """
    if not gtfs_dir.is_dir():
        raise GtfsError(f"No existe el directorio del feed: {gtfs_dir}")

    missing = [name for name in REQUIRED_FILES if not (gtfs_dir / name).is_file()]

    if missing:
        raise GtfsError(
            f"Faltan archivos del feed en {gtfs_dir}: {', '.join(missing)}"
        )

    for name in OPTIONAL_FILES:
        if not (gtfs_dir / name).is_file():
            logger.warning("Archivo opcional ausente en el feed: %s", name)

    agencies = _load_agencies(gtfs_dir)
    shape_by_route = _load_shape_by_route(gtfs_dir)

    feed = GtfsFeed(source_dir=gtfs_dir)

    for row in _read_table(gtfs_dir / "routes.txt"):
        route_id = row.get("route_id", "").strip()

        if not route_id:
            continue

        linea, variante = parse_short_name(row.get("route_short_name", ""))

        feed.routes[route_id] = RouteGeometry(
            route_id=route_id,
            linea=linea,
            variante=variante,
            empresa=agencies.get(row.get("agency_id", "").strip(), "Transporte Trujillo"),
            shape=shape_by_route.get(route_id, ()),
        )

    return feed


def _load_agencies(gtfs_dir: Path) -> dict[str, str]:
    """`agency_id` -> nombre comercial."""
    path = gtfs_dir / "agency.txt"

    if not path.is_file():
        return {}

    return {
        row.get("agency_id", "").strip(): row.get("agency_name", "").strip()
        for row in _read_table(path)
        if row.get("agency_id")
    }


def _load_shape_by_route(
    gtfs_dir: Path,
) -> dict[str, tuple[tuple[float, float], ...]]:
    """`route_id` -> recorrido ordenado por `shape_pt_sequence`.

    Reproduce el encadenado del cliente: `route_id` -> `trip_id` -> `shape_id`.
    Si un trip no declara shape, se cae al propio `route_id` como identificador,
    que es lo que hace el feed de Trujillo.
    """
    route_by_trip: dict[str, str] = {}
    shape_by_trip: dict[str, str] = {}

    for row in _read_table(gtfs_dir / "trips.txt"):
        trip_id = row.get("trip_id", "").strip()

        if not trip_id:
            continue

        route_by_trip[trip_id] = row.get("route_id", "").strip()
        shape_by_trip[trip_id] = row.get("shape_id", "").strip()

    # trip_id por route_id: el feed tiene un trip por ruta, pero se elige el
    # primero de forma determinista para no depender del orden de las líneas.
    trip_by_route: dict[str, str] = {}

    for trip_id, route_id in sorted(route_by_trip.items()):
        if route_id and route_id not in trip_by_route:
            trip_by_route[route_id] = trip_id

    # shape_id -> puntos ordenados
    points_by_shape: dict[str, list[tuple[int, float, float]]] = {}

    with (gtfs_dir / "shapes.txt").open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            shape_id = row.get("shape_id", "").strip()

            if not shape_id:
                continue

            try:
                latitude = float(row["shape_pt_lat"])
                longitude = float(row["shape_pt_lon"])
                sequence = int(row["shape_pt_sequence"])
            except (KeyError, ValueError):
                continue

            points_by_shape.setdefault(shape_id, []).append(
                (sequence, latitude, longitude)
            )

    shape_by_route: dict[str, tuple[tuple[float, float], ...]] = {}

    for route_id in sorted({route for route in route_by_trip.values() if route}):
        trip_id = trip_by_route.get(route_id, route_id)
        shape_id = shape_by_trip.get(trip_id, "") or route_id

        points = points_by_shape.get(shape_id)

        if points is None and shape_id != route_id:
            points = points_by_shape.get(route_id)

        if not points:
            logger.warning(
                "La ruta %s no tiene geometría (shape_id=%r)", route_id, shape_id
            )
            continue

        points.sort(key=lambda item: item[0])
        shape_by_route[route_id] = tuple((lat, lon) for _, lat, lon in points)

    return shape_by_route
