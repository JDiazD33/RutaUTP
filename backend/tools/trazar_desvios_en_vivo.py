#!/usr/bin/env python3
"""Traza la calle nueva de cada línea afectada por los reportes en vivo.

Los reportes en vivo de la presentación (REPORTES_EN_VIVO en
generar_incidencias_presentacion.py) son incidencias de demostración, no
reales. Para cada uno:

1. El tramo cerrado sigue a la línea que lo reporta, en su sentido, desde su
   punto más cercano a la zona y durante los metros indicados.
2. Afecta a todas las líneas del GTFS que recorren ese tramo en el mismo
   sentido (`lineas_en_tramo`, la misma regla que usa el generador).
3. Para cada línea pide a OSRM (red de OpenStreetMap, respeta los sentidos) un
   camino desde antes del tramo hasta después, por puntos de paso a un lado
   del tramo. Prueba varios y se queda con el más corto que no recorra el tramo
   cerrado, no vuelva sobre sus pasos, salga de la línea antes del cierre, la
   retome después y cumpla las reglas del backend para una calle nueva.
4. Guarda tools/prueba-desvio/<zona>-<routeId>.gpx con el camino y las calles
   por las que va; generar_incidencias_presentacion.py lo lee.

Se ejecuta a mano cuando cambien el feed o los reportes en vivo; no forma parte
del backend. Después hay que regenerar las incidencias. Uso, desde
RutaUTP/backend:

    .venv/bin/python tools/trazar_desvios_en_vivo.py
    .venv/bin/python tools/generar_incidencias_presentacion.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request
from xml.sax.saxutils import escape

HERRAMIENTAS = Path(__file__).resolve().parent
sys.path.insert(0, str(HERRAMIENTAS.parent))
sys.path.insert(0, str(HERRAMIENTAS))

import generar_incidencias_presentacion as gen  # noqa: E402
from rutautp_backend.desvios import acumulado, tramo_cerrado  # noqa: E402
from rutautp_backend.geo import haversine_m, match_point_to_polyline  # noqa: E402
from rutautp_backend.gtfs import load_feed  # noqa: E402
from rutautp_backend.route_changes import (  # noqa: E402
    MAX_PATH_CHARS, MAX_PATH_POINTS, MAX_STRETCH_M, encode_polyline, valid_path,
)

OSRM = "https://router.project-osrm.org/route/v1/driving/"
# Nombre genérico: el servidor público pide identificar el cliente.
AGENTE = "trazador-desvios/1.0"
# El servidor público admite una consulta por segundo.
PAUSA_S = 1.1
# El camino empieza y termina sobre la línea, como en trazar_desvio_pierola.py.
ANTES_M, DESPUES_M = 250, 150
# Puntos de paso a cada lado del tramo, de más cerca a más lejos, frente a sus
# extremos o algo más allá de ellos.
DESPLAZAMIENTOS_M = (120, 180, 260, 360)
MARGENES_M = (0, 60, 120)
# Cruzar el tramo cerrado o tocar sus extremos vale; recorrerlo, no.
EXTREMO_M, PEGADO_M, PISA_MAX_M = 60, 12, 30
# Un giro en U o una calle sin salida repiten parte del camino.
REPITE_MAX_M = 30
LARGO_MAXIMO_M = 3500

_ultima_consulta = 0.0


def osrm(puntos):
    """Camino y pasos de OSRM por esos puntos, o `None` si no hay camino."""
    global _ultima_consulta
    coordenadas = ";".join(f"{lon:.6f},{lat:.6f}" for lat, lon in puntos)
    url = f"{OSRM}{coordenadas}?overview=full&geometries=geojson&steps=true&continue_straight=true"
    for intento in range(4):
        espera = PAUSA_S - (time.monotonic() - _ultima_consulta)
        if espera > 0:
            time.sleep(espera)
        _ultima_consulta = time.monotonic()
        try:
            pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE})
            respuesta = json.load(urllib.request.urlopen(pedido, timeout=60))
            break
        except urllib.error.HTTPError as error:
            if error.code == 400:  # NoRoute / NoSegment: el punto de paso no sirve
                return None
            time.sleep(5 * (intento + 1))
        except (urllib.error.URLError, TimeoutError, ValueError):
            time.sleep(5 * (intento + 1))
    else:
        raise SystemExit("OSRM no respondió; vuelve a intentarlo más tarde")
    if respuesta.get("code") != "Ok" or not respuesta.get("routes"):
        return None
    ruta = respuesta["routes"][0]
    camino = [(lat, lon) for lon, lat in ruta["geometry"]["coordinates"]]
    pasos = [(paso.get("name", ""), [(lat, lon) for lon, lat in paso["geometry"]["coordinates"]])
             for tramo in ruta["legs"] for paso in tramo["steps"]]
    return camino, pasos


def a_segmento(p, a, b):
    kx, ky = 111_320 * math.cos(math.radians(p[0])), 110_574
    ax, ay, bx, by = (a[1]-p[1])*kx, (a[0]-p[0])*ky, (b[1]-p[1])*kx, (b[0]-p[0])*ky
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, -(ax*dx + ay*dy) / (dx*dx + dy*dy)))
    return math.hypot(ax + t*dx, ay + t*dy)


def a_linea(p, linea):
    return min(a_segmento(p, linea[i], linea[i + 1]) for i in range(len(linea) - 1))


def lateral(shape, metros, desplazamiento):
    """Punto a `desplazamiento` metros a la izquierda (+) o derecha (-) del recorrido."""
    p = gen.punto_en(shape, metros)
    a, b = gen.punto_en(shape, max(0, metros - 40)), gen.punto_en(shape, metros + 40)
    kx, ky = 111_320 * math.cos(math.radians(p[0])), 110_574
    dx, dy = (b[1] - a[1]) * kx, (b[0] - a[0]) * ky
    largo = math.hypot(dx, dy) or 1
    return (p[0] + desplazamiento * dx / largo / ky, p[1] - desplazamiento * dy / largo / kx)


def puntos_de_paso(referencia, desde, hasta):
    """Puntos de paso a cada lado del tramo, de más cerca a más lejos.

    Uno frente al centro, o dos frente a los extremos y algo más allá: obligan
    a dejar la calle antes del cierre y a volver a ella después.
    """
    candidatos = []
    for desplazamiento in DESPLAZAMIENTOS_M:
        for lado in (1, -1):
            d = desplazamiento * lado
            candidatos.append([lateral(referencia, (desde + hasta) / 2, d)])
            candidatos += [[lateral(referencia, desde - margen, d), lateral(referencia, hasta + margen, d)]
                           for margen in MARGENES_M]
    return candidatos


def repite(denso):
    """Metros del camino que vuelven a pasar por donde ya pasó."""
    recorrido = acumulado(denso)
    repetidos = 0.0
    for i in range(1, len(denso)):
        if any(recorrido[i] - recorrido[j] > 60 and haversine_m(*denso[i], *denso[j]) < 8
               for j in range(i)):
            repetidos += recorrido[i] - recorrido[i - 1]
    return repetidos


def calles(pasos, shape):
    """Calles del desvío, en orden: las de los pasos que se apartan de la línea."""
    nombres = []
    for nombre, geometria in pasos:
        nombre = nombre.strip()
        if not nombre or nombre in nombres or len(geometria) < 2:
            continue
        denso = gen.rellenar(geometria, 20)
        fuera = sum(1 for p in denso
                    if not match_point_to_polyline(*p, shape, threshold_m=gen.REGRESO_M).is_on_route)
        if fuera * 20 >= 60:
            nombres.append(nombre)
    while nombres:
        texto = nombres[0] if len(nombres) == 1 else ", ".join(nombres[:-1]) + " y " + nombres[-1]
        if len(texto) <= 80:
            return texto
        nombres.pop()
    return None


def evaluar(shape, cerrado, tramo, camino, pasos):
    """El desvío que da el camino de OSRM para una línea, o `None` si no vale."""
    if len(camino) < 3:
        return None
    denso = gen.rellenar(camino, 10)
    junto = [haversine_m(*p, *tramo[0]) > EXTREMO_M and haversine_m(*p, *tramo[-1]) > EXTREMO_M
             and a_linea(p, tramo) <= PEGADO_M for p in denso]
    pisa = sum(haversine_m(*denso[i], *denso[i + 1])
               for i in range(len(denso) - 1) if junto[i] and junto[i + 1])
    if pisa > PISA_MAX_M or repite(denso) > REPITE_MAX_M:
        return None
    # Salida y regreso como los mide el generador (y el trazador de la app).
    extraido = gen.desvio_desde_puntos(shape, camino)
    if extraido is None:
        return None
    salida, regreso, trazo = extraido
    pasada = tramo_cerrado(shape, salida, regreso)
    inicio, fin = cerrado
    if (pasada is None or not inicio - 500 <= pasada[0] <= inicio + EXTREMO_M
            or not fin - EXTREMO_M <= pasada[1] <= fin + 500):
        return None
    largo = acumulado(trazo)[-1]
    if (largo > LARGO_MAXIMO_M or len(trazo) > MAX_PATH_POINTS
            or len(encode_polyline(trazo)) > MAX_PATH_CHARS
            or not 50 <= haversine_m(*salida, *regreso) <= MAX_STRETCH_M
            or not valid_path(trazo, salida, regreso, shape)):
        return None
    return {"camino": camino, "largo": largo, "via": calles(pasos, shape),
            "salida": salida, "regreso": regreso, "trazo": trazo}


def trazar_zona(feed, reporte):
    """Desvío de cada línea que recorre el tramo del reporte."""
    zona, nombre, route_id, _, punto, largo, _ = reporte
    referencia, desde, hasta = gen.tramo_en_vivo(feed, route_id, punto, largo)
    tramo = gen.tramo_de(referencia, desde, hasta)
    # La línea que reporta va primero: sus pruebas ordenan las de las demás.
    lineas = sorted(gen.lineas_en_tramo(feed, referencia, desde, hasta),
                    key=lambda r: r.route_id != route_id)
    candidatos = puntos_de_paso(referencia, desde, hasta)
    preferidos, resultados, faltan = [], {}, []
    for ruta in lineas:
        shape = list(ruta.shape)
        cerrado = tramo_cerrado(shape, tramo[0], tramo[-1])
        antes = gen.punto_en(shape, max(0.0, cerrado[0] - ANTES_M))
        despues = gen.punto_en(shape, cerrado[1] + DESPUES_M)
        orden = preferidos + [i for i in range(len(candidatos)) if i not in preferidos]
        validos = []
        for i in orden:
            respuesta = osrm([antes, *candidatos[i], despues])
            desvio = respuesta and evaluar(shape, cerrado, tramo, *respuesta)
            if desvio:
                validos.append((desvio["largo"], i, desvio))
                # La primera línea prueba todos para ordenar los candidatos.
                if preferidos:
                    break
        if not validos:
            faltan.append(ruta)
            continue
        validos.sort(key=lambda v: v[0])
        if not preferidos:
            preferidos = [i for _, i, _ in validos]
        resultados[ruta.route_id] = (ruta, validos[0][2])
        print(f"{zona}: {ruta.linea} {ruta.route_id} {validos[0][2]['largo']:.0f} m "
              f"por {validos[0][2]['via'] or '(sin nombre)'}", file=sys.stderr)
    # Sin camino propio, la línea sigue el de otra del tramo si le vale: el
    # generador hace la misma comprobación.
    ajenos = [(d["salida"], d["regreso"], d["trazo"], d["via"]) for _, d in resultados.values()]
    sin_desvio = []
    for ruta in faltan:
        if gen.desvio_compartido(list(ruta.shape), tramo[0], tramo[-1], ajenos):
            print(f"{zona}: {ruta.linea} {ruta.route_id} sigue el desvío de otra línea del tramo",
                  file=sys.stderr)
        else:
            sin_desvio.append(f"{ruta.linea} {ruta.route_id}")
            print(f"{zona}: {ruta.linea} {ruta.route_id} sin desvío válido", file=sys.stderr)
    return zona, nombre, resultados, sin_desvio


def guardar(zona, nombre, ruta, desvio):
    via = desvio["via"]
    descripcion = f"{ruta.linea}: desvío de demostración en {nombre}, no real." + (f" Por {via}." if via else "")
    archivo = gen.DESVIOS / f"{zona}-{ruta.route_id}.gpx"
    archivo.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="RutaUTP trazar_desvios_en_vivo.py">\n'
        f"  <metadata><desc>{escape(descripcion)}</desc>"
        + (f"<keywords>{escape(via)}</keywords>" if via else "") + "</metadata>\n"
        + "".join(f'  <wpt lat="{lat:.6f}" lon="{lon:.6f}"></wpt>\n' for lat, lon in desvio["camino"])
        + "</gpx>\n", encoding="utf-8")
    return archivo


def main():
    feed = load_feed(gen.GTFS)
    gen.DESVIOS.mkdir(parents=True, exist_ok=True)
    resumen, faltan = [], []
    for reporte in gen.REPORTES_EN_VIVO:
        zona, nombre, resultados, sin_desvio = trazar_zona(feed, reporte)
        faltan += [f"{zona}: {linea}" for linea in sin_desvio]
        if not resultados:
            continue
        # Solo se sustituyen los GPX de esta zona, que genera este script.
        for anterior in gen.DESVIOS.glob(f"{zona}-*.gpx"):
            anterior.unlink()
        for ruta, desvio in resultados.values():
            archivo = guardar(zona, nombre, ruta, desvio)
            resumen.append({"zona": zona, "linea": ruta.linea, "routeId": ruta.route_id,
                            "gpx": archivo.name, "metrosDesvio": round(desvio["largo"]),
                            "via": desvio["via"]})
    print(json.dumps(resumen, ensure_ascii=False, indent=1))
    if faltan:
        raise SystemExit("sin desvío válido: " + "; ".join(faltan))


if __name__ == "__main__":
    main()
