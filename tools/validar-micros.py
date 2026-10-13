"""Validacion de recursos durante la compilacion; no confirma hechos del transporte."""
from pathlib import Path
import csv
import datetime as dt
import hashlib
import json
import re
import struct
import sys
from urllib.parse import urlparse


def exigir(condicion, mensaje):
    if not condicion:
        raise ValueError(mensaje)


def texto(valor, limite):
    return isinstance(valor, str) and bool(valor.strip()) and len(valor) <= limite


def entero(valor):
    return type(valor) is int


def jpeg_info(data):
    exigir(data[:2] == b'\xff\xd8', 'La foto debe ser JPEG')
    pos = 2
    dimensiones = None
    while pos < len(data):
        exigir(data[pos] == 255, 'JPEG invalido')
        while pos < len(data) and data[pos] == 255:
            pos += 1
        exigir(pos < len(data), 'JPEG incompleto')
        marker = data[pos]
        pos += 1
        if marker in (0xDA, 0xD9):
            break
        exigir(pos + 2 <= len(data), 'JPEG incompleto')
        length = struct.unpack('>H', data[pos:pos + 2])[0]
        exigir(length >= 2 and pos + length <= len(data), 'JPEG incompleto')
        exigir(marker not in (0xE1, 0xED), 'Retira EXIF/IPTC con preparar-foto-micro.swift')
        if marker in (0xC0, 0xC2):
            exigir(length >= 8, 'JPEG sin dimensiones validas')
            _, height, width, _ = struct.unpack('>BHHB', data[pos + 2:pos + 8])
            dimensiones = (width, height)
        pos += length
    exigir(dimensiones is not None, 'JPEG sin dimensiones')
    exigir(all(200 <= n <= 960 for n in dimensiones), 'La foto debe medir entre 200 y 960 px por lado')
    return dimensiones


def tablas(carpeta):
    def leer(nombre):
        with (carpeta / (nombre + '.txt')).open(encoding='utf-8-sig', newline='') as archivo:
            return list(csv.DictReader(archivo))
    agencias = {r.get('agency_id', ''): r.get('agency_name', '') for r in leer('agency')}
    trips = sorted(leer('trips'), key=lambda r: r['trip_id'])
    trip_ruta = {}
    for trip in trips:
        trip_ruta.setdefault(trip['route_id'], trip['trip_id'])
    paraderos = {r['stop_id']: r for r in leer('stops')}
    tiempos = {}
    for fila in leer('stop_times'):
        tiempos.setdefault(fila['trip_id'], []).append(fila)
    resultado = {}
    for ruta in leer('routes'):
        short = ruta.get('route_short_name', '')
        partes = short.split('"')
        linea = partes[0].strip() or short
        variante = partes[1].strip() if len(partes) > 1 else ''
        nombre = ruta.get('route_long_name', '')
        prefijo = short + ' : '
        if nombre.startswith(prefijo):
            nombre = nombre[len(prefijo):]
        elif ' : ' in nombre:
            nombre = nombre.split(' : ', 1)[1]
        nombre = nombre.strip()
        extremos = [p.strip() for p in nombre.split('→')]
        if len(extremos) == 2 and extremos[0] and extremos[0] == extremos[1]:
            nombre = extremos[0] + ' (ramal circular)'
        trip = trip_ruta.get(ruta['route_id'], ruta['route_id'])
        stops = []
        for fila in sorted(tiempos.get(trip, []), key=lambda r: int(r['stop_sequence'])):
            stop = paraderos[fila['stop_id']]
            stops.append({'id': stop['stop_id'], 'lat': float(stop['stop_lat']), 'lon': float(stop['stop_lon'])})
        resultado[ruta['route_id']] = {'routeID': ruta['route_id'], 'linea': linea, 'variante': variante,
            'empresa': agencias.get(ruta.get('agency_id', ''), 'Transporte Trujillo'), 'recorrido': nombre,
            'paraderos': stops}
    return resultado


