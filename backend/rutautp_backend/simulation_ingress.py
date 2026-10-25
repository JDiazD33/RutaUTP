"""Autoridad de entrada interna. S04 suministra la autorización durable vigente.

No interpreta órdenes MQTT ni confía en campos del payload del pasajero. El
principal del tópico solo es auténtico si el broker aplica la ACL de identidad.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Callable

from .simulation_models import DataOrigin, canonical_uuid, finite_time

SIMULATION_OBSERVATIONS_TOPIC = "rutautp/simulacion/+/observaciones/+/+/posicion"
SIMULATION_CONTROL_TOPIC = "rutautp/simulacion/estado"
_SYNTHETIC_PRINCIPAL = re.compile(r"sim-[0-9]{3}\Z")


def is_reserved_principal(principal: str) -> bool:
    # Toda la familia se reserva, también nombres mal formados: no degradarlos
    # a observados por no figurar todavía en el manifiesto de un run.
    return principal.casefold().startswith("sim-")


def _topic_identifier(value: str) -> bool:
    return bool(value) and value == value.strip() and len(value) <= 128 and not any(
        char in value for char in ("+", "#", "\x00")
    )


@dataclass(frozen=True)
class ObservationTopic:
    origin: DataOrigin
    principal: str
    session_id: str
    run_id: str | None = None


def parse_observation_topic(topic: str) -> ObservationTopic | None:
    parts = topic.split("/")
    if len(parts) == 5 and parts[:2] == ["rutautp", "observaciones"] and parts[4] == "posicion":
        principal, session = parts[2:4]
        if _topic_identifier(principal) and _topic_identifier(session):
            return ObservationTopic(DataOrigin.OBSERVED, principal, session)
    if (len(parts) == 7 and parts[:2] == ["rutautp", "simulacion"]
            and parts[3] == "observaciones" and parts[6] == "posicion"):
        run_id, principal, session = parts[2], parts[4], parts[5]
        try:
            canonical_uuid(run_id)
            canonical_uuid(session)
        except ValueError:
            return None
        if _SYNTHETIC_PRINCIPAL.fullmatch(principal):
            return ObservationTopic(DataOrigin.SIMULATED, principal, session, run_id)
    return None


@dataclass(frozen=True)
class SimulationAdmission:
    """Permiso ya verificado por el controlador interno; nunca por el actor.

    Solo un run simultáneo. El controlador comprueba horario, revisión durable,
    manifiesto y lease confirmado antes de entregar este valor. La identidad
    depende de las ACL efectivas que se verifican antes del despliegue. Sin
    proveedor no hay autorización; este valor no sustituye al estado durable.
    """

    run_id: str
    control_revision: int
    principals: frozenset[str]
    issued_at: float
    valid_until: float
    service_ends_at: float

    def __post_init__(self) -> None:
        canonical_uuid(self.run_id)
        if (type(self.control_revision) is not int
                or not 1 <= self.control_revision <= 2**53 - 1):
            raise ValueError("controlRevision debe ser un entero positivo seguro")
        principals = frozenset(self.principals)
        if not 1 <= len(principals) <= 100 or any(
            not isinstance(p, str) or not _SYNTHETIC_PRINCIPAL.fullmatch(p) for p in principals
        ):
            raise ValueError("whitelist sintética inválida")
        object.__setattr__(self, "principals", principals)
        for value in (self.issued_at, self.valid_until, self.service_ends_at):
            finite_time(value)
        if not self.issued_at < self.valid_until <= self.service_ends_at:
            raise ValueError("autorización temporal inconsistente")
        if self.valid_until - self.issued_at > 15:
            raise ValueError("la autorización sintética no puede superar 15 s")

    def is_current(self, now: float) -> bool:
        finite_time(now)
        return self.issued_at <= now < self.valid_until


AdmissionProvider = Callable[[float], SimulationAdmission | None]
