"""Pruebas de la geometría.

Los valores esperados se calculan con propiedades geométricas conocidas, no
copiando la salida de la implementación: si se copiara, la prueba pasaría
siempre aunque la fórmula estuviera mal.
"""

from __future__ import annotations

import math

import pytest

from rutautp_backend.geo import (
    bearing_deg,
    closest_point_on_segment,
    decimate,
    haversine_m,
    heading_difference_deg,
    is_valid_coordinate,
    match_point_to_polyline,
    sanitize_heading,
    sanitize_speed,
    segment_bearing_deg,
)

# Un grado de latitud sobre una esfera de radio 6371 km: R * pi/180.
# Ojo: NO es 111 320, que es la constante del plano local que usa
# `closest_point_on_segment`. Confundirlas es el error clásico aquí.
METERS_PER_DEGREE_LAT = math.pi * 6_371_000.0 / 180.0


class TestHaversine:
    def test_mismo_punto_da_cero(self):
        assert haversine_m(-8.1, -79.03, -8.1, -79.03) == 0.0

    def test_un_grado_de_latitud(self):
        distance = haversine_m(0.0, 0.0, 1.0, 0.0)

        assert distance == pytest.approx(METERS_PER_DEGREE_LAT, rel=0.001)

    def test_mil_grados_de_latitud_son_unos_111_metros(self):
        distance = haversine_m(-8.1, -79.03, -8.101, -79.03)

        assert distance == pytest.approx(111.32, rel=0.01)

    def test_es_simetrica(self):
        a = haversine_m(-8.09, -79.04, -8.12, -79.02)
        b = haversine_m(-8.12, -79.02, -8.09, -79.04)

        assert a == pytest.approx(b, rel=1e-12)


class TestClosestPointOnSegment:
    def test_punto_sobre_el_segmento_da_distancia_cero(self):
        _, _, distance, _, _ = closest_point_on_segment(
            -8.10, -79.030, -8.10, -79.040, -8.10, -79.020
        )

        assert distance == pytest.approx(0.0, abs=0.01)

    def test_punto_perpendicular_a_la_mitad(self):
        # 111.32 m al norte de la mitad del segmento.
        _, _, distance, _, _ = closest_point_on_segment(
            -8.099, -79.030, -8.10, -79.040, -8.10, -79.020
        )

        assert distance == pytest.approx(111.32, rel=0.02)

    def test_la_proyeccion_se_acota_al_extremo_mas_cercano(self):
        # Muy al oeste del extremo inicial: la proyección cae en el extremo.
        snapped_lat, snapped_lon, distance, along, _ = closest_point_on_segment(
            -8.10, -79.100, -8.10, -79.040, -8.10, -79.020
        )

        assert snapped_lon == pytest.approx(-79.040, abs=1e-6)
        assert along == 0.0
        assert distance > 6000

    def test_segmento_degenerado_no_divide_por_cero(self):
        snapped_lat, snapped_lon, distance, along, length = closest_point_on_segment(
            -8.10, -79.030, -8.10, -79.030, -8.10, -79.030
        )

        assert (snapped_lat, snapped_lon) == (-8.10, -79.030)
        assert distance == 0.0
        assert (along, length) == (0.0, 0.0)


class TestMatchPointToPolyline:
    # Rectángulo sencillo: 0.01 grados hacia el este por la latitud -8.10.
    POLYLINE = [(-8.10, -79.04), (-8.10, -79.03), (-8.10, -79.02)]

    def test_polilinea_corta_devuelve_none(self):
        assert match_point_to_polyline(-8.10, -79.03, []) is None
        assert match_point_to_polyline(-8.10, -79.03, [(-8.10, -79.03)]) is None

    def test_punto_sobre_la_linea_esta_en_ruta(self):
        match = match_point_to_polyline(-8.10, -79.035, self.POLYLINE)

        assert match is not None
        assert match.distance_m == pytest.approx(0.0, abs=0.5)
        assert match.is_on_route is True

    def test_punto_lejano_no_esta_en_ruta_pero_si_se_informa_la_distancia(self):
        match = match_point_to_polyline(-8.12, -79.03, self.POLYLINE)

        assert match is not None
        assert match.distance_m > 2000
        assert match.is_on_route is False

    def test_el_umbral_no_filtra_el_resultado(self):
        """El umbral solo se informa en `is_on_route`.

        Es la diferencia deliberada con el cliente, donde se pasa un umbral que
        nunca se usa para filtrar y la consecuencia pasó desapercibida.
        """
        cerca = match_point_to_polyline(-8.10, -79.03, self.POLYLINE, threshold_m=10)
        lejos = match_point_to_polyline(-8.12, -79.03, self.POLYLINE, threshold_m=10)

        assert cerca is not None and lejos is not None
        assert cerca.is_on_route is True
        assert lejos.is_on_route is False

    def test_el_progreso_avanza_a_lo_largo_del_recorrido(self):
        inicio = match_point_to_polyline(-8.10, -79.039, self.POLYLINE)
        medio = match_point_to_polyline(-8.10, -79.030, self.POLYLINE)
        final = match_point_to_polyline(-8.10, -79.021, self.POLYLINE)

        assert inicio.progress < medio.progress < final.progress
        assert inicio.progress == pytest.approx(0.05, abs=0.02)
        assert final.progress == pytest.approx(0.95, abs=0.02)

    def test_identifica_el_segmento_correcto(self):
        primero = match_point_to_polyline(-8.10, -79.035, self.POLYLINE)
        segundo = match_point_to_polyline(-8.10, -79.025, self.POLYLINE)

        assert primero.segment_index == 0
        assert segundo.segment_index == 1


