#!/usr/bin/env python3
"""Genera simulation/incidencias-presentacion.json desde el GTFS.

Incidencias reales o comprobadas en la calle; ya no se reparten motivos
inventados a lo largo de la C-01:

- C-01 «B»: la obra en la Av. Nicolás de Piérola (MPT, noviembre de 2026), desde
  la entrada por la Av. América Norte hasta el Hospital Primavera.
- M-34 «A»: el desvío de la prueba de la app, que sale en Av. Nicolás de
  Piérola, va por calles que usa la CT-29 TA y retoma en Av. Gerónimo de la
  Torre. Su calle nueva sale de tools/prueba-desvio/desvio-M-34-A.gpx. El
  tramo que esquiva queda cerrado para todas las líneas que lo recorren en ese
  sentido: cada una lleva su aviso con la misma calle nueva por la Av. Mansiche.
- Obra real en la Av. Nicolás de Piérola (MPT, noviembre de 2026): cada línea
  que entra desde la Av. España rumbo al norte sigue el desvío oficial por Vera
  Enríquez, Federico Chopin, Franz Liszt, Sibelius y Dunker Lavalle. Los GPX
  tools/prueba-desvio/desvio-pierola-<routeId>.gpx salen de
  backend/tools/trazar_desvio_pierola.py.

Además, «reportes en vivo»: incidencias de demostración, no reales, en otras
zonas de la ciudad (REPORTES_EN_VIVO). Llevan `afterS` para aparecer
escalonadas durante la presentación, como si otros micros las reportaran en
ese momento. Cada una afecta a todas las líneas que recorren su tramo en el
mismo sentido y cada línea sigue su calle nueva: los GPX
tools/prueba-desvio/<zona>-<routeId>.gpx salen de
backend/tools/trazar_desvios_en_vivo.py. Una línea sin GPX propio sigue el
desvío de otra línea del mismo tramo si el backend lo acepta para su
recorrido; si ninguno vale, recibe el aviso sin calle nueva y el script lo
advierte.

Al terminar valida el archivo con `load_simulated`, igual que el backend.

Uso, desde RutaUTP/backend:
    .venv/bin/python tools/generar_incidencias_presentacion.py
"""
from __future__ import annotations

import csv
import html
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from rutautp_backend.desvios import acumulado, tramo_cerrado  # noqa: E402
from rutautp_backend.geo import haversine_m, match_point_to_polyline  # noqa: E402
from rutautp_backend.gtfs import load_feed  # noqa: E402
from rutautp_backend.route_changes import encode_polyline, load_simulated, valid_path  # noqa: E402

GTFS = ROOT / "gtfs"
DESVIOS = ROOT / "tools" / "prueba-desvio"
GPX = DESVIOS / "desvio-M-34-A.gpx"
SALIDA = ROOT / "backend" / "simulation" / "incidencias-presentacion.json"
LINEA_B = "17350695"   # C-01 «B»
LINEA_A = "17434457"   # M-34 «A»
SALIDA_M, REGRESO_M = 60, 35   # mismos umbrales que TrazadorDesvio en la app
# Obra en Nicolás de Piérola: inicio del tramo donde las líneas entran desde el
# sur (cruce con la Av. América Norte) y Hospital Primavera, según OpenStreetMap.
ENTRADA_TRAMO = (-8.10575, -79.03443)
HOSPITAL_PRIMAVERA = (-8.10159, -79.03573)
# Reportes en vivo: (zona, nombre, línea que lo reporta, motivo, punto
# aproximado, metros de tramo, segundos tras el arranque). El tramo cerrado
# sigue a esa línea, en su sentido, desde su punto más cercano al indicado.
REPORTES_EN_VIVO = (
    ("vivo-esperanza", "La Esperanza", "17419574", "detour", (-8.075, -79.045), 600, 20),
    ("vivo-porvenir", "El Porvenir", "17434332", "detour", (-8.085, -79.003), 550, 45),
    ("vivo-larco", "Víctor Larco", "17581709", "detour", (-8.135, -79.040), 650, 75),
    ("vivo-florencia", "Florencia de Mora", "17434307", "closure", (-8.080, -79.020), 400, 110),
    ("vivo-huanchaco", "Huanchaco", "17521112", "detour", (-8.0905, -79.1185), 550, 150),
    ("vivo-alto-trujillo", "Alto Trujillo", "17554576", "works", (-8.060, -78.990), 450, 200),
)
# Una línea recorre un tramo si cada punto del tramo, cada TRAMO_MUESTRA_M, le
# queda a TRAMO_CERCA_M o menos, y si lo pasa en el mismo sentido sin alargarlo
# más de la mitad: otra calle entre los mismos extremos no es el mismo tramo.
TRAMO_MUESTRA_M, TRAMO_CERCA_M = 30, 30


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