def validar(root):
    folder = root / 'micros'
    exigir(not folder.is_symlink(), 'La carpeta micros no debe ser un enlace')
    catalogo = folder / 'catalogo.json'
    exigir(catalogo.is_file() and not catalogo.is_symlink(), 'Falta micros/catalogo.json')
    exigir(catalogo.stat().st_size <= 256 * 1024, 'Catalogo mayor a 256 KB')
    data = json.loads(catalogo.read_text())
    exigir(entero(data.get('version')) and data['version'] == 1, 'Version de catalogo desconocida')
    identidades = data.get('identidades')
    vinculos = data.get('vinculos')
    fotos_referencia = data.get('referenciasFotograficas', [])
    exigir(isinstance(identidades, list) and len(identidades) <= 200, 'Identidades invalidas')
    exigir(isinstance(vinculos, list) and len(vinculos) <= 500, 'Vinculos invalidos')
    exigir(isinstance(fotos_referencia, list) and len(fotos_referencia) <= 500, 'Referencias fotograficas invalidas')
    archivos = {}
    total = 0
    for archivo in folder.rglob('*'):
        exigir(not archivo.is_symlink(), 'No se admiten enlaces dentro de micros')
        if archivo.is_dir():
            continue
        if archivo == catalogo:
            continue
        exigir(archivo.parent == folder / 'fotos' and re.fullmatch(r'[a-z0-9][a-z0-9-]{0,79}\.jpg', archivo.name),
               'Solo se admiten catalogo.json y fotos JPEG dentro de micros')
        size = archivo.stat().st_size
        exigir(0 < size <= 128 * 1024, 'Foto mayor a 128 KB: ' + archivo.name)
        total += size
        photo = archivo.read_bytes()
        width, height = jpeg_info(photo)
        archivos[archivo.name] = (width, height, hashlib.sha256(photo).hexdigest())
    exigir(len(archivos) <= 48 and total <= 6 * 1024 * 1024, 'Presupuesto de fotos excedido (48 fotos / 6 MB)')
    ids = set()
    por_id = {}
    usados = set()
    nombres_color = {'blanco', 'negro', 'rojo', 'azul', 'verde', 'amarillo', 'naranja', 'gris', 'marron', 'morado'}
    for identidad in identidades:
        exigir(texto(identidad.get('id'), 80) and identidad['id'] not in ids, 'ID de identidad invalido o duplicado')
        ids.add(identidad['id'])
        por_id[identidad['id']] = identidad
        exigir(texto(identidad.get('letra'), 20) and texto(identidad.get('empresa'), 160), 'Falta letra o empresa')
        colores = identidad.get('colores')
        exigir(isinstance(colores, list) and 1 <= len(colores) <= 5, 'Colores invalidos')
        for color in colores:
            exigir(color.get('nombre') in nombres_color and re.fullmatch(r'[0-9A-Fa-f]{6}', color.get('hex', '')), 'Color invalido')
        foto = identidad.get('foto', {})
        exigir(foto.get('archivo') in archivos, 'Falta foto de identidad')
        exigir(entero(foto.get('ancho')) and entero(foto.get('alto')), 'Dimensiones de foto invalidas')
        exigir((foto['ancho'], foto['alto'], foto.get('sha256')) == archivos[foto['archivo']], 'Foto y metadatos no coinciden')
        exigir(texto(foto.get('credito'), 200) and texto(foto.get('autorizacion'), 500), 'Falta credito o referencia de autorizacion')
        usados.add(foto['archivo'])
    referencias = {}
    if vinculos or fotos_referencia:
        referencias = tablas(root / 'gtfs')
        if (root / 'gtfs-utp/routes.txt').is_file():
            for key, value in tablas(root / 'gtfs-utp').items():
                exigir(key not in referencias, 'route_id ambiguo entre feeds')
                referencias[key] = value
    rutas = set()
    tramos = set()
    identidades_usadas = set()
    for vinculo in vinculos:
        exigir(vinculo.get('identidadID') in ids, 'Vinculo con identidad desconocida')
        identidades_usadas.add(vinculo['identidadID'])
        referencia = vinculo.get('referenciaGTFS', {})
        route_id = referencia.get('routeID')
        exigir(route_id in referencias, 'Ruta desconocida')
        rutas.add(route_id)
        exigir(referencia == referencias[route_id], 'La referencia ya no coincide con el GTFS: ' + route_id)
        letra = referencia['variante'].strip()
        if not letra and referencia['linea'].startswith('CT-'):
            partes = referencia['linea'].split(maxsplit=1)
            letra = partes[1] if len(partes) == 2 else ''
        letra = ' '.join(letra.replace('<3', ' ♥').split())
        identidad = por_id[vinculo['identidadID']]
        exigir(identidad['letra'] == letra and identidad['empresa'] == referencia['empresa'],
               'Letra o empresa contradictoria: revalida el catalogo GTFS antes de vincular la foto')
        desde = vinculo.get('desdeIndice')
        hasta = vinculo.get('hastaIndice')
        exigir(entero(desde) and entero(hasta) and 0 <= desde < hasta < len(referencia['paraderos']), 'Tramo verificado invalido')
        key = (route_id, desde, hasta)
        exigir(key not in tramos, 'Tramo duplicado o ambiguo')
        tramos.add(key)
        exigir(texto(vinculo.get('cartelDestino'), 160), 'Falta cartel de destino comprobado')
        v = vinculo.get('verificacion', {})
        exigir(v.get('estado') == 'verificado', 'No empaquetes borradores como identidades publicadas')
        for campo, limite in [('fuente', 500), ('verificadoPor', 160)]:
            exigir(texto(v.get(campo), limite), 'Falta evidencia de verificacion: ' + campo)
        fecha = dt.date.fromisoformat(v.get('fecha', ''))
        hasta_fecha = dt.date.fromisoformat(v.get('vigenteHasta', ''))
        exigir(fecha.isoformat() == v['fecha'] and hasta_fecha.isoformat() == v['vigenteHasta'], 'Usa fechas AAAA-MM-DD')
        exigir(dt.date(1970, 1, 1) <= fecha <= hasta_fecha <= dt.date(2100, 12, 31), 'Fechas fuera de rango')
        exigir(fecha <= dt.datetime.now(dt.timezone.utc).date(), 'Verificacion con fecha futura')
    exigir(identidades_usadas == ids, 'Hay identidades sin un vinculo verificado')
    rutas_foto = set()
    for registro in fotos_referencia:
        referencia = registro.get('referenciaGTFS', {})
        route_id = referencia.get('routeID')
        exigir(route_id in referencias and route_id not in rutas_foto, 'Referencia fotografica desconocida o duplicada')
        rutas_foto.add(route_id)
        exigir(referencia == referencias[route_id], 'Referencia fotografica no coincide con GTFS: ' + route_id)
        codigo = referencia['linea']
        letra = referencia['variante'].strip()
        if not letra and codigo.startswith('CT-'):
            partes = codigo.split(maxsplit=1)
            codigo = partes[0]
            letra = partes[1] if len(partes) == 2 else ''
        letra = ' '.join(letra.replace('<3', ' ♥').split())
        exigir(letra and registro.get('codigoFuente') == codigo + ' ' + letra,
               'La foto no confirma la letra o variante especifica del GTFS')
        url = urlparse(registro.get('fuenteURL', ''))
        exigir(url.scheme == 'https' and url.hostname and not url.username and not url.password, 'Fuente fotografica invalida')
        exigir(registro.get('derechos') in ('pendiente', 'autorizado'), 'Estado de derechos no indicado')
        revision = dt.date.fromisoformat(registro.get('fechaRevision', ''))
        exigir(revision.isoformat() == registro['fechaRevision'] and dt.date(1970, 1, 1) <= revision <= dt.datetime.now(dt.timezone.utc).date(),
               'Fecha de revision fotografica invalida')
        if registro.get('fechaFoto') is not None:
            fecha_foto = dt.date.fromisoformat(registro['fechaFoto'])
            exigir(fecha_foto.isoformat() == registro['fechaFoto'] and dt.date(1970, 1, 1) <= fecha_foto <= revision,
                   'Fecha de foto invalida')
        foto = registro.get('foto', {})
        exigir(foto.get('archivo') in archivos, 'Falta foto de referencia')
        exigir(entero(foto.get('ancho')) and entero(foto.get('alto')), 'Dimensiones de referencia invalidas')
        exigir((foto['ancho'], foto['alto'], foto.get('sha256')) == archivos[foto['archivo']], 'Referencia y archivo no coinciden')
        exigir(texto(foto.get('credito'), 200) and texto(foto.get('autorizacion'), 500), 'Falta credito o estado de autorizacion')
        usados.add(foto['archivo'])
    exigir(usados == set(archivos), 'Hay fotos sin usar; retiralas del paquete para ahorrar espacio')
    return {'fotos': len(archivos), 'bytes_fotos': total, 'identidades': len(ids), 'rutas': len(rutas), 'vinculos': len(tramos),
            'referencias_fotograficas': len(rutas_foto)}


if __name__ == '__main__':
    try:
        root = Path(sys.argv[1]).resolve()
        resultado = validar(root)
        if len(sys.argv) == 3:
            Path(sys.argv[2]).write_text(json.dumps(resultado, sort_keys=True) + '\n')
        print('Micros: ' + json.dumps(resultado, sort_keys=True))
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        print('error: Catalogo de micros: ' + str(error), file=sys.stderr)
        sys.exit(1)
