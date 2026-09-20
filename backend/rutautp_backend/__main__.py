"""Punto de entrada del puente.

    python -m rutautp_backend --check         # valida el feed y sale
    python -m rutautp_backend --health-check  # ¿sigue vivo el puente?
    python -m rutautp_backend --dry-run       # se conecta, procesa y no publica
    python -m rutautp_backend                 # puente en marcha
"""

from __future__ import annotations

import argparse
import dataclasses
import logging
import sys
from pathlib import Path

from .bridge import Bridge
from .config import Config, ConfigError
from .gtfs import GtfsError, load_feed
from .health import check_health
from .metrics import configure_logging

logger = logging.getLogger("rutautp_backend")

# Cuántas rutas se muestran en el informe de `--check`.
CHECK_SAMPLE_SIZE = 5

# Códigos de salida del proceso.
#
# Están juntos y con nombre para que un supervisor pueda distinguir el motivo
# sin leer el código. `--check` los usa: antes devolvía 0 pasara lo que pasara,
# así que como comprobación automática no servía para fallar.
EXIT_OK = 0
EXIT_UNHEALTHY = 1
EXIT_CONFIG = 2
EXIT_CONNECTION = 3
#: El feed se cargó, pero hay rutas sin geometría utilizable. El servicio
#: rechazaría **todas** sus observaciones con `UNKNOWN_ROUTE`, así que no es un
#: arranque sano y conviene que la comprobación lo diga.
EXIT_FEED_UNUSABLE = 4


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
        help=(
            "Solo carga el feed, informa y termina. No se conecta al broker. "
            f"Devuelve {EXIT_OK} si todas las rutas tienen geometría y "
            f"{EXIT_FEED_UNUSABLE} si alguna no la tiene."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Se conecta y procesa, pero no publica nada en vehiculos/.",
    )
    parser.add_argument(
        "--health-check",
        action="store_true",
        help=(
            "Lee el latido que deja el puente en marcha y termina: 0 si está "
            "sano, 1 si no. Para supervisores (systemd, Docker, cron)."
        ),
    )
    parser.add_argument(
        "--plain-logs",
        action="store_true",
        help="Registro legible en vez de una línea JSON por evento.",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        config = Config.from_env()
    except ConfigError as error:
        # Sin registro configurado todavía: el mensaje va directo a stderr.
        print(f"configuración inválida: {error}", file=sys.stderr)
        return EXIT_CONFIG

    if args.gtfs_dir:
        config = dataclasses.replace(config, gtfs_dir=Path(args.gtfs_dir))

    configure_logging(config.log_level, as_json=not args.plain_logs)

    # La comprobación de salud no necesita el feed: si el broker o el disco
    # fallan, el informe tiene que salir igual. Por eso va antes de cargarlo.
    if args.health_check:
        return _report_health(config)

    try:
        feed = load_feed(config.gtfs_dir)
    except GtfsError as error:
        logger.error("no se pudo cargar el feed: %s", error)
        return EXIT_CONFIG

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
        return EXIT_CONNECTION

    return EXIT_OK


def _report_health(config: Config) -> int:
    """Informa del estado del puente. Devuelve el código de salida.

    Se imprime en texto plano y no por el registro: el resultado tiene que ser
    legible tal cual en la salida de un supervisor, sin depender de que el
    registro esté en JSON o en modo legible.
    """
    healthy, detail = check_health(config.health_file, config.health_max_age_s)

    if healthy:
        print(f"salud OK: {detail}")
        return EXIT_OK

    print(f"salud FALLA: {detail}", file=sys.stderr)

    return EXIT_UNHEALTHY


def _report_feed(feed) -> int:
    """Informa del feed y detecta rutas inutilizables. Devuelve el código de salida.

    Una ruta sin geometría no es un detalle cosmético: el validador la rechaza
    con `UNKNOWN_ROUTE` en `_check_against_route`, así que **todas** las
    observaciones de esa línea se descartan. Si la comprobación devolviera 0 en
    ese caso, un supervisor no podría distinguir un feed sano de uno que deja
    líneas enteras fuera del mapa.
    """
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

        return EXIT_FEED_UNUSABLE

    logger.info("todas las rutas tienen geometría usable")

    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
