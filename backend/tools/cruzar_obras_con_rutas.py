#!/usr/bin/env python3
"""Qué líneas del GTFS recorren una calle en obra.

Uso, desde la raíz del repositorio:

    PYTHONPATH=backend backend/.venv/bin/python backend/tools/cruzar_obras_con_rutas.py "San Martín" "Liverpool"

Varias calles comparten nombre en distintos distritos. Para acotar a una zona,
pasa primero `--bbox sur,oeste,norte,este`; por ejemplo, el centro histórico
dentro de la Av. España: `--bbox -8.1190,-79.0380,-8.1030,-79.0190`.

Consulta la geometría de cada calle en OpenStreetMap (Overpass) dentro de
Trujillo y la compara con los recorridos del feed. Una línea cuenta como
afectada solo si va pegada a la calle (a 15 m o menos) durante un tramo
seguido de 80 m o más: cruzarla o tocar un extremo no obliga a desviarse.
Solo lee: no modifica el feed ni las incidencias de la simulación.
"""
import json
import math
import sys
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

from rutautp_backend.gtfs import load_feed

ROOT = Path(__file__).resolve().parents[2]
BBOX = "-8.20,-79.12,-8.03,-78.95"  # Trujillo metropolitano
TOLERANCIA_M, TRAMO_MINIMO_M = 15, 80


def sin_tildes(texto):
    return "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn").lower()


def patron(nombre):
    # Overpass no ignora tildes: se aceptan ambas formas de cada vocal.
    vocales = {"a": "[aá]", "e": "[eé]", "i": "[ií]", "o": "[oó]", "u": "[uúü]"}
    return "".join(vocales.get(c, c) for c in sin_tildes(nombre))


def metros(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((a[0] - b[0]) * 110_574, (a[1] - b[1]) * 111_320 * math.cos(lat))


def a_segmento(p, a, b):
    kx, ky = 111_320 * math.cos(math.radians(p[0])), 110_574
    ax, ay, bx, by = (a[1]-p[1])*kx, (a[0]-p[0])*ky, (b[1]-p[1])*kx, (b[0]-p[0])*ky
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, -(ax*dx + ay*dy) / (dx*dx + dy*dy)))
    return math.hypot(ax + t*dx, ay + t*dy)


def geometria(calles):
    consulta = "[out:json][timeout:60];(" + "".join(
        f'way["highway"]["name"~"{patron(c)}",i]({BBOX});' for c in calles) + ");out geom;"
    pedido = urllib.request.Request("https://overpass-api.de/api/interpreter",
                                    data=urllib.parse.urlencode({"data": consulta}).encode(),
                                    headers={"User-Agent": "RutaUTP-simulacion/1.0"})
    por_calle = {c: [] for c in calles}
    for way in json.load(urllib.request.urlopen(pedido, timeout=90))["elements"]:
        nombre = sin_tildes(way.get("tags", {}).get("name", ""))
        for calle in calles:
            if sin_tildes(calle) in nombre:
                por_calle[calle].append([(n["lat"], n["lon"]) for n in way["geometry"]])
    return por_calle


def tramos_pegados(shape, segmentos):
    """Tramos seguidos del recorrido que van sobre la calle: (metros, desde, hasta)."""
    cerca = [min(a_segmento(p, a, b) for a, b in segmentos) <= TOLERANCIA_M for p in shape]
    tramos, inicio = [], None
    for i in range(len(shape)):
        if cerca[i] and inicio is None:
            inicio = i
        if inicio is not None and (not cerca[i] or i == len(shape) - 1):
            fin = i if cerca[i] else i - 1
            largo = sum(metros(shape[j], shape[j + 1]) for j in range(inicio, fin))
            tramos.append((round(largo), shape[inicio], shape[fin]))
            inicio = None
    return [t for t in tramos if t[0] >= TRAMO_MINIMO_M]


def main(calles):
    feed = load_feed(ROOT / "gtfs")
    ids = {linea.split(",")[0] for linea in (ROOT / "gtfs/routes.txt").read_text(encoding="utf-8-sig").splitlines()[1:]}
    resultado = {}
    for calle, ways in geometria(calles).items():
        segmentos = [(w[i], w[i + 1]) for w in ways for i in range(len(w) - 1)]
        afectadas = []
        for rid in sorted(ids):
            ruta = feed.get(rid)
            if ruta is None or not segmentos:
                continue
            for largo, desde, hasta in tramos_pegados(ruta.shape, segmentos):
                afectadas.append({"routeId": rid, "linea": ruta.linea, "metros": largo,
                                  "desde": desde, "hasta": hasta})
        resultado[calle] = {"tramosOSM": len(ways), "lineas": afectadas}
    print(json.dumps(resultado, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    argumentos = sys.argv[1:]
    if argumentos[:1] == ["--bbox"] and len(argumentos) >= 2:
        BBOX, argumentos = argumentos[1], argumentos[2:]
    if not argumentos:
        raise SystemExit(__doc__)
    main(argumentos)
