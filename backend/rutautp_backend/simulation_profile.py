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
# Perfiles explícitos: cada ampliación conserva su whitelist y presupuesto.
PROFILE_SPECS = {'ensayo-2': (2, 1, 300, 240), 'ensayo-6': (6, 2, 300, 720),
                 'pasajeros-30': (30, 10, 900, 6000), 'pasajeros-50': (50, 15, 300, 6000)}
# Tope diario de mensajes de la presentación (suma de todas sus sesiones del día,
# hora de Lima). Protege la cuota del plan de EMQX y frena una simulación que no
# se apague. Antes era 10000: subirlo exige cambiarlo aquí y en los escenarios.
CUPO_DIARIO_PRESENTACION = 30000
PROFILE_DAY_LIMITS = {'ensayo-2': 6000, 'ensayo-6': 6000, 'pasajeros-30': CUPO_DIARIO_PRESENTACION,
                      'pasajeros-50': CUPO_DIARIO_PRESENTACION}

# Variantes `micros-N`: las mismas 50 cuentas de pasajeros-50 repartidas en N
# micros. El backend exige 2 cuentas distintas por micro, así que 50 cuentas
# admiten hasta 25. Conservan duración y presupuestos de pasajeros-50.
MICROS_BASE = 'pasajeros-50'
MICROS_MINIMO, MICROS_MAXIMO = 10, 25
for _micros in range(MICROS_MINIMO, MICROS_MAXIMO + 1):
    PROFILE_SPECS[f'micros-{_micros}'] = (50, _micros, 300, 6000)
    PROFILE_DAY_LIMITS[f'micros-{_micros}'] = CUPO_DIARIO_PRESENTACION
del _micros

# El motor exige una ruta distinta por micro. Rutas para los micros 16 a 25:
# siguen el orden de route_id, con líneas distintas a las del perfil base, y
# se comprobaron contra el feed fijado por huella (primer viaje de cada ruta,
# su trazado y la línea que calcula el backend). Si el feed cambia, la huella
# del perfil falla antes de usarlas.
RUTAS_EXTRA_MICROS = (
    ("17463385", "C-22", "15"), ("17463445", "M-23", "16"), ("17491518", "C-03", "18"),
    ("17492018", "C-05", "19"), ("17508289", "C-12", "20"), ("17508501", "C-13", "22"),
    ("17508507", "C-16", "24"), ("17520880", "C-23", "25"), ("17520994", "C-18", "26"),
    ("17521004", "C-24", "27"),
)


def derivar_micros(base_bytes: bytes, micros: int) -> bytes:
    """Reparte las cuentas del perfil base en `micros` micros, con 2 o más cada uno.

    Es determinista: cada proceso obtiene los mismos bytes y la misma huella.
    Los primeros micros conservan las rutas del perfil base; los siguientes
    usan `RUTAS_EXTRA_MICROS`.
    """
    body = json.loads(base_bytes.decode("utf-8"))
    base = body["vehicles"]
    principals = [p for vehicle in base for p in vehicle["principals"]]
    cuota, resto = divmod(len(principals), micros)
    if cuota < 2:
        raise ValueError("cada micro necesita al menos 2 cuentas")
    if micros > len(base) + len(RUTAS_EXTRA_MICROS):
        raise ValueError("no hay rutas preparadas para tantos micros")
    vehicles, inicio = [], 0
    for indice in range(micros):
        if indice < len(base):
            vehicle = {k: v for k, v in base[indice].items() if k != "principals"}
        else:
            extra = indice - len(base)
            route_id, linea, trip_id = RUTAS_EXTRA_MICROS[extra]
            vehicle = {"routeId": route_id, "linea": linea, "tripId": trip_id,
                       "shapeId": route_id, "initialProgress": round(0.1 + 0.05 * extra, 2)}
        vehicle["scenarioVehicleId"] = f"scenario-bus-{indice + 1:02d}"
        tamano = cuota + (1 if indice < resto else 0)
        vehicle["principals"] = principals[inicio:inicio + tamano]
        inicio += tamano
        vehicles.append(vehicle)
    body["scenarioId"] = f"micros-{micros}"
    body["limits"]["nominalVehicleCount"] = micros
    body["vehicles"] = vehicles
    return (json.dumps(body, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
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
            raise ValueError('perfil no preparado: ' + ', '.join(PROFILE_SPECS))
        actor_count, vehicle_count, max_duration, max_calls = PROFILE_SPECS[name]
        derivado = name.startswith('micros-')
        # Un perfil derivado vigila y lee el archivo base; su huella es la del
        # JSON derivado, que es lo que se fija en el control del run.
        path = PROFILE_DIRECTORY / f"{MICROS_BASE if derivado else name}.json"
        watched = [path, *(gtfs_dir / filename for filename in sorted(FEED_HASH_FILES))]
        def signatures():
            return tuple((s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
                         for s in (p.stat() for p in watched))
        before = signatures()
        raw_bytes = path.read_bytes()
        if derivado:
            raw_bytes = derivar_micros(raw_bytes, vehicle_count)
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
                             ('maxObservationPublishCallsPerDay', PROFILE_DAY_LIMITS[name])):
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
