"""Pruebas de la línea de comandos (`__main__.py`).

Existen por un fallo concreto: `--check` devolvía **0 pasara lo que pasara**.
Como comprobación automática no servía para fallar, así que un feed con líneas
enteras sin geometría —cuyas observaciones se rechazan todas con
`UNKNOWN_ROUTE`— se reportaba igual que uno sano.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from rutautp_backend.__main__ import (
    EXIT_CONFIG,
    EXIT_FEED_UNUSABLE,
    EXIT_OK,
    main,
)
from rutautp_backend.metrics import Metrics
from rutautp_backend.models import RejectReason

REPO_ROOT = Path(__file__).resolve().parents[2]
GTFS_REAL = REPO_ROOT / "gtfs"

ROUTES = "route_id,route_short_name,agency_id\nA,C-01,1\nB,C-02,1\n"
TRIPS = "trip_id,route_id,shape_id\ntA,A,shapeA\ntB,B,shapeB\n"
SHAPES = (
    "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n"
    "shapeA,-8.1000,-79.0300,1\n"
    "shapeA,-8.1010,-79.0310,2\n"
    "shapeB,-8.1100,-79.0400,1\n"
    "shapeB,-8.1110,-79.0410,2\n"
)


def escribir_feed(destino: Path, *, trips: str = TRIPS) -> Path:
    """Feed mínimo pero completo: `load_feed` exige estos tres archivos."""
    destino.mkdir(parents=True, exist_ok=True)

    (destino / "routes.txt").write_text(ROUTES, encoding="utf-8")
    (destino / "trips.txt").write_text(trips, encoding="utf-8")
    (destino / "shapes.txt").write_text(SHAPES, encoding="utf-8")

    return destino


class TestCheck:
    def test_con_todas_las_rutas_con_geometria_devuelve_cero(
        self, tmp_path: Path, monkeypatch
    ):
        monkeypatch.setenv("GTFS_DIR", str(escribir_feed(tmp_path / "gtfs")))

        assert main(["--check", "--plain-logs"]) == EXIT_OK

    def test_falla_si_una_ruta_no_tiene_geometria(self, tmp_path: Path, monkeypatch):
        """El caso que motivó el cambio: antes esto devolvía 0."""
        sin_shape = "trip_id,route_id,shape_id\ntA,A,shapeA\ntB,B,\n"

        monkeypatch.setenv(
            "GTFS_DIR", str(escribir_feed(tmp_path / "gtfs", trips=sin_shape))
        )

        assert main(["--check", "--plain-logs"]) == EXIT_FEED_UNUSABLE

    def test_el_codigo_de_feed_inutilizable_no_choca_con_los_demas(self):
        """Un supervisor debe poder distinguir los motivos entre sí."""
        assert len({EXIT_OK, EXIT_CONFIG, EXIT_FEED_UNUSABLE}) == 3
        assert EXIT_OK == 0

    def test_un_feed_inexistente_devuelve_error_de_configuracion(
        self, tmp_path: Path, monkeypatch
    ):
        monkeypatch.setenv("GTFS_DIR", str(tmp_path / "no-existe"))

        assert main(["--check", "--plain-logs"]) == EXIT_CONFIG

    def test_el_feed_real_del_repositorio_pasa(self, monkeypatch):
        """Si el feed de verdad fallara la comprobación, sería un aviso, no ruido."""
        monkeypatch.setenv("GTFS_DIR", str(GTFS_REAL))

        assert main(["--check", "--plain-logs"]) == EXIT_OK


class TestSinCodigoMuerto:
    def test_los_motivos_ya_no_se_formatean_en_una_linea_suelta(self):
        """`format_reasons` se retiró por no usarse en ningún sitio.

        Se deja constancia para que no vuelva a añadirse una función que nadie
        llama: el resumen ya publica los motivos ordenados en `snapshot()`, que
        es lo que consume el registro y el volcado JSON.
        """
        assert not hasattr(Metrics(), "format_reasons")

    def test_el_resumen_sigue_trayendo_los_motivos(self):
        """Lo que sí se usa, y por lo que la función anterior sobraba."""
        metricas = Metrics()

        metricas.record_rejected(RejectReason.DUPLICATE)

        assert metricas.snapshot()["reasons"] == {"duplicate": 1}
