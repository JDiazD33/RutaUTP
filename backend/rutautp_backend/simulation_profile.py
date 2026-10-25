"""Perfil autorizado de S01, compartible con el futuro motor S05/S06."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, time
from pathlib import Path
from zoneinfo import ZoneInfo

from .simulation_models import FEED_HASH_FILES, SimulationRunRecord

PROFILE_DIRECTORY = Path(__file__).resolve().parents[1] / "simulation/scenarios"
# Perfiles explícitos: no habilitar tamaños arbitrarios ni 50/100 incidentalmente.
PROFILE_SPECS = {'ensayo-2': (2, 1, 300, 240), 'ensayo-6': (6, 2, 300, 720),
                 'pasajeros-30': (30, 10, 900, 6000)}
def lima_zone() -> ZoneInfo:
    # No exigir la base IANA al arrancar el circuito observado con simulación
    # apagada. Si falta al activar, el controlador revoca el perfil.
    return ZoneInfo("America/Lima")


@dataclass(frozen=True)
class SimulationProfile:
    path: Path
    raw: str
    sha256: str
    name: str
    version: int
    seed: int
    principals: frozenset[str]
    starts_at: time
    ends_at: time
    max_run_seconds: int
    feed_hashes: dict[str, str]
    verified_signatures: tuple

    @classmethod
    def load(cls, name: str, gtfs_dir: Path) -> "SimulationProfile":
        if name not in PROFILE_SPECS:
            raise ValueError('perfil no preparado; solo ensayo-2, ensayo-6 y pasajeros-30')
        actor_count, vehicle_count, max_duration, max_calls = PROFILE_SPECS[name]
        path = PROFILE_DIRECTORY / f"{name}.json"
        watched = [path, *(gtfs_dir / filename for filename in sorted(FEED_HASH_FILES))]
        def signatures():
            return tuple((s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
                         for s in (p.stat() for p in watched))
        before = signatures()
        raw_bytes = path.read_bytes()
        if len(raw_bytes) > 64 * 1024:
            raise ValueError("manifiesto demasiado grande")
        raw = raw_bytes.decode("utf-8")
        body = json.loads(raw)
        if (type(body["schemaVersion"]) is not int or body["schemaVersion"] != 1 or body["scenarioId"] != name
                or body["enabledByDefault"] is not False or body["dataOrigin"] != "simulated"
                or body["clock"] != {"mode": "realtime", "rate": 1}
                or type(body["clock"]["rate"]) is not int
                or any(type(v) is not int for v in body["contracts"].values())
                or body["contracts"] != {"passengerObservation": 1, "vehiclePosition": 2, "simulationControl": 1}):
            raise ValueError("contrato del perfil incompatible")
        service = body["service"]
        if service["timeZone"] != "America/Lima" or service["closePolicy"] != "stop_at_boundary":
            raise ValueError("horario incompatible")
        hours = [service["startsAtLocal"], service["endsAtLocal"]]
        if any(not isinstance(h, str) or not re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", h) for h in hours):
            raise ValueError("hora local inválida")
        start, end = (time.fromisoformat(h) for h in hours)
        if start >= end:
            raise ValueError("la ventana debe cerrar el mismo día")
        if body["control"]["heartbeatIntervalSeconds"] != 5 or body["control"]["leaseSeconds"] != 15:
            raise ValueError("control incompatible con cadencia 5 s / lease 15 s")
        limits = body["limits"]
        if limits['maxConcurrentActors'] != actor_count or limits['nominalVehicleCount'] != vehicle_count:
            raise ValueError('los conteos no coinciden con el perfil preparado')
        duration = limits["maxRunDurationSeconds"]
        if type(duration) is not int or not 1 <= duration <= max_duration:
            raise ValueError("duración del run inválida")
        for key, maximum in (('maxObservationPublishCallsPerRun', max_calls),
                             ('maxObservationPublishCallsPerDay', 6000)):
            if type(limits[key]) is not int or not 1 <= limits[key] <= maximum:
                raise ValueError('presupuesto del perfil fuera de rango')
        vehicles = body["vehicles"]
        principals = [p for vehicle in vehicles for p in vehicle["principals"]]
        if (len(vehicles) != vehicle_count or len(principals) != actor_count
                or set(principals) != {f"sim-{i:03d}" for i in range(1, actor_count+1)}
                or any(len(v["principals"]) < 2 for v in vehicles)):
            raise ValueError("whitelist/quorum del perfil inválidos")
        digest = hashlib.sha256(raw_bytes).hexdigest()
        hashes = body["feed"]["sha256"]
        # Reutiliza la validación de versión, semilla y cinco SHA-256 de S02.
        SimulationRunRecord("00000000-0000-4000-8000-000000000001", name,
                            body["scenarioVersion"], body["seed"], digest, hashes, 0)
        if set(hashes) != FEED_HASH_FILES:
            raise ValueError("feed incompleto")
        for filename, expected in hashes.items():
            if hashlib.sha256((gtfs_dir / filename).read_bytes()).hexdigest() != expected:
                raise ValueError(f"el feed no coincide: {filename}")
        if signatures() != before:
            raise ValueError("el perfil/feed cambió durante la verificación")
        return cls(path, raw, digest, name, body["scenarioVersion"], body["seed"],
                   frozenset(principals), start, end, duration, dict(hashes), before)

    def window(self, now: float) -> tuple[bool, str, float]:
        zone = lima_zone()
        local = datetime.fromtimestamp(now, zone)
        opens = datetime.combine(local.date(), self.starts_at, zone).timestamp()
        closes = datetime.combine(local.date(), self.ends_at, zone).timestamp()
        return opens <= now < closes, local.date().isoformat(), closes

    def pinned(self) -> dict:
        return {"name": self.name, "path": str(self.path), "sha256": self.sha256, "raw": self.raw}

    def signatures(self, gtfs_dir: Path) -> tuple:
        # Detección barata entre verificaciones de hashes, sin releer shapes a
        # cada observación. Cualquier cambio exige otro enable/verificación.
        paths = [self.path, *(gtfs_dir / name for name in sorted(FEED_HASH_FILES))]
        return tuple((s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
                     for s in (p.stat() for p in paths))
