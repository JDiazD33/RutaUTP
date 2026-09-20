"""Pruebas de la lectura del feed GTFS.

Se ejecutan contra el feed real del repositorio. Un feed inventado no habría
detectado lo que sí importa: que `route_short_name` trae comillas embebidas
(`C-01 "B"`) y que los recorridos deben quedar ordenados por secuencia.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from rutautp_backend.geo import haversine_m
from rutautp_backend.gtfs import (
    GtfsError,
    GtfsFeed,
    load_feed,
    parse_short_name,
)

from .conftest import SAMPLE_LINE, SAMPLE_ROUTE_ID


class TestParseShortName:
    def test_separa_linea_y_variante(self):
        assert parse_short_name('C-01 "B"') == ("C-01", "B")

    def test_variante_de_varias_letras(self):
        assert parse_short_name('C-07 "Z1"') == ("C-07", "Z1")

    def test_sin_comillas_no_hay_variante(self):
        assert parse_short_name("M-07") == ("M-07", "")

    def test_espacios_sobrantes(self):
        assert parse_short_name('  C-01  "B"  ') == ("C-01", "B")

    def test_cadena_vacia(self):
        assert parse_short_name("") == ("", "")

    def test_comilla_sin_cierre(self):
        linea, variante = parse_short_name('C-01 "B')

        assert linea == "C-01"
        assert variante == "B"


class TestLoadFeed:
    def test_carga_todas_las_rutas_del_feed(self, feed: GtfsFeed):
        assert feed.route_count > 90

    def test_todas_las_rutas_tienen_geometria_usable(self, feed: GtfsFeed):
        """El feed de Trujillo trae shape para cada ruta.

        Si alguna se quedara sin geometría, el servidor rechazaría todas sus
        observaciones con `UNKNOWN_ROUTE`, así que conviene detectarlo aquí.
        """
        sin_geometria = [
            route.route_id for route in feed.routes.values() if route.point_count < 2
        ]

        assert sin_geometria == []

    def test_la_ruta_de_referencia_esta_y_tiene_la_linea_esperada(
        self, sample_route
    ):
        assert sample_route.route_id == SAMPLE_ROUTE_ID
        assert sample_route.linea == SAMPLE_LINE

    def test_la_empresa_se_resuelve_desde_agency(self, sample_route):
        assert sample_route.empresa
        assert sample_route.empresa != "Transporte Trujillo"

    def test_los_recorridos_estan_ordenados_por_secuencia(self, feed: GtfsFeed):
        """Vértices consecutivos deben estar cerca.

        `shapes.txt` no garantiza el orden de las filas; si no se ordenara por
        `shape_pt_sequence`, el recorrido saldría en zigzag y las distancias
        contra el shape no significarían nada.
        """
        for route in feed.routes_with_geometry():
            for index in range(len(route.shape) - 1):
                distance = haversine_m(*route.shape[index], *route.shape[index + 1])

                assert distance < 2000, (
                    f"{route.route_id} salta {distance:.0f} m entre los vértices "
                    f"{index} y {index + 1}"
                )

    def test_la_longitud_del_recorrido_es_plausible(self, sample_route):
        # Una línea urbana de Trujillo: ni 100 m ni 500 km.
        assert 1_000 < sample_route.length_m < 200_000

    def test_ruta_desconocida_devuelve_none(self, feed: GtfsFeed):
        assert feed.get("no-existe") is None

    def test_el_resumen_menciona_rutas_y_vertices(self, feed: GtfsFeed):
        resumen = feed.summary()

        assert "rutas" in resumen
        assert "vértices" in resumen


class TestErrores:
    def test_directorio_inexistente(self, tmp_path: Path):
        with pytest.raises(GtfsError, match="No existe el directorio"):
            load_feed(tmp_path / "no-existe")

    def test_faltan_archivos_esenciales(self, tmp_path: Path):
        (tmp_path / "routes.txt").write_text("route_id\n", encoding="utf-8")

        with pytest.raises(GtfsError, match="Faltan archivos"):
            load_feed(tmp_path)

    def test_archivo_que_no_es_directorio(self, tmp_path: Path):
        archivo = tmp_path / "gtfs.txt"
        archivo.write_text("nada", encoding="utf-8")

        with pytest.raises(GtfsError):
            load_feed(archivo)
