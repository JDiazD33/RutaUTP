#!/usr/bin/env python3
"""Traza el desvío oficial por la obra en la Av. Nicolás de Piérola.

Fuentes, consultadas el 16/11/2026:

- Aviso de la Municipalidad Provincial de Trujillo (Facebook munitruGMCRR,
  post 122322985742141403). Dice que para ir de la Av. España a la Av. Nicolás
  de Piérola se sigue el desvío por las avenidas Vera Enríquez y Federico
  Chopin, y luego por Franz Liszt, Sibelius y Dunker Lavalle.
- «Trujillo es Noticia» informa del cierre simultáneo por 60 días de tramos de
  Nicolás de Piérola, Valcárcel, Vera Enríquez y América Norte.

Para cada línea del GTFS que entra desde la Av. España a la Nicolás de Piérola
rumbo al norte, pide a OSRM (red de OpenStreetMap, respeta los sentidos) un
camino por esas calles, en ese orden. Comprueba que no pise el tramo cerrado y
guarda un GPX en tools/prueba-desvio/, que lee generar_incidencias_presentacion.py.
Se ejecuta a mano cuando cambie el feed o el aviso; no forma parte del backend.

Uso, desde la raíz del repositorio:

    PYTHONPATH=backend backend/.venv/bin/python backend/tools/trazar_desvio_pierola.py
"""
import json
import math
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from rutautp_backend.gtfs import load_feed

ROOT = Path(__file__).resolve().parents[2]
DESTINO = ROOT / "tools" / "prueba-desvio"
BBOX = "-8.112,-79.042,-8.092,-79.026"
# Cruces que delimitan el tramo cerrado, según OSM: entrada de las líneas desde
# el sur (cruce con la Av. América Norte) y regreso por el Pasaje E. Dunker La Valle.
INICIO_CIERRE = (-8.10575, -79.03443)
FIN_CIERRE = (-8.09620, -79.03830)
# Calles del aviso, en orden. Vera Enríquez es de dos calzadas de un sentido:
# se toma la que va de la Av. España hacia la Nicolás de Piérola.
CALLES = (("Vera Enr[ií]quez", "noroeste"), ("Chop[ií]n", None), ("Liszt", None),
          ("Sibelius", None), ("Dunker", None))
AFECTADAS_DESDE_ESPANA = 1000  # metros mínimos sobre el tramo cerrado rumbo al norte


def metros(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((a[0] - b[0]) * 110_574, (a[1] - b[1]) * 111_320 * math.cos(lat))


def rumbo(a, b):
    y = (b[1] - a[1]) * math.cos(math.radians(a[0]))
    return math.degrees(math.atan2(y, b[0] - a[0])) % 360


SERVIDORES = ("https://overpass-api.de/api/interpreter",
              "https://overpass.kumi.systems/api/interpreter")


def overpass():
    """Una sola consulta para todas las calles; reintenta en un espejo si falla."""
    consulta = "[out:json][timeout:60];(" + "".join(
        f'way["highway"]["name"~"{patron}",i]({BBOX});' for patron, _ in CALLES) + ");out geom;"
    for intento, servidor in enumerate(SERVIDORES * 2):
        try:
            pedido = urllib.request.Request(servidor, data=urllib.parse.urlencode({"data": consulta}).encode(),
                                            headers={"User-Agent": "RutaUTP-simulacion/1.0"})
            return json.load(urllib.request.urlopen(pedido, timeout=90))["elements"]
        except (urllib.error.URLError, TimeoutError):
            time.sleep(5 * (intento + 1))
    raise SystemExit("Overpass no respondió; vuelve a intentarlo más tarde")


def punto_de_paso(elementos, patron, sentido):
    """Nodo central de la vía más larga; con `sentido`, solo vías con ese rumbo."""
    vias = [[(n["lat"], n["lon"]) for n in w["geometry"]] for w in elementos
            if re.search(patron, w.get("tags", {}).get("name", ""), re.I)]
    if sentido == "noroeste":  # de la Av. España (sureste) hacia la Nicolás de Piérola
        vias = [v for v in vias if 280 <= rumbo(v[0], v[-1]) <= 340]
    if not vias:
        raise SystemExit(f"OSM no devolvió la calle {patron}")
    via = max(vias, key=lambda v: sum(metros(v[i], v[i + 1]) for i in range(len(v) - 1)))
    return via[len(via) // 2]


def a_segmento(p, a, b):
    kx, ky = 111_320 * math.cos(math.radians(p[0])), 110_574
    ax, ay, bx, by = (a[1]-p[1])*kx, (a[0]-p[0])*ky, (b[1]-p[1])*kx, (b[0]-p[0])*ky
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, -(ax*dx + ay*dy) / (dx*dx + dy*dy)))
    return math.hypot(ax + t*dx, ay + t*dy)


