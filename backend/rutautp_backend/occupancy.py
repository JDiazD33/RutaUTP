"""Ocupación por unidad: voto reciente por principal detectado a bordo."""
from __future__ import annotations

import json
import math
import re

REPORT_TOPIC = "rutautp/ocupacion/+/reporte"
SNAPSHOT_TOPIC = "rutautp/ocupacion/estado"
WINDOW = 180


class Occupancy:
    def __init__(self, vehicles):
        # Consulta de solo lectura; no modifica la agregación de posiciones.
        self.vehicles = vehicles
        self.votes = {}
        self.last_reports = {}
        self.last_snapshot = float("-inf")

    def active_vehicles(self, now):
        return {v.vehicle_id: v for v in self.vehicles()
                if -10 <= now - v.last_seen <= 45}

    def prune(self, now):
        active = self.active_vehicles(now)
        self.votes = {vid: {p: vote for p, vote in votes.items()
                            if now - vote[1] < WINDOW}
                      for vid, votes in self.votes.items() if vid in active}
        self.votes = {vid: votes for vid, votes in self.votes.items() if votes}
        self.last_reports = {p: t for p, t in self.last_reports.items() if now - t < 30}
        return active

    def status(self, vehicle_id, now):
        votes = self.votes.get(vehicle_id, {})
        counts = {state: sum(v[0] == state for v in votes.values())
                  for state in ("empty", "full")}
        state = max(counts, key=counts.get)
        other = "empty" if state == "full" else "full"
        if counts[state] < 2 or counts[state] <= counts[other]:
            return None
        # Conservador: retirar al vencer el voto más antiguo de la mayoría.
        # El siguiente snapshot recalcula si aún queda quorum suficiente.
        matching = [v[1] for v in votes.values() if v[0] == state]
        return dict(vehicleId=vehicle_id, state=state, confirmations=counts[state],
                    updatedAt=max(matching), expiresAt=min(matching)+WINDOW)

    def handle(self, topic, payload, now):
        active = self.prune(now)
        match = re.fullmatch(r"rutautp/ocupacion/([^/+#\x00]{1,128})/reporte", topic)
        if not match or len(payload) > 1024:
            return None
        principal = match[1]
        try:
            body = json.loads(payload)
            request_id = body["requestId"]
            if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,64}", request_id):
                return None
            receipt = dict(requestId=request_id, accepted=False, code="invalid")
            vehicle_id, state, timestamp = body["vehicleId"], body["state"], body["timestamp"]
            if (type(body.get("schemaVersion")) is not int or body["schemaVersion"] != 1
                or not isinstance(vehicle_id, str) or not 1 <= len(vehicle_id) <= 200
                or state not in ("empty", "full")
                or type(timestamp) not in (int, float) or not math.isfinite(timestamp)
                or not -10 <= now - timestamp <= 60):
                return principal, receipt
            vehicle = active.get(vehicle_id)
            if vehicle is None:
                receipt["code"] = "unavailable"
                return principal, receipt
            if not -10 <= now - vehicle.principals.get(principal, float("-inf")) <= 60:
                receipt["code"] = "not_onboard"
                return principal, receipt
            if principal in self.last_reports:
                receipt["code"] = "rate_limit"
                return principal, receipt
            if len(self.last_reports) >= 5000 or (vehicle_id not in self.votes and len(self.votes) >= 500):
                receipt["code"] = "busy"
                return principal, receipt
            votes = self.votes.setdefault(vehicle_id, {})
            if principal not in votes and len(votes) >= 1000:
                receipt["code"] = "busy"
                return principal, receipt
            self.last_reports[principal] = now
            # Una cuenta no respalda simultáneamente la ocupación de dos buses.
            for group in self.votes.values():
                group.pop(principal, None)
            votes[principal] = state, now
            status = self.status(vehicle_id, now)
            receipt.update(accepted=True, code="confirmed" if status and status["state"] == state else "pending")
            return principal, receipt
        except (ValueError, TypeError, KeyError, UnicodeDecodeError, RecursionError):
            return None

    def snapshot(self, now):
        self.prune(now)
        return dict(schemaVersion=1, timestamp=now,
                    buses=[status for vid in self.votes
                           if (status := self.status(vid, now)) is not None])

    def publish_snapshot(self, now, publisher):
        if publisher and now - self.last_snapshot >= 5:
            if publisher(SNAPSHOT_TOPIC, json.dumps(self.snapshot(now))):
                self.last_snapshot = now