class TestBearing:
    def test_hacia_el_este_son_90_grados(self):
        # No son 90.000 exactos: una línea de latitud constante no es una
        # geodésica, así que el rumbo inicial se desvía unas milésimas.
        bearing = bearing_deg(-8.10, -79.04, -8.10, -79.03)

        assert bearing == pytest.approx(90.0, abs=0.01)

    def test_hacia_el_norte_son_0_grados(self):
        bearing = bearing_deg(-8.10, -79.03, -8.09, -79.03)

        assert bearing == pytest.approx(0.0, abs=0.5) or bearing == pytest.approx(
            360.0, abs=0.5
        )

    def test_hacia_el_sur_son_180_grados(self):
        assert bearing_deg(-8.09, -79.03, -8.10, -79.03) == pytest.approx(180.0)

    def test_siempre_dentro_de_cero_y_trescientos_sesenta(self):
        for lat, lon in [(-8.09, -79.02), (-8.11, -79.04), (-8.10, -79.05)]:
            bearing = bearing_deg(-8.10, -79.03, lat, lon)

            assert 0.0 <= bearing < 360.0

    def test_rumbo_del_segmento_usa_los_vertices_correctos(self):
        polyline = [(-8.10, -79.04), (-8.10, -79.03), (-8.09, -79.03)]

        assert segment_bearing_deg(polyline, 0) == pytest.approx(90.0, abs=0.01)
        assert segment_bearing_deg(polyline, 1) == pytest.approx(0.0, abs=0.5)

    def test_indice_fuera_de_rango_devuelve_cero(self):
        polyline = [(-8.10, -79.04), (-8.10, -79.03)]

        assert segment_bearing_deg(polyline, -1) == 0.0
        assert segment_bearing_deg(polyline, 5) == 0.0


class TestHeadingDifference:
    def test_mismo_rumbo(self):
        assert heading_difference_deg(90, 90) == pytest.approx(0.0)

    def test_rumbo_opuesto(self):
        assert heading_difference_deg(90, 270) == pytest.approx(180.0)

    def test_toma_el_angulo_menor_al_cruzar_el_norte(self):
        # 350 y 10 distan 20 grados, no 340.
        assert heading_difference_deg(350, 10) == pytest.approx(20.0)
        assert heading_difference_deg(10, 350) == pytest.approx(20.0)

    def test_rumbo_desconocido_cuenta_como_no_alineado(self):
        assert heading_difference_deg(-1, 90) == pytest.approx(180.0)

    def test_rumbo_no_finito_cuenta_como_no_alineado(self):
        assert heading_difference_deg(math.nan, 90) == pytest.approx(180.0)


class TestSanitizacion:
    def test_velocidad_desconocida_se_normaliza(self):
        assert sanitize_speed(math.nan) == -1.0
        assert sanitize_speed(math.inf) == -1.0
        assert sanitize_speed(-5) == -1.0

    def test_velocidad_absurda_se_acota(self):
        assert sanitize_speed(500) == 100.0

    def test_velocidad_normal_pasa_intacta(self):
        assert sanitize_speed(8.5) == pytest.approx(8.5)

    def test_rumbo_desconocido(self):
        assert sanitize_heading(-1) == -1.0
        assert sanitize_heading(math.nan) == -1.0

    def test_rumbo_se_normaliza_al_rango(self):
        assert sanitize_heading(370) == pytest.approx(10.0)
        assert sanitize_heading(0) == pytest.approx(0.0)

    def test_coordenadas_validas(self):
        assert is_valid_coordinate(-8.1, -79.03) is True
        assert is_valid_coordinate(90, 180) is True

    def test_coordenadas_invalidas(self):
        assert is_valid_coordinate(91, -79.03) is False
        assert is_valid_coordinate(-8.1, 181) is False
        assert is_valid_coordinate(math.nan, -79.03) is False
        assert is_valid_coordinate(-8.1, math.inf) is False


class TestDecimate:
    def test_lista_corta_no_se_toca(self):
        puntos = [(-8.1, -79.04), (-8.1, -79.03)]

        assert decimate(puntos, 10) == puntos

    def test_reduce_la_cantidad(self):
        puntos = [(-8.1 - index * 0.0001, -79.03) for index in range(1000)]

        assert len(decimate(puntos, 50)) == 50

    def test_conserva_el_ultimo_punto(self):
        puntos = [(-8.1 - index * 0.0001, -79.03) for index in range(1000)]

        assert decimate(puntos, 50)[-1] == puntos[-1]
