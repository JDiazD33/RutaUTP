"""Desvíos vigentes: el trazo que reemplaza un tramo cerrado de una ruta.

Parte de incidencias con trazo (`path`) ya validadas por
`route_changes.load_simulated`: desvíos, y también cierres u obras que indican
la calle por la que va ahora la línea. La validación acepta posiciones sobre ese
trazo, con su rumbo y un avance interpolado entre la salida y el regreso,
para que el agregador siga agrupando al micro. La simulación mueve el micro
por el mismo trazo (`recorrido_con_desvios`).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from .geo import haversine_m
from .route_changes import ROAD_REASONS, decode_polyline

RADIO_EXTREMO_M = 60
LARGO_MAXIMO_M = 5000


@dataclass(frozen=True)
class Desvio:
    alert_id: str
    route_id: str
    trazo: tuple[tuple[float, float], ...]
    inicio_m: float
    fin_m: float
    largo_ruta_m: float

    def progreso(self, fraccion: float) -> float:
        """Avance sobre la ruta original para un punto del trazo (0 a 1 del trazo)."""
        fraccion = min(max(fraccion, 0.0), 1.0)
        return (self.inicio_m + fraccion * (self.fin_m - self.inicio_m)) / self.largo_ruta_m


def acumulado(shape) -> list[float]:
    distancias = [0.0]
    for a, b in zip(shape, shape[1:]):
        distancias.append(distancias[-1] + haversine_m(*a, *b))
    return distancias


def _proyeccion(p, a, b):
    """Fracción del segmento y distancia en metros (plano local, escala urbana)."""
    kx, ky = 111_320 * math.cos(math.radians(p[0])), 110_574
    ax, ay = (a[1] - p[1]) * kx, (a[0] - p[0]) * ky
    bx, by = (b[1] - p[1]) * kx, (b[0] - p[0]) * ky
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
    return t, math.hypot(ax + t * dx, ay + t * dy)


def _pasadas(shape, distancias, punto):
    """Distancia sobre la ruta de cada segmento que pasa cerca del punto."""
    resultado = []
    for i, (a, b) in enumerate(zip(shape, shape[1:])):
        t, separacion = _proyeccion(punto, a, b)
        if separacion <= RADIO_EXTREMO_M:
            resultado.append(distancias[i] + t * (distancias[i + 1] - distancias[i]))
    return resultado


def tramo_cerrado(shape, salida, regreso) -> tuple[float, float] | None:
    """Inicio y fin del tramo que el desvío evita, en metros sobre la ruta.

    Una ruta puede pasar dos veces por la misma avenida (ida y vuelta). Se toma
    la pasada en que el regreso queda después de la salida y más cerca de ella.
    """
    distancias = acumulado(shape)
    pares = [(fin - inicio, inicio, fin)
             for inicio in _pasadas(shape, distancias, salida)
             for fin in _pasadas(shape, distancias, regreso)
             if 0 < fin - inicio <= LARGO_MAXIMO_M]
    if not pares:
        return None
    _, inicio, fin = min(pares)
    return inicio, fin


def desvios_por_ruta(alertas, feed) -> dict[str, tuple[Desvio, ...]]:
    """Desvíos con trazo de cada ruta, a partir de alertas ya validadas.

    Un atasco o un choque no cambian el recorrido: nunca traen trazo.
    """
    resultado: dict[str, list[Desvio]] = {}
    for alerta in alertas:
        if alerta.get("reason") in ROAD_REASONS or not alerta.get("path") or "endLat" not in alerta:
            continue
        ruta = feed.get(alerta["routeId"])
        trazo = tuple(decode_polyline(alerta["path"]) or ())
        if ruta is None or len(trazo) < 2:
            continue
        shape = list(ruta.shape)
        tramo = tramo_cerrado(shape, (alerta["lat"], alerta["lon"]), (alerta["endLat"], alerta["endLon"]))
        if tramo is None:
            continue
        resultado.setdefault(alerta["routeId"], []).append(
            Desvio(alerta["id"], alerta["routeId"], trazo, tramo[0], tramo[1], acumulado(shape)[-1]))
    return {ruta: tuple(sorted(lista, key=lambda d: d.inicio_m)) for ruta, lista in resultado.items()}


def _punto_en(shape, distancias, metros):
    for i in range(len(shape) - 1):
        if distancias[i + 1] >= metros:
            largo = distancias[i + 1] - distancias[i]
            t = 0.0 if largo <= 0 else (metros - distancias[i]) / largo
            a, b = shape[i], shape[i + 1]
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    return shape[-1]


def recorrido_con_desvios(shape, desvios) -> list[tuple[float, float]]:
    """La ruta con cada tramo cerrado sustituido por el trazo de su desvío.

    Los desvíos deben venir ordenados y sin solaparse; uno que se solape con el
    anterior se ignora para no producir un recorrido incoherente.
    """
    distancias = acumulado(shape)
    resultado, cursor = [], 0.0
    for desvio in desvios:
        if desvio.inicio_m < cursor:
            continue
        resultado += [p for p, d in zip(shape, distancias) if cursor <= d < desvio.inicio_m]
        resultado.append(_punto_en(shape, distancias, desvio.inicio_m))
        resultado += list(desvio.trazo)
        resultado.append(_punto_en(shape, distancias, desvio.fin_m))
        cursor = desvio.fin_m
    resultado += [p for p, d in zip(shape, distancias) if d > cursor]
    return resultado


def largo_trazo(desvio: Desvio) -> float:
    return acumulado(list(desvio.trazo))[-1]
