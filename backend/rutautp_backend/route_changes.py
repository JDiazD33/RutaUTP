"""Reportes de desvío independientes del rastreo vehicular.

Dos principales MQTT distintos, misma ruta/motivo y puntos a <=200 m.
Los votos caducan a los 15 minutos; se pierde el quorum al caducar uno.
Estado efímero: tras reiniciar se requieren reportes nuevos.
"""
from __future__ import annotations

import json
import math
import re
import uuid

from .geo import haversine_m, match_point_to_polyline

REPORT_TOPIC = "rutautp/cambios/+/reporte"
SNAPSHOT_TOPIC = "rutautp/cambios/estado"
WINDOW = 15 * 60


class RouteChanges:
    def __init__(self, feed):
        self.feed = feed
        self.groups = []
        self.last_snapshot = float("-inf")
        self.last_reports = {}

    def prune(self, now):
        for group in self.groups:
            group["votes"] = {p: t for p, t in group["votes"].items() if now - t < WINDOW}
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
            if (type(body.get("schemaVersion")) is not int or body.get("schemaVersion") != 1 or route is None
                or reason not in ("works", "closure", "detour")
                or not isinstance(place, str) or not 3 <= len(place.strip()) <= 120
                or any(type(v) not in (int, float) or not math.isfinite(v) for v in (lat, lon, timestamp))
                or not -90 <= lat <= 90 or not -180 <= lon <= 180
                or not -10 <= now - timestamp <= 120):
                return (principal, receipt)
            location = match_point_to_polyline(lat, lon, list(route.shape), threshold_m=500)
            if not location or not location.is_on_route:
                receipt["code"] = "off_route"
                return (principal, receipt)
            if principal in self.last_reports:
                receipt["code"] = "rate_limit"
                return (principal, receipt)
            if len(self.last_reports) >= 5000:
                receipt["code"] = "busy"
                return (principal, receipt)
            self.last_reports[principal] = now
            group = next((g for g in self.groups if g["routeId"] == route_id
                          and g["reason"] == reason
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
            receipt.update(accepted=True, code="confirmed" if len(group["votes"]) >= 2 else "pending")
            return (principal, receipt)
        except (ValueError, TypeError, KeyError, UnicodeDecodeError, RecursionError):
            return None

    def snapshot(self, now):
        self.prune(now)
        alerts = []
        for group in self.groups:
            if len(group["votes"]) < 2:
                continue
            # La segunda confirmación más reciente determina hasta cuándo hay quorum.
            expires = sorted(group["votes"].values(), reverse=True)[1] + WINDOW
            alerts.append({**{k: v for k, v in group.items() if k != "votes"},
                           "confirmations": len(group["votes"]), "expiresAt": expires})
        return {"schemaVersion": 1, "timestamp": now, "alerts": alerts}

    def publish_snapshot(self, now, publisher):
        if publisher and now - self.last_snapshot >= 5:
            if publisher(SNAPSHOT_TOPIC, json.dumps(self.snapshot(now))):
                self.last_snapshot = now