def metros_hasta(shape, punto):
    """Distancia recorrida hasta el vértice del recorrido más cercano al punto."""
    cercano = min(range(len(shape)), key=lambda i: haversine_m(*punto, *shape[i]))
    return sum(haversine_m(*a, *b) for a, b in zip(shape[:cercano], shape[1:cercano + 1]))


def tramo_de(shape, desde, hasta):
    """Puntos del recorrido entre `desde` y `hasta` metros, extremos incluidos."""
    interior = [p for p, d in zip(shape, acumulado(shape)) if desde < d < hasta]
    return [punto_en(shape, desde), *interior, punto_en(shape, hasta)]


def tramo_en_vivo(feed, route_id, punto, largo):
    """Recorrido de la línea que reporta y su tramo cerrado, en metros."""
    ruta = feed.get(route_id)
    if ruta is None:
        raise SystemExit(f"la ruta {route_id} de un reporte en vivo ya no está en el feed")
    shape = list(ruta.shape)
    desde = metros_hasta(shape, punto)
    return shape, desde, desde + largo


def lineas_en_tramo(feed, shape, desde, hasta):
    """Líneas que recorren el tramo [desde, hasta] de `shape` en su sentido.

    Incluye la línea del propio recorrido. Orden estable por código de línea.
    """
    inicio, fin = punto_en(shape, desde), punto_en(shape, hasta)
    muestras = rellenar(tramo_de(shape, desde, hasta), TRAMO_MUESTRA_M)
    lineas = []
    for ruta in sorted(feed.routes_with_geometry(), key=lambda r: (r.linea, r.variante, r.route_id)):
        recorrido = list(ruta.shape)
        if not all(match_point_to_polyline(*p, recorrido, threshold_m=TRAMO_CERCA_M).is_on_route
                   for p in muestras):
            continue
        pasada = tramo_cerrado(recorrido, inicio, fin)
        if pasada and pasada[1] - pasada[0] <= 1.5 * (hasta - desde) + 100:
            lineas.append(ruta)
    return lineas


def desvio_compartido(shape, inicio, fin, desvios):
    """El desvío de otra línea del mismo tramo, si también vale para esta.

    Las líneas de una calle cerrada siguen el mismo desvío. Sirve cuando el
    camino toca otra parte del recorrido de esta línea y no se puede medir
    dónde sale y retoma: se exige que esquive todo su tramo cerrado y que el
    backend acepte la calle nueva para su recorrido.
    """
    cerrado = tramo_cerrado(shape, inicio, fin)
    for salida, regreso, camino, via in desvios:
        pasada = tramo_cerrado(shape, salida, regreso)
        if (cerrado and pasada and pasada[0] <= cerrado[0] + SALIDA_M
                and pasada[1] >= cerrado[1] - SALIDA_M
                and pasada[1] - pasada[0] <= cerrado[1] - cerrado[0] + 1000
                and valid_path(camino, salida, regreso, shape)):
            return salida, regreso, camino, via
    return None


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


def puntos_gpx(gpx):
    texto = gpx.read_text(encoding="utf-8")
    return [(float(a), float(b)) for a, b in
            re.findall(r'<wpt lat="([-0-9.]+)" lon="([-0-9.]+)"', texto)]


def via_gpx(gpx):
    """Calles del desvío que anotó el trazador en el GPX, o `None`."""
    anotada = re.search(r"<keywords>(.*?)</keywords>", gpx.read_text(encoding="utf-8"), re.S)
    via = html.unescape(anotada[1]).strip() if anotada else ""
    return via if 3 <= len(via) <= 80 else None


def desvio_desde_puntos(shape, puntos):
    """Salida, regreso y calle nueva de un trazo, con las reglas del trazador.

    `None` si el trazo no sale del recorrido o no vuelve a él.
    """
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
    return None


