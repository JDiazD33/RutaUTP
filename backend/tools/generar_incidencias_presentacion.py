#!/usr/bin/env python3
"""Genera simulation/incidencias-presentacion.json desde el GTFS.

Solo incidencias reales o comprobadas en la calle; ya no se reparten motivos
inventados a lo largo de la C-01:

- C-01 «B»: la obra en la Av. Nicolás de Piérola (MPT, noviembre de 2026), desde
  la entrada por la Av. América Norte hasta el Hospital Primavera.
- M-34 «A»: el desvío de la prueba de la app, que sale en Av. Nicolás de
  Piérola, va por calles que usa la CT-29 TA y retoma en Av. Gerónimo de la
  Torre. Su calle nueva sale de tools/prueba-desvio/desvio-M-34-A.gpx.
- Obra real en la Av. Nicolás de Piérola (MPT, noviembre de 2026): cada línea
  que entra desde la Av. España rumbo al norte sigue el desvío oficial por Vera
  Enríquez, Federico Chopin, Franz Liszt, Sibelius y Dunker Lavalle. Los GPX
  tools/prueba-desvio/desvio-pierola-<routeId>.gpx salen de
  backend/tools/trazar_desvio_pierola.py.

Al terminar valida el archivo con `load_simulated`, igual que el backend.

Uso, desde RutaUTP/backend:
    .venv/bin/python tools/generar_incidencias_presentacion.py
"""
from __future__ import annotations

import csv
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from rutautp_backend.desvios import tramo_cerrado  # noqa: E402
from rutautp_backend.geo import haversine_m, match_point_to_polyline  # noqa: E402
from rutautp_backend.gtfs import load_feed  # noqa: E402
from rutautp_backend.route_changes import encode_polyline, load_simulated  # noqa: E402

GTFS = ROOT / "gtfs"
GPX = ROOT / "tools" / "prueba-desvio" / "desvio-M-34-A.gpx"
SALIDA = ROOT / "backend" / "simulation" / "incidencias-presentacion.json"
LINEA_B = "17350695"   # C-01 «B»
LINEA_A = "17434457"   # M-34 «A»
SALIDA_M, REGRESO_M = 60, 35   # mismos umbrales que TrazadorDesvio en la app
# Obra en Nicolás de Piérola: inicio del tramo donde las líneas entran desde el
# sur (cruce con la Av. América Norte) y Hospital Primavera, según OpenStreetMap.
ENTRADA_TRAMO = (-8.10575, -79.03443)
HOSPITAL_PRIMAVERA = (-8.10159, -79.03573)


def punto_en(shape, metros):
    """Punto del recorrido a `metros` desde su inicio."""
    recorrido = 0.0
    for a, b in zip(shape, shape[1:]):
        paso = haversine_m(*a, *b)
        if paso and recorrido + paso >= metros:
            t = (metros - recorrido) / paso
            return (round(a[0] + (b[0] - a[0]) * t, 6), round(a[1] + (b[1] - a[1]) * t, 6))
        recorrido += paso
    return shape[-1]


def paraderos():
    with (GTFS / "stops.txt").open(encoding="utf-8-sig") as archivo:
        return [(f["stop_name"].strip(), float(f["stop_lat"]), float(f["stop_lon"]))
                for f in csv.DictReader(archivo)]


def referencia(punto, stops):
    """Nombre del paradero más cercano, como referencia del lugar."""
    nombre, *_ = min(stops, key=lambda s: haversine_m(*punto, s[1], s[2]))
    return nombre[:120]


def xy(p, origen):
    return ((p[1] - origen[1]) * 111_320 * math.cos(math.radians(origen[0])),
            (p[0] - origen[0]) * 110_574)


def simplificar(puntos, tolerancia):
    """Douglas-Peucker en metros, como TrazoDesvio en la app."""
    if len(puntos) <= 2:
        return puntos
    plano = [xy(p, puntos[0]) for p in puntos]
    conservar = [False] * len(puntos)
    conservar[0] = conservar[-1] = True
    pendientes = [(0, len(puntos) - 1)]
    while pendientes:
        a, b = pendientes.pop()
        (ax, ay), (bx, by) = plano[a], plano[b]
        mayor, indice = 0.0, a
        for i in range(a + 1, b):
            px, py = plano[i]
            dx, dy = bx - ax, by - ay
            l2 = dx * dx + dy * dy
            t = 0 if l2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
            d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if d > mayor:
                mayor, indice = d, i
        if mayor > tolerancia:
            conservar[indice] = True
            pendientes += [(a, indice), (indice, b)]
    return [p for p, c in zip(puntos, conservar) if c]


