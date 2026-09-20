"""Contadores y registro estructurado.

El proyecto apunta a un análisis de precisión y falsos positivos, así que
interesa más *por qué* se descartó una observación que el total. Los motivos se
cuentan por separado y se pueden volcar como JSON para procesarlos después.
"""

from __future__ import annotations

import json
import logging
import time
from collections import Counter
from dataclasses import dataclass, field
from typing import Any

from .models import RejectReason

logger = logging.getLogger(__name__)


@dataclass
class Metrics:
    """Contadores acumulados del puente."""

    received: int = 0
    accepted: int = 0
    published: int = 0
    publish_attempts: int = 0
    publish_failures: int = 0
    internal_errors: int = 0
    vehicles_created: int = 0
    vehicles_expired: int = 0
    rejected: Counter[str] = field(default_factory=Counter)

    def record_received(self) -> None:
        self.received += 1

    def record_accepted(self) -> None:
        self.accepted += 1

    def record_rejected(self, reason: RejectReason) -> None:
        self.rejected[reason.value] += 1

    def record_publish_attempt(self) -> None:
        self.publish_attempts += 1

    def record_publish_failed(self) -> None:
        self.publish_failures += 1

    def record_published(self) -> None:
        self.published += 1

    def record_internal_error(self) -> None:
        """Fallo inesperado del propio servicio, no del mensaje."""
        self.internal_errors += 1

    def record_created(self) -> None:
        self.vehicles_created += 1

    def record_expired(self, count: int) -> None:
        self.vehicles_expired += count

    @property
    def rejections(self) -> int:
        return sum(self.rejected.values())

    def snapshot(self) -> dict[str, Any]:
        """Resumen serializable, con los motivos ordenados de mayor a menor."""
        return {
            "received": self.received,
            "accepted": self.accepted,
            "rejected": self.rejections,
            "publishAttempts": self.publish_attempts,
            "published": self.published,
            "publishFailures": self.publish_failures,
            "internalErrors": self.internal_errors,
            "vehiclesCreated": self.vehicles_created,
            "vehiclesExpired": self.vehicles_expired,
            "reasons": dict(self.rejected.most_common()),
        }

    def log_summary(self, extra: dict[str, Any] | None = None) -> None:
        payload = self.snapshot()

        if extra:
            payload.update(extra)

        payload["at"] = round(time.time(), 3)

        logger.info("resumen %s", json.dumps(payload, ensure_ascii=False))


class JsonFormatter(logging.Formatter):
    """Una línea JSON por registro, apta para volcar a un archivo."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "at": round(record.created, 3),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, ensure_ascii=False)


def configure_logging(level: str = "INFO", as_json: bool = True) -> None:
    """Configura el registro del proceso."""
    handler = logging.StreamHandler()

    if as_json:
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)-7s %(name)s: %(message)s")
        )

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(getattr(logging, level.upper(), logging.INFO))