def desvio_desde_gpx(shape, gpx=GPX, nombre="la M-34 «A»"):
    """Salida, regreso y calle nueva del GPX, con las reglas del trazador."""
    desvio = desvio_desde_puntos(shape, puntos_gpx(gpx))
    if desvio is None:
        raise SystemExit(f"el GPX {gpx.name} ya no sale y retoma {nombre}")
    return desvio


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

    linea_a = list(feed.get(LINEA_A).shape)
    salida, regreso, camino = desvio_desde_gpx(linea_a)
    m34 = {"id": "desvio-m34a", "routeId": LINEA_A, "reason": "detour",
           "lat": round(salida[0], 6), "lon": round(salida[1], 6),
           "place": referencia(salida, stops), "via": "Avenida Mansiche",
           "endLat": round(regreso[0], 6), "endLon": round(regreso[1], 6),
           "path": encode_polyline(camino)}
    incidencias.append(m34)
    # El tramo que esquiva la M-34 «A» queda cerrado para todas las líneas que
    # lo recorren en ese sentido: comparten salida, regreso y calle nueva.
    cerrado = tramo_cerrado(linea_a, salida, regreso)
    if cerrado is None:
        raise SystemExit("la M-34 «A» ya no recorre el tramo de su desvío")
    for ruta in lineas_en_tramo(feed, linea_a, *cerrado):
        if ruta.route_id != LINEA_A:
            incidencias.append({**m34, "id": f"desvio-mansiche-{ruta.route_id}", "routeId": ruta.route_id})

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

    # Reportes en vivo: un aviso por cada línea que recorre el tramo, con la
    # calle nueva que trazó trazar_desvios_en_vivo.py para esa línea.
    for zona, _, route_id, motivo, punto, largo, despues in REPORTES_EN_VIVO:
        referencia_zona, desde, hasta = tramo_en_vivo(feed, route_id, punto, largo)
        inicio, fin = punto_en(referencia_zona, desde), punto_en(referencia_zona, hasta)
        lugar = referencia(inicio, stops)
        lineas = lineas_en_tramo(feed, referencia_zona, desde, hasta)
        propios = {}
        for ruta in lineas:
            gpx = DESVIOS / f"{zona}-{ruta.route_id}.gpx"
            if gpx.exists():
                propios[ruta.route_id] = (*desvio_desde_gpx(list(ruta.shape), gpx, f"la {ruta.linea}"),
                                          via_gpx(gpx))
        for ruta in lineas:
            shape = list(ruta.shape)
            desvio = propios.get(ruta.route_id) or desvio_compartido(shape, inicio, fin, propios.values())
            if desvio:
                salida, regreso, camino, via = desvio
                trazo = encode_polyline(camino)
            else:
                pasada = tramo_cerrado(shape, inicio, fin)
                salida, regreso = punto_en(shape, pasada[0]), punto_en(shape, pasada[1])
                via = trazo = None
                print(f"aviso: falta {zona}-{ruta.route_id}.gpx; la {ruta.linea} queda sin calle "
                      "nueva. Ejecuta backend/tools/trazar_desvios_en_vivo.py", file=sys.stderr)
            aviso = {"id": f"{zona}-{ruta.route_id}", "routeId": ruta.route_id, "reason": motivo,
                     "lat": round(salida[0], 6), "lon": round(salida[1], 6), "place": lugar}
            if via:
                aviso["via"] = via
            aviso.update(endLat=round(regreso[0], 6), endLon=round(regreso[1], 6))
            if trazo:
                aviso["path"] = trazo
            aviso["afterS"] = despues
            incidencias.append(aviso)

    SALIDA.write_text(json.dumps({
        "schemaVersion": 1,
        "descripcion": "Incidencias simuladas de la presentación. Las genera "
                       "tools/generar_incidencias_presentacion.py desde el GTFS.",
        "alerts": incidencias}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    validas = load_simulated(SALIDA, feed)
    if len(validas) != len(incidencias):
        raise SystemExit(f"solo {len(validas)} de {len(incidencias)} incidencias pasan la validación")
    for alerta in validas:
        print(f"{alerta['id']:<28} {alerta['reason']:<8} {alerta.get('afterS', 0):>4}s {alerta['place']}")


if __name__ == "__main__":
    main()
