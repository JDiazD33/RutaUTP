"""Reportes de cambios de ruta e incidencias, independientes del rastreo vehicular.

Un aviso se publica cuando `quorum` principales MQTT distintos (2 por defecto)
reportan el mismo motivo con puntos a <=200 m. Obras, cierres y desvíos se
agrupan además por ruta; tráfico y choques son de la vía y suman entre líneas.
Cada voto dura lo que su motivo (`TTL`): una obra no caduca como un atasco.
Se pierde el quorum al caducar un voto; cada reporte nuevo renueva el suyo.
Estado efímero: tras reiniciar se requieren reportes nuevos.

La calle nueva (`path`) es el trazo que graba el teléfono a bordo entre la
salida del recorrido y el reingreso. Solo se publica cuando dos cuentas del
mismo grupo aportan trazos que coinciden: un trazo aislado nunca se dibuja.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
import re
import uuid

from .geo import haversine_m, match_point_to_polyline
from .models import is_finite_real

logger = logging.getLogger(__name__)

REPORT_TOPIC = "rutautp/cambios/+/reporte"
SNAPSHOT_TOPIC = "rutautp/cambios/estado"
# Vigencia de cada voto, en segundos, según lo que suele durar la incidencia.
TTL = {"traffic": 30 * 60, "crash": 60 * 60, "closure": 12 * 3600,
       "detour": 24 * 3600, "works": 24 * 3600}
# Incidencias de la vía: afectan a cualquier línea que pase por el punto.
ROAD_REASONS = ("traffic", "crash")
DEFAULT_QUORUM = 2
# Con votos de hasta 24 h, una sola cuenta no debe poder llenar la memoria.
MAX_VOTES_PER_PRINCIPAL = 10
MAX_STRETCH_M = 5000
# Trazo de la calle nueva: polilínea codificada (algoritmo de Google,
# precisión 1e-5), igual que `PolilineaCodificada` en la app.
MAX_PATH_CHARS = 1400
MAX_PATH_POINTS = 120
# Sus extremos coinciden con el inicio y con el punto donde retoma.
PATH_ENDPOINT_M = 75
# Un salto mayor entre puntos consecutivos es un error de GPS.
PATH_MAX_STEP_M = 600
PATH_MAX_LENGTH_M = 8000
# Algún punto debe apartarse del recorrido; si no, no hay calle nueva.
PATH_MIN_DEVIATION_M = 60
# Dos trazos son la misma calle si ninguno se aparta del otro más de
# PATH_AGREEMENT_MAX_M y, de media, no más de PATH_AGREEMENT_MEAN_M.
PATH_AGREEMENT_MAX_M = 80
PATH_AGREEMENT_MEAN_M = 35
PATH_SAMPLE_M = 40
# Cada trazo se compara con los anteriores del grupo: el tope acota el coste.
MAX_PATHS_PER_GROUP = 6
# Incidencias simuladas de la presentación: se publican marcadas y con una
# vigencia que se renueva en cada snapshot mientras el backend las sirve.
SIMULATED_TTL_S = 30 * 60
MAX_SIMULATED = 60
# Una incidencia simulada puede aparecer `afterS` segundos después del primer
# snapshot, como si la comunidad la reportara durante la presentación.
MAX_SIMULATED_DELAY_S = 3600


def encode_polyline(points):
    """Codifica [(lat, lon), ...] con precisión 1e-5."""
    out, previous = [], (0, 0)
    for lat, lon in points:
        current = (round(lat * 1e5), round(lon * 1e5))
        for value in (current[0] - previous[0], current[1] - previous[1]):
            value = ~(value << 1) if value < 0 else value << 1
            while value >= 0x20:
                out.append(chr((0x20 | (value & 0x1F)) + 63))
                value >>= 5
            out.append(chr(value + 63))
        previous = current
    return "".join(out)


def decode_polyline(text):
    """Decodifica una polilínea; `None` si no es completa y válida."""
    if not isinstance(text, str) or not 1 <= len(text) <= MAX_PATH_CHARS:
        return None
    points, index, lat, lon = [], 0, 0, 0
    while index < len(text):
        deltas = []
        for _ in range(2):
            result = shift = 0
            while True:
                if index >= len(text) or shift > 30:
                    return None
                chunk = ord(text[index]) - 63
                index += 1
                if not 0 <= chunk <= 63:
                    return None
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20:
                    break
            deltas.append(~(result >> 1) if result & 1 else result >> 1)
        lat, lon = lat + deltas[0], lon + deltas[1]
        point = (lat / 1e5, lon / 1e5)
        if not -90 <= point[0] <= 90 or not -180 <= point[1] <= 180 or len(points) >= MAX_PATH_POINTS:
            return None
        points.append(point)
    return points


def valid_path(points, start, end, shape):
    """Trazo plausible entre el inicio y el reingreso que sale del recorrido."""
    if points is None or len(points) < 3:
        return False
    if haversine_m(*points[0], *start) > PATH_ENDPOINT_M or haversine_m(*points[-1], *end) > PATH_ENDPOINT_M:
        return False
    length = 0.0
    for a, b in zip(points, points[1:]):
        step = haversine_m(*a, *b)
        if step > PATH_MAX_STEP_M:
            return False
        length += step
    if length > PATH_MAX_LENGTH_M:
        return False
    return any((match := match_point_to_polyline(lat, lon, shape, threshold_m=PATH_MIN_DEVIATION_M))
               and not match.is_on_route for lat, lon in points)


def _samples(points):
    """Puntos cada PATH_SAMPLE_M a lo largo del trazo, extremos incluidos."""
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        parts = max(1, int(haversine_m(*a, *b) // PATH_SAMPLE_M))
        out += [(a[0] + (b[0] - a[0]) * i / parts, a[1] + (b[1] - a[1]) * i / parts)
                for i in range(1, parts + 1)]
    return out


def paths_agree(first, second):
    """Dos trazos describen la misma calle si ninguno se separa del otro."""
    distances = []
    for samples, other in ((_samples(first), second), (_samples(second), first)):
        for lat, lon in samples:
            match = match_point_to_polyline(lat, lon, other, threshold_m=PATH_AGREEMENT_MAX_M)
            if match is None or not match.is_on_route:
                return False
            distances.append(match.distance_m)
    return sum(distances) / len(distances) <= PATH_AGREEMENT_MEAN_M


def load_simulated(path, feed):
    """Lee y valida las incidencias simuladas de la presentación.

    Cada una cumple las mismas reglas que un reporte: ruta conocida, motivo
    válido, puntos a 500 m o menos del recorrido y tramo y trazo plausibles.
    Las que no cumplen se descartan con un aviso; un archivo ilegible no
    publica ninguna, pero no detiene el backend.
    """
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        logger.error("incidencias simuladas: no se pudo leer %s: %s", path, error)
        return []
    items = data.get("alerts") if isinstance(data, dict) and data.get("schemaVersion") == 1 else None
    if not isinstance(items, list):
        logger.error("incidencias simuladas: formato desconocido en %s", path)
        return []
    alerts, seen = [], set()
    for item in items[:MAX_SIMULATED]:
        alert = _simulated_alert(item, feed)
        if alert is None or alert["id"] in seen:
            logger.warning("incidencia simulada descartada: %r", item.get("id") if isinstance(item, dict) else item)
            continue
        seen.add(alert["id"])
        alerts.append(alert)
    return alerts


def _simulated_alert(item, feed):
    """Una incidencia simulada lista para el snapshot, o `None` si no vale."""
    if not isinstance(item, dict):
        return None
    ident, route_id, reason = item.get("id"), item.get("routeId"), item.get("reason")
    lat, lon, place = item.get("lat"), item.get("lon"), item.get("place")
    via, path_text = item.get("via"), item.get("path")
    after = item.get("afterS", 0)
    end = (item.get("endLat"), item.get("endLon"))
    has_end = end != (None, None)
    route = feed.get(route_id) if isinstance(route_id, str) else None
    if (route is None or reason not in TTL
            or not isinstance(ident, str) or not re.fullmatch(r"[a-z0-9-]{1,40}", ident)
            or not isinstance(place, str) or not 3 <= len(place.strip()) <= 120
            or not all(is_finite_real(v) for v in (lat, lon))
            or type(after) is not int or not 0 <= after <= MAX_SIMULATED_DELAY_S
            or (via is not None and (not isinstance(via, str) or not 3 <= len(via.strip()) <= 80))
            or (has_end and (not all(is_finite_real(v) for v in end)
                             or not 50 <= haversine_m(lat, lon, *end) <= MAX_STRETCH_M))
            or (path_text is not None and (not has_end or reason in ROAD_REASONS))):
        return None
    shape = list(route.shape)
    for point in ((lat, lon), end) if has_end else ((lat, lon),):
        match = match_point_to_polyline(*point, shape, threshold_m=500)
        if not match or not match.is_on_route:
            return None
    if path_text is not None and not valid_path(decode_polyline(path_text), (lat, lon), end, shape):
        return None
    alert = {"id": f"sim-{ident}", "routeId": route_id, "reason": reason,
             "lat": lat, "lon": lon, "place": place.strip(), "simulated": True}
    if via is not None:
        alert["via"] = via.strip()
    if has_end:
        alert["endLat"], alert["endLon"] = end
    if path_text is not None:
        alert["path"] = path_text
    if after:
        alert["afterS"] = after
    return alert


class RouteChanges:
    def __init__(self, feed, quorum=DEFAULT_QUORUM, simulated=()):
        if type(quorum) is not int or quorum < 2:
            raise ValueError("quorum debe ser un entero mayor o igual que 2")
        self.feed = feed
        self.quorum = quorum
        # Incidencias simuladas de la presentación. No tienen votos ni avisos
        # push: se publican con el quorum y una vigencia que se renueva. Las
        # que llevan `afterS` esperan ese tiempo desde el primer snapshot.
        self.simulated = list(simulated)
        self.simulated_origin = None
        self.groups = []
        self.last_snapshot = float("-inf")
        self.last_reports = {}

    def prune(self, now):
        for group in self.groups:
            ttl = TTL[group["reason"]]
            group["votes"] = {p: t for p, t in group["votes"].items() if now - t < ttl}
            # El trazo de una cuenta deja de contar cuando caduca su voto.
            if "paths" in group:
                group["paths"] = {p: v for p, v in group["paths"].items() if p in group["votes"]}
        self.groups = [g for g in self.groups if g["votes"]]
        self.last_reports = {p: t for p, t in self.last_reports.items() if now - t < 30}

    def handle(self, topic, payload, now):
        """Devuelve recibo privado; identidad exclusivamente del tópico con ACL."""
        self.prune(now)
        match = re.fullmatch(r"rutautp/cambios/([^/+#\x00]{1,128})/reporte", topic)
        if not match or len(payload) > 2048:
            return None
        principal = match[1]
        try:
            body = json.loads(payload)
            request_id = body["requestId"]
            if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,64}", request_id):
                return None
            receipt = {"requestId": request_id, "accepted": False, "code": "invalid"}
            route_id, reason = body["routeId"], body["reason"]
            route = self.feed.get(route_id)
            lat, lon, timestamp = (body[key] for key in ("lat", "lon", "timestamp"))
            place = body["place"]
            # Opcionales: por dónde va ahora y dónde retoma su recorrido.
            via = body.get("via")
            end = (body.get("endLat"), body.get("endLon"))
            has_end = end != (None, None)
            # Opcional: trazo de la calle nueva. Exige el punto donde retoma.
            path_text = body.get("path")
            if (type(body.get("schemaVersion")) is not int or body.get("schemaVersion") != 1 or route is None
                or reason not in TTL
                or not isinstance(place, str) or not 3 <= len(place.strip()) <= 120
                or not all(is_finite_real(v) for v in (lat, lon, timestamp))
                or not -90 <= lat <= 90 or not -180 <= lon <= 180
                or not -10 <= now - timestamp <= 120
                or (via is not None and (not isinstance(via, str) or not 3 <= len(via.strip()) <= 80))
                # Solo obras, cierres y desvíos cambian el recorrido.
                or (path_text is not None and (not has_end or reason in ROAD_REASONS))
                or (has_end and (not all(is_finite_real(v) for v in end)
                                 or not -90 <= end[0] <= 90 or not -180 <= end[1] <= 180
                                 or not 50 <= haversine_m(lat, lon, *end) <= MAX_STRETCH_M))):
                return (principal, receipt)
            shape = list(route.shape)
            location = match_point_to_polyline(lat, lon, shape, threshold_m=500)
            if not location or not location.is_on_route:
                receipt["code"] = "off_route"
                return (principal, receipt)
            if has_end:
                rejoin = match_point_to_polyline(*end, shape, threshold_m=500)
                if not rejoin or not rejoin.is_on_route:
                    receipt["code"] = "off_route"
                    return (principal, receipt)
            if principal in self.last_reports:
                receipt["code"] = "rate_limit"
                return (principal, receipt)
            if len(self.last_reports) >= 5000:
                receipt["code"] = "busy"
                return (principal, receipt)
            self.last_reports[principal] = now
            # Validar el trazo cuesta más que el resto: se hace después de
            # consumir la cuota, para que repetirlo no ocupe el bucle MQTT.
            path = None
            if path_text is not None:
                path = decode_polyline(path_text)
                if not valid_path(path, (lat, lon), end, shape):
                    receipt["code"] = "invalid_path"
                    return (principal, receipt)
            group = next((g for g in self.groups if g["reason"] == reason
                          and (reason in ROAD_REASONS or g["routeId"] == route_id)
                          and haversine_m(lat, lon, g["lat"], g["lon"]) <= 200), None)
            if group is None:
                if len(self.groups) >= 500:
                    receipt["code"] = "busy"
                    return (principal, receipt)
                group = dict(id=str(uuid.uuid4()), routeId=route_id, reason=reason,
                             lat=lat, lon=lon, place=place.strip(), votes={})
                self.groups.append(group)
            if principal not in group["votes"] and len(group["votes"]) >= 1000:
                receipt["code"] = "busy"
                return (principal, receipt)
            group["votes"][principal] = now
            # El primer reporte que los aporta fija el tramo y la vía alterna.
            # Solo valen para la ruta del grupo: el tramo se midió sobre ella.
            if route_id == group["routeId"]:
                if via is not None and "via" not in group:
                    group["via"] = via.strip()
                if has_end and "endLat" not in group:
                    group["endLat"], group["endLon"] = end
                # La calle nueva se publica cuando dos cuentas graban trazos
                # que coinciden; se muestra el del reporte más antiguo.
                if path is not None and "path" not in group:
                    paths = group.setdefault("paths", {})
                    if principal not in paths and len(paths) < MAX_PATHS_PER_GROUP:
                        agreed = next((text for other, (text, points) in paths.items()
                                       if paths_agree(points, path)), None)
                        paths[principal] = (path_text, path)
                        if agreed is not None:
                            group["path"] = agreed
            self._cap_votes(principal, keep=group)
            count = len(group["votes"])
            if count >= self.quorum and "confirmedAt" not in group:
                group["confirmedAt"] = now
            receipt.update(accepted=True, code="confirmed" if count >= self.quorum else "pending",
                           confirmations=count, required=self.quorum)
            return (principal, receipt)
        except (ValueError, TypeError, KeyError, UnicodeDecodeError, RecursionError):
            return None

    def _cap_votes(self, principal, keep):
        """Retira los votos más antiguos de una cuenta que supera su tope."""
        own = sorted((g for g in self.groups if principal in g["votes"] and g is not keep),
                     key=lambda g: g["votes"][principal])
        for group in own[:max(0, len(own) + 1 - MAX_VOTES_PER_PRINCIPAL)]:
            del group["votes"][principal]
        self.groups = [g for g in self.groups if g["votes"]]

    def snapshot(self, now):
        self.prune(now)
        alerts = []
        for group in self.groups:
            if len(group["votes"]) < self.quorum:
                continue
            # El voto que completa el quorum, contando desde el más reciente,
            # determina hasta cuándo se mantiene.
            newest = sorted(group["votes"].values(), reverse=True)
            expires = newest[self.quorum - 1] + TTL[group["reason"]]
            # Los trazos por cuenta identifican a quien reportó: no se publican.
            alerts.append({**{k: v for k, v in group.items() if k not in ("votes", "confirmedAt", "paths")},
                           "confirmations": len(group["votes"]), "expiresAt": expires})
        if self.simulated_origin is None:
            self.simulated_origin = now
        elapsed = now - self.simulated_origin
        alerts += [{**{k: v for k, v in alert.items() if k != "afterS"},
                    "confirmations": self.quorum, "expiresAt": now + SIMULATED_TTL_S}
                   for alert in self.simulated if elapsed >= alert.get("afterS", 0)]
        return {"schemaVersion": 1, "timestamp": now, "quorum": self.quorum, "alerts": alerts}

    def confirmed_for_push(self, now):
        """Solo cambios de recorrido: un atasco o un choque no se notifican."""
        alerts = self.snapshot(now)["alerts"]
        confirmed = {g["id"]: g["confirmedAt"] for g in self.groups if "confirmedAt" in g}
        return [{**alert, "confirmedAt": confirmed[alert["id"]]} for alert in alerts
                if alert["id"] in confirmed and alert["reason"] not in ROAD_REASONS]

    def publish_snapshot(self, now, publisher):
        if publisher and now - self.last_snapshot >= 5:
            if publisher(SNAPSHOT_TOPIC, json.dumps(self.snapshot(now))):
                self.last_snapshot = now