def rellenar(puntos, paso=450):
    """Ningún salto mayor que `paso` metros, como pide el backend."""
    resultado = [puntos[0]]
    for a, b in zip(puntos, puntos[1:]):
        partes = max(1, math.ceil(haversine_m(*a, *b) / paso))
        resultado += [(a[0] + (b[0] - a[0]) * i / partes, a[1] + (b[1] - a[1]) * i / partes)
                      for i in range(1, partes + 1)]
    return resultado


def desvio_desde_gpx(shape, gpx=GPX, nombre="la M-34 «A»"):
    """Salida, regreso y calle nueva del GPX, con las reglas del trazador."""
    texto = gpx.read_text(encoding="utf-8")
    puntos = [(float(a), float(b)) for a, b in
              re.findall(r'<wpt lat="([-0-9.]+)" lon="([-0-9.]+)"', texto)]
    medidos = [(p, match_point_to_polyline(*p, shape, threshold_m=REGRESO_M)) for p in puntos]
    ultimo, salida, trazo = None, None, []
    for p, m in medidos:
        if salida is None:
            if m.distance_m <= REGRESO_M:
                ultimo = m
            elif m.distance_m > SALIDA_M and ultimo is not None:
                salida = ultimo
                trazo = [(salida.snapped_lat, salida.snapped_lon), p]
        elif m.distance_m <= REGRESO_M:
            regreso = (m.snapped_lat, m.snapped_lon)
            trazo.append(regreso)
            camino = rellenar(simplificar(trazo, 6))
            return (salida.snapped_lat, salida.snapped_lon), regreso, camino
        else:
            trazo.append(p)
    raise SystemExit(f"el GPX {gpx.name} ya no sale y retoma {nombre}")


def main():
    feed = load_feed(GTFS)
    stops = paraderos()
    linea_b = list(feed.get(LINEA_B).shape)
    incidencias = []
    # Tramo en obra sobre la pasada rumbo al norte de la C-01.
    tramo = tramo_cerrado(linea_b, ENTRADA_TRAMO, HOSPITAL_PRIMAVERA)
    if tramo is None:
        raise SystemExit("la C-01 «B» ya no pasa por el tramo en obra de Nicolás de Piérola")
    inicio, fin = punto_en(linea_b, tramo[0]), punto_en(linea_b, tramo[1])
    incidencias.append({"id": "obras-pierola-c01b", "routeId": LINEA_B, "reason": "works",
                        "lat": round(inicio[0], 6), "lon": round(inicio[1], 6),
                        "place": referencia(inicio, stops),
                        "endLat": round(fin[0], 6), "endLon": round(fin[1], 6)})

    salida, regreso, camino = desvio_desde_gpx(list(feed.get(LINEA_A).shape))
    incidencias.append({"id": "desvio-m34a", "routeId": LINEA_A, "reason": "detour",
                        "lat": round(salida[0], 6), "lon": round(salida[1], 6),
                        "place": referencia(salida, stops), "via": "Avenida Mansiche",
                        "endLat": round(regreso[0], 6), "endLon": round(regreso[1], 6),
                        "path": encode_polyline(camino)})

    # Obra real en la Av. Nicolás de Piérola: un desvío por línea afectada.
    for gpx in sorted((ROOT / "tools" / "prueba-desvio").glob("desvio-pierola-*.gpx")):
        route_id = gpx.stem.removeprefix("desvio-pierola-")
        ruta = feed.get(route_id)
        if ruta is None:
            raise SystemExit(f"{gpx.name}: la ruta {route_id} ya no está en el feed")
        salida, regreso, camino = desvio_desde_gpx(list(ruta.shape), gpx, f"la {ruta.linea}")
        incidencias.append({"id": f"desvio-pierola-{route_id}", "routeId": route_id, "reason": "detour",
                            "lat": round(salida[0], 6), "lon": round(salida[1], 6),
                            "place": referencia(salida, stops),
                            "via": "Vera Enríquez, Chopin, Liszt, Sibelius y Dunker Lavalle",
                            "endLat": round(regreso[0], 6), "endLon": round(regreso[1], 6),
                            "path": encode_polyline(camino)})

    SALIDA.write_text(json.dumps({
        "schemaVersion": 1,
        "descripcion": "Incidencias simuladas de la presentación. Las genera "
                       "tools/generar_incidencias_presentacion.py desde el GTFS.",
        "alerts": incidencias}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    validas = load_simulated(SALIDA, feed)
    if len(validas) != len(incidencias):
        raise SystemExit(f"solo {len(validas)} de {len(incidencias)} incidencias pasan la validación")
    for alerta in validas:
        print(f"{alerta['id']:<16} {alerta['reason']:<8} {alerta['place']}")


if __name__ == "__main__":
    main()
