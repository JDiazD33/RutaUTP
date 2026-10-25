"""Procedencia y registros internos; no cambian los mensajes MQTT existentes."""

from __future__ import annotations

import math
import re
import uuid
from dataclasses import dataclass
from enum import Enum
from types import MappingProxyType
from typing import Mapping


class DataOrigin(str, Enum):
    OBSERVED = "observed"
    SIMULATED = "simulated"
    LEGACY_UNKNOWN = "legacy_unknown"
    UNKNOWN = "unknown"


class SimulationRunStatus(str, Enum):
    PREPARED = "prepared"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    DISABLED = "disabled"
    FAILED = "failed"


TERMINAL_RUN_STATUSES = frozenset({
    SimulationRunStatus.COMPLETED,
    SimulationRunStatus.DISABLED,
    SimulationRunStatus.FAILED,
})
FEED_HASH_FILES = frozenset({
    "routes.txt", "trips.txt", "shapes.txt", "stops.txt", "stop_times.txt",
})


def canonical_uuid(value: str) -> str:
    """Los UUID nuevos del backend/generador se guardan en formato canónico."""
    if not isinstance(value, str) or str(uuid.UUID(value)) != value:
        raise ValueError("se requiere un UUID canónico en minúsculas")
    return value


def finite_time(value: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("la fecha debe ser un número")
    if not math.isfinite(value) or value < 0:
        raise ValueError("la fecha debe ser finita y no negativa")
    return value


def canonical_text(value: str, name: str, limit: int = 128) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(f"{name} no canónico")
    if len(value) > limit or "\x00" in value:
        raise ValueError(f"{name} demasiado largo o inválido")
    return value


@dataclass(frozen=True)
class SourceContext:
    """Contexto interno construido por el backend, nunca desde una bandera JSON.

    En una posición agregada no hay un principal único. Para registrar una
    observación sintética sí se comprobará contra la sesión del actor.
    """

    origin: DataOrigin
    run_id: str | None = None
    principal: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.origin, DataOrigin):
            raise ValueError("origin debe ser DataOrigin")
        if self.origin is DataOrigin.LEGACY_UNKNOWN:
            raise ValueError("legacy_unknown se reserva a la migración")
        if self.origin is DataOrigin.SIMULATED:
            canonical_uuid(self.run_id)
        elif self.run_id is not None:
            raise ValueError("solo simulated puede pertenecer a un run")
        if self.principal is not None:
            canonical_text(self.principal, "principal")


OBSERVED_SOURCE = SourceContext(DataOrigin.OBSERVED)
UNKNOWN_SOURCE = SourceContext(DataOrigin.UNKNOWN)


@dataclass(frozen=True)
class SimulationRunRecord:
    run_id: str
    scenario_id: str
    scenario_version: int
    seed: int
    manifest_sha256: str
    feed_sha256: Mapping[str, str]
    created_at: float

    def __post_init__(self) -> None:
        canonical_uuid(self.run_id)
        canonical_text(self.scenario_id, "scenario_id", 64)
        for value, minimum in ((self.scenario_version, 1), (self.seed, 0)):
            if type(value) is not int or not minimum <= value <= 2**53 - 1:
                raise ValueError("versión o semilla fuera de rango")
        finite_time(self.created_at)
        if set(self.feed_sha256) != FEED_HASH_FILES:
            raise ValueError("se requieren los cinco hashes del feed de S01")
        for digest in (self.manifest_sha256, *self.feed_sha256.values()):
            if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("SHA-256 no canónico")
        object.__setattr__(self, "feed_sha256", MappingProxyType(dict(self.feed_sha256)))


@dataclass(frozen=True)
class SimulationActorRecord:
    run_id: str
    principal: str
    session_id: str
    scenario_vehicle_id: str
    route_id: str
    boarded_at: float

    def __post_init__(self) -> None:
        canonical_uuid(self.run_id)
        canonical_uuid(self.session_id)
        for name in ("principal", "scenario_vehicle_id", "route_id"):
            canonical_text(getattr(self, name), name)
        finite_time(self.boarded_at)
