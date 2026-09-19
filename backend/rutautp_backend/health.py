"""Latido y comprobación de salud del puente.

Existe para responder a una pregunta que antes no tenía respuesta: **¿el
servicio está vivo?** Y, más útil todavía, distinguir tres situaciones que se
confunden entre sí cuando solo se mira si el proceso existe:

1. El puente funciona y está conectado.
2. El puente está vivo pero **desconectado del broker** (no llega nada).
3. El puente **se murió** o dejó de ciclar.

Sin esta distinción, "no hay vehículos en el mapa" es ambiguo: puede ser que no
haya pasajeros contribuyendo —lo normal— o que el servicio esté caído.

El latido se escribe de forma atómica (temporal + `os.replace`) para que quien
lo lea nunca encuentre un JSON a medio escribir y concluya que el servicio está
roto.
"""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


def write_heartbeat(path: str, payload: dict[str, Any]) -> None:
    """Escribe el latido. Un fallo de disco no interrumpe el puente."""
    if not path.strip():
        return

    target = Path(path).expanduser()

    try:
        target.parent.mkdir(parents=True, exist_ok=True)

        temporary = target.with_name(target.name + ".tmp")
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False), encoding="utf-8"
        )

        os.replace(temporary, target)
    except OSError as error:
        logger.warning("no se pudo escribir el latido en %s: %s", target, error)


def remove_heartbeat(path: str) -> None:
    """Retira el latido. Se llama al cerrar el puente.

    Dejarlo sería peor que no tenerlo: un supervisor lo vería reciente durante
    el margen de tolerancia y creería que el servicio sigue en pie.
    """
    if not path.strip():
        return

    try:
        Path(path).expanduser().unlink(missing_ok=True)
    except OSError as error:
        logger.warning("no se pudo retirar el latido %s: %s", path, error)


def read_heartbeat(path: str) -> dict[str, Any] | None:
    """Devuelve el latido, o `None` si no existe o no es legible."""
    if not path.strip():
        return None

    try:
        raw = Path(path).expanduser().read_text(encoding="utf-8")
    except OSError:
        return None

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None

    return payload if isinstance(payload, dict) else None


def check_health(
    path: str,
    max_age_s: float,
    now: float | None = None,
) -> tuple[bool, str]:
    """Devuelve `(sano, explicación)`.

    La explicación está redactada para que sirva tal cual en el registro de un
    supervisor o en la salida de `--health-check`.
    """
    now = time.time() if now is None else now

    if not path.strip():
        return True, "comprobación de salud desactivada (BACKEND_HEALTH_FILE vacío)"

    payload = read_heartbeat(path)

    if payload is None:
        return False, (
            f"no hay latido legible en {path}: el backend no llegó a arrancar "
            "o se detuvo sin dejar rastro"
        )

    at = payload.get("at")

    # `bool` es subclase de `int`: `True` no es una marca de tiempo válida.
    if isinstance(at, bool) or not isinstance(at, (int, float)):
        return False, f"el latido de {path} no tiene marca de tiempo utilizable"

    age = now - float(at)

    if age > max_age_s:
        return False, (
            f"el último latido es de hace {age:.0f} s (máximo {max_age_s:.0f} s): "
            "el proceso está vivo pero dejó de ciclar"
        )

    if payload.get("connected") is False:
        return False, "el backend está vivo pero desconectado del broker"

    return True, f"sano: latido de hace {age:.1f} s, conectado al broker"
