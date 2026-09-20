"""Puente `observaciones` -> `vehiculos` de RutaUTP.

Los teléfonos a bordo publican observaciones anónimas de ubicación. Este
servicio las valida contra el feed GTFS, agrupa las que corresponden a una misma
unidad y publica la posición vehicular resultante, que es lo que consume el mapa
del resto de usuarios.

Ver `README.md` en la raíz de `backend/` para el modelo de confianza y el
significado de cada variable de entorno.
"""

from .aggregation import VehicleAggregator
from .bridge import Bridge, HandleOutcome
from .config import Config, ConfigError
from .gtfs import GtfsError, GtfsFeed, RouteGeometry, load_feed
from .health import check_health, read_heartbeat, remove_heartbeat, write_heartbeat
from .metrics import Metrics, configure_logging
from .models import EstimatedVehicle, Observation, RejectReason
from .persistence import ObservationStore, open_store
from .validation import ObservationValidator, ValidationResult

__all__ = [
    "Bridge",
    "Config",
    "ConfigError",
    "EstimatedVehicle",
    "GtfsError",
    "GtfsFeed",
    "HandleOutcome",
    "Metrics",
    "Observation",
    "ObservationStore",
    "ObservationValidator",
    "RejectReason",
    "RouteGeometry",
    "ValidationResult",
    "VehicleAggregator",
    "check_health",
    "configure_logging",
    "load_feed",
    "open_store",
    "read_heartbeat",
    "remove_heartbeat",
    "write_heartbeat",
]

__version__ = "0.1.0"
