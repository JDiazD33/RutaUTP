"""Guion de ocupación v1. No mide pasajeros ni emite votos comunitarios.

La mezcla sigue una curva de demanda por hora de Lima, pensada para que una
presentación encendida a cualquier hora se vea razonable: arranque desde las
06:00, punta universitaria de 07:00 a 09:00 (clases de 8 y 9), valle a media
mañana, pico del mediodía, tarde alta hasta las 18:00 y descenso gradual desde
las 19:00, sin caída brusca. Es un guion de demostración, no demanda ni
capacidad medidas.
"""
from __future__ import annotations

import hashlib
import math
from .simulation_models import DataOrigin, SourceContext

SCRIPT_VERSION = 1
STATES = ("empty", "space", "full")
SLOT_SECONDS = 300
# Perú no aplica horario de verano: la hora de Lima es siempre UTC−5. Así el
# guion no depende de la base IANA en cada posición publicada.
LIMA_UTC_OFFSET_SECONDS = -5 * 3600

# (hora local de Lima, demanda de 0 a 1). Entre dos puntos se interpola de forma
# lineal para que la ocupación suba y baje poco a poco, sin escalones horarios.
DEMAND_CURVE = (
    (0, 0.05),
    (5, 0.10),
    (6, 0.50),   # empiezan a salir los primeros universitarios
    (7, 0.88),
    (8, 1.00),   # punta de la mañana: clases de 8:00
    (9, 0.92),   # clases de 9:00
    (10, 0.62),  # valle de media mañana
    (11, 0.70),
    (12, 0.95),  # pico del mediodía
    (13, 1.00),
    (14, 0.92),
    (15, 0.78),
    (16, 0.88),  # tarde alta
    (17, 0.92),
    (18, 0.95),  # salida de clases y del trabajo
    (19, 0.82),  # desde aquí baja de forma gradual
    (20, 0.66),
    (21, 0.52),
    (22, 0.38),
    (23, 0.20),
    (24, 0.05),
)
# Carga de un micro = demanda + sesgo propio + variación del bloque de cinco
# minutos. Por debajo de EMPTY_BELOW está vacío; desde FULL_FROM, lleno.
EMPTY_BELOW, FULL_FROM = 0.40, 0.88
VEHICLE_SPREAD, SLOT_SPREAD = 0.15, 0.12


def demand_at(timestamp: float) -> float:
    """Demanda de 0 a 1 de la curva para la hora de Lima de ese timestamp."""
    if not math.isfinite(timestamp):
        raise ValueError("la fecha debe ser finita")
    hour = ((timestamp + LIMA_UTC_OFFSET_SECONDS) % 86400) / 3600
    for (start, low), (end, high) in zip(DEMAND_CURVE, DEMAND_CURVE[1:]):
        if hour < end:
            return low + (high - low) * (hour - start) / (end - start)
    return DEMAND_CURVE[-1][1]


def demand_label(timestamp: float) -> str:
    """Nivel legible de la curva para la terminal de la presentación."""
    demand = demand_at(timestamp)
    return "alta" if demand >= 0.85 else ("media" if demand >= 0.6 else "baja")


def _unit(label: str) -> float:
    """Valor estable en [-1, 1) derivado de SHA-256, igual en cada proceso."""
    return int.from_bytes(hashlib.sha256(label.encode()).digest()[:4], "big") / 2**31 - 1


def scenario_occupancy(source: SourceContext, vehicle_id: str, timestamp: float) -> str:
    if (source.origin is not DataOrigin.SIMULATED
            or not vehicle_id.startswith(f"sim:{source.run_id}:")
            or not math.isfinite(timestamp) or timestamp < 0):
        raise ValueError("ocupación de escenario requiere vehículo/run sintético vigente")
    # El estado no cambia dentro de un bloque de cinco minutos. Cada micro
    # conserva un sesgo propio durante el run (unas unidades van más llenas) y
    # suma una variación pequeña por bloque. Entre bloques contiguos la carga
    # cambia menos que la distancia entre umbrales, así que un micro no pasa de
    # vacío a lleno sin mostrar antes «con espacio».
    slot = int(timestamp // SLOT_SECONDS)
    load = (demand_at(slot * SLOT_SECONDS)
            + VEHICLE_SPREAD * _unit(f"bias:{vehicle_id}")
            + SLOT_SPREAD * _unit(f"slot:{vehicle_id}:{slot}"))
    if load < EMPTY_BELOW:
        return "empty"
    return "full" if load >= FULL_FROM else "space"
