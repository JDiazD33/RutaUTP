#!/usr/bin/env python3
"""¿Compensa suavizar la posición promediando una ventana?

Promediar las últimas observaciones reduce el ruido del GPS, pero introduce
retraso: la media de muestras de hasta W segundos atrás va por detrás del
vehículo. A 8 m/s, una ventana de 5 s son hasta 40 m de retraso, que puede ser
peor que el ruido de ~10 m que pretende quitar.

Este script simula varios teléfonos publicando desde un mismo bus sobre el
recorrido real de una línea y mide, para cada estrategia:

  - error medio  : distancia media entre la posición reportada y la verdad
  - salto medio  : cuánto se mueve el marcador entre dos publicaciones
                   (lo que se percibe como temblor en el mapa)

Uso:
    python tools/smoothing_tradeoff.py
    python tools/smoothing_tradeoff.py --phones 5 --speed 8
"""

from __future__ import annotations

import argparse
import math
import random
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from rutautp_backend.geo import haversine_m  # noqa: E402
from rutautp_backend.gtfs import load_feed  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]

# Error típico de un GPS de teléfono en ciudad, en metros.
DEFAULT_GPS_SIGMA_M = 8.0

# Cada cuántos segundos publica una baliza (igual que el cliente).
PUBLISH_INTERVAL_S = 5.0

DEFAULT_ROUTE_ID = "17350695"


def cumulative_distances(shape) -> list[float]:
    """Distancia acumulada en metros a lo largo del recorrido."""
    acumulados = [0.0]

    for index in range(len(shape) - 1):
        acumulados.append(
            acumulados[-1] + haversine_m(*shape[index], *shape[index + 1])
        )

    return acumulados


def position_at(shape, acumulados: list[float], distance_m: float):
    """Punto del recorrido a `distance_m` del inicio, interpolado."""
    total = acumulados[-1]
    distance_m = max(0.0, min(distance_m, total))

    lo, hi = 0, len(acumulados) - 1
    while lo < hi - 1:
        mid = (lo + hi) // 2
        if acumulados[mid] <= distance_m:
            lo = mid
        else:
            hi = mid

    tramo = acumulados[lo + 1] - acumulados[lo]
    fraccion = 0.0 if tramo <= 0 else (distance_m - acumulados[lo]) / tramo

    a, b = shape[lo], shape[lo + 1]

    return (
        a[0] + (b[0] - a[0]) * fraccion,
        a[1] + (b[1] - a[1]) * fraccion,
    )


def displace(lat: float, lon: float, north_m: float, east_m: float):
    """Desplaza un punto en metros."""
    meters_per_degree_lat = 111_320.0
    meters_per_degree_lon = meters_per_degree_lat * math.cos(math.radians(lat))

    return (
        lat + north_m / meters_per_degree_lat,
        lon + east_m / meters_per_degree_lon,
    )


def simulate(
    shape,
    acumulados,
    *,
    phones: int,
    speed_ms: float,
    sigma_m: float,
    duration_s: float,
    seed: int,
):
    """Devuelve, por instante, la lista de (timestamp, lat, lon) de cada teléfono."""
    rng = random.Random(seed)

    # Las balizas publican cada 5 s, pero no sincronizadas entre sí.
    phases = [index * PUBLISH_INTERVAL_S / phones for index in range(phones)]

    muestras_por_tel: list[list[tuple[float, float, float]]] = [
        [] for _ in range(phones)
    ]

    for index, phase in enumerate(phases):
        t = phase
        while t <= duration_s:
            verdad = position_at(shape, acumulados, speed_ms * t)

            norte = rng.gauss(0.0, sigma_m)
            este = rng.gauss(0.0, sigma_m)

            lat, lon = displace(verdad[0], verdad[1], norte, este)

            muestras_por_tel[index].append((t, lat, lon))
            t += PUBLISH_INTERVAL_S

    return muestras_por_tel


def evaluate(
    shape,
    acumulados,
    muestras_por_tel,
    *,
    speed_ms: float,
    window_s: float | None,
    duration_s: float,
    step_s: float = 1.0,
):
    """Error medio y salto medio de una estrategia.

    `window_s = None` es la estrategia actual: tomar la muestra más reciente.
    """
    errores: list[float] = []
    saltos: list[float] = []

    anterior = None
    t = PUBLISH_INTERVAL_S

    while t <= duration_s:
        # Última muestra de cada teléfono hasta `t`.
        candidatas = []

        for muestras in muestras_por_tel:
            vistas = [m for m in muestras if m[0] <= t]

            if vistas:
                candidatas.append(vistas[-1])

        if not candidatas:
            t += step_s
            continue

        if window_s is None:
            elegidas = [max(candidatas, key=lambda m: m[0])]
        else:
            mas_nueva = max(m[0] for m in candidatas)
            elegidas = [m for m in candidatas if m[0] >= mas_nueva - window_s]

        lat = statistics.fmean(m[1] for m in elegidas)
        lon = statistics.fmean(m[2] for m in elegidas)

        verdad = position_at(shape, acumulados, speed_ms * t)
        errores.append(haversine_m(lat, lon, verdad[0], verdad[1]))

        if anterior is not None:
            saltos.append(haversine_m(lat, lon, anterior[0], anterior[1]))

        anterior = (lat, lon)
        t += step_s

    return (
        statistics.fmean(errores) if errores else float("nan"),
        statistics.fmean(saltos) if saltos else float("nan"),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--route", default=DEFAULT_ROUTE_ID)
    parser.add_argument("--phones", type=int, default=3)
    parser.add_argument("--speed", type=float, default=8.0, help="m/s")
    parser.add_argument("--sigma", type=float, default=DEFAULT_GPS_SIGMA_M)
    parser.add_argument("--duration", type=float, default=900.0)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument(
        "--windows",
        default="1,2,3,5,10",
        help="ventanas a comparar, en segundos",
    )

    args = parser.parse_args()

    feed = load_feed(REPO_ROOT / "gtfs")
    route = feed.get(args.route)

    if route is None:
        print(f"la ruta {args.route} no está en el feed", file=sys.stderr)
        return 1

    shape = list(route.shape)
    acumulados = cumulative_distances(shape)

    print(
        f"línea {route.linea}: {len(shape)} vértices, "
        f"{acumulados[-1] / 1000:.1f} km"
    )
    print(
        f"simulación: {args.phones} teléfonos, {args.speed:.1f} m/s, "
        f"sigma GPS {args.sigma:.1f} m, {args.duration:.0f} s, "
        f"publicando cada {PUBLISH_INTERVAL_S:.0f} s"
    )
    print("")

    muestras = simulate(
        shape,
        acumulados,
        phones=args.phones,
        speed_ms=args.speed,
        sigma_m=args.sigma,
        duration_s=args.duration,
        seed=args.seed,
    )

    print(f"{'estrategia':<22}{'error medio':>14}{'salto medio':>14}")

    error, salto = evaluate(
        shape,
        acumulados,
        muestras,
        speed_ms=args.speed,
        window_s=None,
        duration_s=args.duration,
    )
    print(f"{'más reciente (actual)':<22}{error:>11.1f} m{salto:>11.1f} m")

    for window in (float(w) for w in args.windows.split(",")):
        error, salto = evaluate(
            shape,
            acumulados,
            muestras,
            speed_ms=args.speed,
            window_s=window,
            duration_s=args.duration,
        )
        print(f"{f'ventana de {window:.0f} s':<22}{error:>11.1f} m{salto:>11.1f} m")

    return 0


if __name__ == "__main__":
    sys.exit(main())
