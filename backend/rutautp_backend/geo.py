"""Geometría para validar observaciones contra los recorridos del GTFS.

Las fórmulas replican deliberadamente las del cliente
(`RutaUTP/Utils/PolylineMatching.swift` y
`RutaUTP/Services/Tracking/Detection/RouteCandidateMatcher.swift`).

No es duplicación por descuido: si el servidor midiera distancias o rumbos con
otra convención, rechazaría observaciones que el cliente considera válidas y el
diagnóstico sería imposible. Manteniendo la misma convención, una discrepancia
significa de verdad que el mensaje no cuadra con el recorrido.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

EARTH_RADIUS_M = 6_371_000.0

METERS_PER_DEGREE_LAT = 111_320.0


@dataclass(frozen=True)
class PolylineMatch:
    """Resultado de proyectar un punto sobre una polilínea."""

    segment_index: int
    snapped_lat: float
    snapped_lon: float
    distance_m: float
    progress: float
    is_on_route: bool


def haversine_m(
    lat_a: float,
    lon_a: float,
    lat_b: float,
    lon_b: float,
) -> float:
    """Distancia en metros entre dos coordenadas."""
    delta_lat = math.radians(lat_b - lat_a)
    delta_lon = math.radians(lon_b - lon_a)

    rad_lat_a = math.radians(lat_a)
    rad_lat_b = math.radians(lat_b)

    h = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(rad_lat_a) * math.cos(rad_lat_b) * math.sin(delta_lon / 2) ** 2
    )

    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(h)))


def closest_point_on_segment(
    p_lat: float,
    p_lon: float,
    a_lat: float,
    a_lon: float,
    b_lat: float,
    b_lon: float,
) -> tuple[float, float, float, float, float]:
    """Proyección ortogonal de `p` sobre el segmento `a-b`.

    Trabaja en un plano local en metros anclado a la latitud de `a`, la misma
    aproximación equirectangular que usa el cliente. Es suficiente para
    segmentos urbanos y evita trigonometría esférica por cada vértice.

    Devuelve `(lat, lon, distancia_m, longitud_hasta_el_punto, longitud_del_segmento)`.
    """
    meters_per_degree_lon = METERS_PER_DEGREE_LAT * math.cos(math.radians(a_lat))

    ax = a_lon * meters_per_degree_lon
    ay = a_lat * METERS_PER_DEGREE_LAT
    bx = b_lon * meters_per_degree_lon
    by = b_lat * METERS_PER_DEGREE_LAT
    px = p_lon * meters_per_degree_lon
    py = p_lat * METERS_PER_DEGREE_LAT

    dx = bx - ax
    dy = by - ay
    segment_length_squared = dx * dx + dy * dy

    if segment_length_squared <= 0:
        # El "segmento" es en realidad un punto repetido.
        distance = haversine_m(p_lat, p_lon, a_lat, a_lon)
        return a_lat, a_lon, distance, 0.0, 0.0

    # t = fracción a lo largo de a-b, acotada a [0, 1].
    t = ((px - ax) * dx + (py - ay) * dy) / segment_length_squared
    t = min(max(t, 0.0), 1.0)

    closest_x = ax + t * dx
    closest_y = ay + t * dy

    distance = math.hypot(px - closest_x, py - closest_y)
    segment_length = math.sqrt(segment_length_squared)

    return (
        closest_y / METERS_PER_DEGREE_LAT,
        closest_x / meters_per_degree_lon,
        distance,
        t * segment_length,
        segment_length,
    )


def match_point_to_polyline(
    lat: float,
    lon: float,
    polyline: list[tuple[float, float]],
    threshold_m: float = 20.0,
) -> PolylineMatch | None:
    """Proyecta el punto sobre la polilínea y devuelve el mejor ajuste.

    Devuelve `None` solo si la polilínea tiene menos de dos puntos. El umbral
    **no** filtra el resultado: se informa en `is_on_route` para que quien llame
    decida. El cliente tiene un defecto aquí (pasa un umbral que nunca se usa
    para filtrar); en el servidor se expone explícitamente para no repetirlo.
    """
    if len(polyline) < 2:
        return None

    best_index = 0
    best_lat = polyline[0][0]
    best_lon = polyline[0][1]
    best_distance = math.inf
    best_prefix_length = 0.0
    best_along_length = 0.0

    accumulated_length = 0.0

    for index in range(len(polyline) - 1):
        a_lat, a_lon = polyline[index]
        b_lat, b_lon = polyline[index + 1]

        (
            snapped_lat,
            snapped_lon,
            distance,
            along_length,
            segment_length,
        ) = closest_point_on_segment(lat, lon, a_lat, a_lon, b_lat, b_lon)

        if distance < best_distance:
            best_index = index
            best_lat = snapped_lat
            best_lon = snapped_lon
            best_distance = distance
            best_prefix_length = accumulated_length
            best_along_length = along_length

        accumulated_length += segment_length

    if accumulated_length > 0:
        progress = (best_prefix_length + best_along_length) / accumulated_length
        progress = min(max(progress, 0.0), 1.0)
    else:
        progress = 0.0

    return PolylineMatch(
        segment_index=best_index,
        snapped_lat=best_lat,
        snapped_lon=best_lon,
        distance_m=best_distance,
        progress=progress,
        is_on_route=best_distance <= threshold_m,
    )


def bearing_deg(
    from_lat: float,
    from_lon: float,
    to_lat: float,
    to_lon: float,
) -> float:
    """Rumbo inicial de `from` hacia `to`, en grados [0, 360)."""
    start_latitude = math.radians(from_lat)
    end_latitude = math.radians(to_lat)
    longitude_difference = math.radians(to_lon - from_lon)

    y = math.sin(longitude_difference) * math.cos(end_latitude)
    x = math.cos(start_latitude) * math.sin(end_latitude) - math.sin(
        start_latitude
    ) * math.cos(end_latitude) * math.cos(longitude_difference)

    degrees = math.degrees(math.atan2(y, x))

    return (degrees + 360.0) % 360.0


def segment_bearing_deg(
    polyline: list[tuple[float, float]],
    segment_index: int,
) -> float:
    """Rumbo del segmento indicado. `0` si el índice no es utilizable."""
    if segment_index < 0 or segment_index + 1 >= len(polyline):
        return 0.0

    start = polyline[segment_index]
    end = polyline[segment_index + 1]

    return bearing_deg(start[0], start[1], end[0], end[1])


def heading_difference_deg(device_heading: float, route_heading: float) -> float:
    """Diferencia angular mínima entre dos rumbos, en grados [0, 180].

    Un rumbo desconocido (negativo) devuelve 180: no debe contar como alineado.
    """
    if not math.isfinite(device_heading) or device_heading < 0:
        return 180.0

    raw_difference = abs(device_heading - route_heading)

    return min(raw_difference, 360.0 - raw_difference)


def sanitize_speed(value: float) -> float:
    """Velocidad válida para el contrato JSON. `-1` significa desconocida.

    Mismo techo que el cliente (100 m/s = 360 km/h) para que el valor que
    publica el servidor no se recorte otra vez en el teléfono.
    """
    if not math.isfinite(value):
        return -1.0

    return min(max(value, -1.0), 100.0)


def sanitize_heading(value: float) -> float:
    """Rumbo normalizado a [0, 360). `-1` significa desconocido."""
    if not math.isfinite(value) or value < 0:
        return -1.0

    return math.fmod(value, 360.0)


def is_valid_coordinate(lat: float, lon: float) -> bool:
    """Coordenada finita y dentro de rango."""
    if not math.isfinite(lat) or not math.isfinite(lon):
        return False

    return abs(lat) <= 90.0 and abs(lon) <= 180.0


def decimate(
    polyline: list[tuple[float, float]],
    max_points: int,
) -> list[tuple[float, float]]:
    """Reduce la densidad conservando el orden y el último punto.

    Igual que el cliente. El servidor valida contra el recorrido completo, pero
    esta función sirve para el informe y para comparar ambas implementaciones.
    """
    if len(polyline) <= max_points or max_points < 2:
        return list(polyline)

    step = len(polyline) / max_points

    result = [polyline[min(int(index * step), len(polyline) - 1)] for index in range(max_points)]
    result[-1] = polyline[-1]

    return result
