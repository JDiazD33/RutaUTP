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
from .config import Config
from .gtfs import GtfsError, GtfsFeed, RouteGeometry, load_feed
from .metrics import Metrics, configure_logging
from .models import EstimatedVehicle, Observation, RejectReason
from .validation import ObservationValidator, ValidationResult

__all__ = [
    "Bridge",
    "Config",
    "EstimatedVehicle",
    "GtfsError",
    "GtfsFeed",
    "HandleOutcome",
    "Metrics",
    "Observation",
    "ObservationValidator",
    "RejectReason",
    "RouteGeometry",
    "ValidationResult",
    "VehicleAggregator",
    "configure_logging",
    "load_feed",
]

__version__ = "0.1.0"
