"""Punto de entrada del puente.

    python -m rutautp_backend --check      # valida el feed y sale
    python -m rutautp_backend --dry-run    # se conecta, procesa y no publica
    python -m rutautp_backend              # puente en marcha
"""

from __future__ import annotations

import argparse
import dataclasses
import logging
import sys
from pathlib import Path

from .bridge import Bridge
from .config import Config
from .gtfs import GtfsError, load_feed
from .metrics import configure_logging

logger = logging.getLogger("rutautp_backend")

# Cuántas rutas se muestran en el informe de `--check`.
CHECK_SAMPLE_SIZE = 5


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="rutautp_backend",
        description=(
            "Puente observaciones -> vehiculos del canal MQTT de RutaUTP. "
            "Valida cada observación contra el feed GTFS, agrupa las de una "
            "misma unidad y publica la posición vehicular resultante."
        ),
    )

    parser.add_argument(
        "--gtfs-dir",
        default=None,
        help="Directorio del feed GTFS (por defecto $GTFS_DIR o ./gtfs del repo)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Solo carga el feed, informa y termina. No se conecta al broker.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Se conecta y procesa, pero no publica nada en vehiculos/.",
    )
    parser.add_argument(
        "--plain-logs",
        action="store_true",
        help="Registro legible en vez de una línea JSON por evento.",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    config = Config.from_env()

    if args.gtfs_dir:
        config = dataclasses.replace(config, gtfs_dir=Path(args.gtfs_dir))

    configure_logging(config.log_level, as_json=not args.plain_logs)

    try:
        feed = load_feed(config.gtfs_dir)
    except GtfsError as error:
        logger.error("no se pudo cargar el feed: %s", error)
        return 2

    logger.info("feed cargado desde %s: %s", config.gtfs_dir, feed.summary())

    if args.check:
        return _report_feed(feed)

    bridge = Bridge(config=config, feed=feed)

    try:
        bridge.run(publish=not args.dry_run)
    except OSError as error:
        logger.error(
            "no se pudo conectar a %s:%d: %s", config.host, config.port, error
        )
        return 3

    return 0


def _report_feed(feed) -> int:
    """Informa del feed y detecta rutas inutilizables. Devuelve el código de salida."""
    for route in feed.routes_with_geometry()[:CHECK_SAMPLE_SIZE]:
        logger.info(
            "  %s línea %s (%s): %d vértices, %.1f km",
            route.route_id,
            route.linea,
            route.empresa,
            route.point_count,
            route.length_m / 1000,
        )

    unusable = [
        route.route_id for route in feed.routes.values() if route.point_count < 2
    ]

    if unusable:
        logger.warning(
            "%d ruta(s) sin geometría usable: %s",
            len(unusable),
            ", ".join(unusable[:10]),
        )

        return 0

    logger.info("todas las rutas tienen geometría usable")

    return 0


if __name__ == "__main__":
    sys.exit(main())