def indice_cercano(shape, punto, desde=0):
    """Fin del segmento más cercano al punto y su distancia (los vértices son escasos)."""
    i = min(range(desde, len(shape) - 1), key=lambda j: a_segmento(punto, shape[j], shape[j + 1]))
    return i + 1, a_segmento(punto, shape[i], shape[i + 1])


def avanzar(shape, indice, distancia, paso):
    recorrido = 0
    while 0 < indice < len(shape) - 1 and recorrido < distancia:
        recorrido += metros(shape[indice], shape[indice + paso])
        indice += paso
    return indice


def osrm(puntos):
    coordenadas = ";".join(f"{lon:.6f},{lat:.6f}" for lat, lon in puntos)
    url = (f"https://router.project-osrm.org/route/v1/driving/{coordenadas}"
           "?overview=full&geometries=geojson&continue_straight=true")
    pedido = urllib.request.Request(url, headers={"User-Agent": "RutaUTP-simulacion/1.0"})
    ruta = json.load(urllib.request.urlopen(pedido, timeout=60))["routes"][0]
    return [(lat, lon) for lon, lat in ruta["geometry"]["coordinates"]]


def distancia_a(punto, polilinea):
    return min(metros(punto, p) for p in polilinea)


def main():
    feed = load_feed(ROOT / "gtfs")
    elementos = overpass()
    pasos = [punto_de_paso(elementos, patron, sentido) for patron, sentido in CALLES]
    ids = sorted({l.split(",")[0] for l in (ROOT / "gtfs/routes.txt").read_text(encoding="utf-8-sig").splitlines()[1:]})
    generados = []
    for rid in ids:
        ruta = feed.get(rid)
        if ruta is None:
            continue
        shape = list(ruta.shape)
        i0, d0 = indice_cercano(shape, INICIO_CIERRE)
        if d0 > 25:
            continue
        i0 -= 1  # comienzo del segmento que pasa por la entrada
        i1, d1 = indice_cercano(shape, FIN_CIERRE, i0)
        cerrado = shape[i0:i1 + 1]
        largo = sum(metros(cerrado[i], cerrado[i + 1]) for i in range(len(cerrado) - 1))
        # Solo rumbo al norte: el regreso va después de la entrada y cubre el tramo.
        if d1 > 25 or largo < AFECTADAS_DESDE_ESPANA or largo > 2500:
            print(f"{ruta.linea} {rid}: no entra al tramo rumbo al norte ({d1:.0f} m, {largo:.0f} m)")
            continue
        antes, despues = avanzar(shape, i0, 250, -1), avanzar(shape, i1, 150, 1)
        camino = osrm([shape[antes], *pasos, shape[despues]])
        # Cruzar la avenida cerrada es válido; recorrerla no. Se miden los metros
        # seguidos del desvío que van pegados al tramo cerrado, lejos de sus extremos.
        cerca = [metros(p, shape[i0]) > 60 and metros(p, shape[i1]) > 60
                 and min(a_segmento(p, cerrado[j], cerrado[j + 1]) for j in range(len(cerrado) - 1)) <= 12
                 for p in camino]
        pisa = sum(metros(camino[i], camino[i + 1]) for i in range(len(camino) - 1) if cerca[i] and cerca[i + 1])
        largo_desvio = sum(metros(camino[i], camino[i + 1]) for i in range(len(camino) - 1))
        if pisa > 30 or largo_desvio > 4000:
            print(f"{ruta.linea} {rid}: descartado ({pisa:.0f} m sobre el cierre, {largo_desvio:.0f} m)")
            continue
        DESTINO.mkdir(parents=True, exist_ok=True)
        archivo = DESTINO / f"desvio-pierola-{rid}.gpx"
        archivo.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<gpx version="1.1" creator="RutaUTP trazar_desvio_pierola.py">\n'
            f'  <metadata><desc>{ruta.linea}: desvío oficial MPT por obra en Av. Nicolás de Piérola. '
            'Av. España, Vera Enríquez, Federico Chopin, Franz Liszt, Sibelius y Dunker Lavalle.</desc></metadata>\n'
            + "".join(f'  <wpt lat="{lat:.6f}" lon="{lon:.6f}"></wpt>\n' for lat, lon in camino)
            + "</gpx>\n", encoding="utf-8")
        generados.append({"routeId": rid, "linea": ruta.linea, "gpx": archivo.name,
                          "metrosCerrados": round(largo), "metrosDesvio": round(largo_desvio)})
    print(json.dumps(generados, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
