"""Reloj a 1× e interfaz inyectable; nunca acelera timestamps para la red."""

from dataclasses import dataclass
import time
from typing import Protocol

from rutautp_backend.simulation_models import finite_time


@dataclass(frozen=True)
class ClockSample:
    unix: float
    monotonic: float

    def __post_init__(self):
        finite_time(self.unix)
        finite_time(self.monotonic)


class Clock(Protocol):
    def read(self) -> ClockSample: ...


class RealtimeClock:
    def read(self) -> ClockSample:
        return ClockSample(time.time(), time.monotonic())


class ClockDiscontinuity(ValueError):
    pass


class ClockGuard:
    def __init__(self):
        self.previous: ClockSample | None = None

    def elapsed(self, sample: ClockSample) -> float:
        previous = self.previous
        if previous is None:
            self.previous = sample
            return 0.0
        delta = sample.monotonic - previous.monotonic
        civil = sample.unix - previous.unix
        if delta < 0 or delta > 15 or civil < 0 or abs(civil - delta) > 2:
            raise ClockDiscontinuity("civil_clock_jump_or_suspension")
        self.previous = sample
        return delta
