"""Fixtures compartidas por las pruebas.

Se usa el feed GTFS real del repositorio, no uno inventado: así las pruebas
comprueban que el parseo funciona con el formato que tiene el feed de Trujillo
(con comillas dentro de `route_short_name`, acentos y flechas).
"""

from __future__ import annotations

from pathlib import Path

import pytest

from rutautp_backend.config import Config
from rutautp_backend.gtfs import GtfsFeed, load_feed

REPO_ROOT = Path(__file__).resolve().parents[2]
GTFS_DIR = REPO_ROOT / "gtfs"

# Ruta de referencia del feed real, usada en varias pruebas.
SAMPLE_ROUTE_ID = "17350695"
SAMPLE_LINE = "C-01"


@pytest.fixture(scope="session")
def feed() -> GtfsFeed:
    return load_feed(GTFS_DIR)


@pytest.fixture
def config() -> Config:
    """Configuración por defecto, independiente del entorno del proceso.

    La persistencia y el latido se desactivan salvo en las pruebas que los
    ejercitan: sin esto, cada prueba que construye un `Bridge` escribiría en el
    histórico y en el latido reales del repositorio.

    El espacio de nombres de vehículo se fija para que los identificadores sean
    reproducibles: en producción se genera uno por arranque.
    """
    return Config(
        gtfs_dir=GTFS_DIR,
        database_path="",
        health_file="",
        vehicle_namespace="t0",
    )


#: Sufijo que llevan los identificadores con el espacio de nombres de prueba.
VEHICLE_NAMESPACE = "t0"


def vehicle_id(route_id: str, ordinal: int) -> str:
    """Identificador esperado de un vehículo con el espacio de nombres de prueba.

    El formato real incluye un espacio de nombres por arranque (D02): sin él, un
    `{ruta}-01` de un proceso nuevo heredaría la identidad visible del anterior.
    """
    return f"{route_id}-{VEHICLE_NAMESPACE}-{ordinal:02d}"


@pytest.fixture(scope="session")
def sample_route(feed: GtfsFeed):
    route = feed.get(SAMPLE_ROUTE_ID)

    assert route is not None, "el feed real debe contener la ruta de referencia"

    return route


def point_on_route(route, progress: float) -> tuple[float, float]:
    """Punto sobre el recorrido, a la fracción `progress` de sus vértices.

    Sirve para construir observaciones válidas sin inventar coordenadas: es el
    mismo recorrido contra el que luego se validan.
    """
    index = min(int(progress * (len(route.shape) - 1)), len(route.shape) - 2)

    return route.shape[index]


def offset_meters(
    latitude: float,
    longitude: float,
    north_m: float = 0.0,
    east_m: float = 0.0,
) -> tuple[float, float]:
    """Desplaza un punto una distancia aproximada en metros."""
    meters_per_degree_lat = 111_320.0
    import math

    meters_per_degree_lon = meters_per_degree_lat * math.cos(math.radians(latitude))

    return (
        latitude + north_m / meters_per_degree_lat,
        longitude + east_m / meters_per_degree_lon,
    )
