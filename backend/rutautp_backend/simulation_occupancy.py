"""Guion de ocupación v1. No mide pasajeros ni emite votos comunitarios."""
from __future__ import annotations

import hashlib
import math
from .simulation_models import DataOrigin, SourceContext

SCRIPT_VERSION = 1
STATES = ("empty", "space", "full")


def scenario_occupancy(source: SourceContext, vehicle_id: str, timestamp: float) -> str:
    if (source.origin is not DataOrigin.SIMULATED
            or not vehicle_id.startswith(f"sim:{source.run_id}:")
            or not math.isfinite(timestamp) or timestamp < 0):
        raise ValueError("ocupación de escenario requiere vehículo/run sintético vigente")
    # Variación por unidad estable entre mensajes, en ciclos de cinco minutos.
    # Las horas punta de Lima desplazan la mezcla hacia unidades más ocupadas.
    salt = int.from_bytes(hashlib.sha256(vehicle_id.encode()).digest()[:4], "big")
    local_seconds = timestamp - 5 * 3600
    hour = int(local_seconds // 3600) % 24
    phase = (int(local_seconds // 300) + salt) % 6
    pattern = ("space", "full", "full", "space", "empty", "space") if hour in (
        7, 8, 17, 18, 19
    ) else ("empty", "space", "full", "space", "empty", "space")
    return pattern[phase]
