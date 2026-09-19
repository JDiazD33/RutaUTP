"""Pruebas de identidad de vehículo: agrupación y espacio de nombres.

Cubren D01 (continuidad sesión–vehículo) y D02 (no reutilizar identificadores
tras reiniciar). Antes, la agrupación solo miraba ruta, distancia y tiempo, y
esos tres criterios no distinguen dos unidades que se cruzan ni impiden que un
pasajero cambie de bus a mitad de viaje.
"""

from __future__ import annotations

import pytest

from rutautp_backend.aggregation import VehicleAggregator
from rutautp_backend.config import Config
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.models import Observation

from .conftest import SAMPLE_ROUTE_ID, vehicle_id

NOW = 1_700_000_000.0

#: Vértices del recorrido de referencia, con las distancias medidas sobre el
#: feed real. Los vértices NO están espaciados uniformemente (el tramo v100-v101
#: mide 184 m y el v101-v102 solo 5 m) y además el recorrido se curva, así que
#: hay que usar distancias en línea recta y no diferencias de índice: v100 y
#: v116 están a 345 m por el recorrido pero solo a 209 m en línea recta.
V_CERCA_A = 101
V_CERCA_B = 102             # 5 m en recta de V_CERCA_A
V_BASE = 100
V_OTRO_BUS = 122            # 624 m en recta de V_BASE: fuera del radio (300 m)
V_MAS_CERCA_DEL_OTRO = 121  # 530 m de V_BASE y 94 m de V_OTRO_BUS
V_LEJOS = 400


def observation_on(
    route,
    index: int,
    *,
    now: float = NOW,
    session: str = "s-1",
    heading: float | None = None,
    progress: float | None = None,
) -> Observation:
    """Observación sobre el vértice `index` del recorrido real."""
    latitude, longitude = route.shape[index]

    return Observation(
        session_id=session,
        route_id=route.route_id,
        linea=route.linea,
        lat=latitude,
        lon=longitude,
        speed=8.0,
        heading=(
            segment_bearing_deg(list(route.shape), index)
            if heading is None
            else heading
        ),
        accuracy=8.0,
        motion_activity="automotive",
        timestamp=now,
        distance_to_route_m=0.0,
        heading_diff_deg=0.0,
        progress=(
            index / (len(route.shape) - 1) if progress is None else progress
        ),
    )


@pytest.fixture
def aggregator(config: Config, feed: GtfsFeed) -> VehicleAggregator:
    return VehicleAggregator(config, feed)


class TestVinculoPorSesion:
    """Un pasajero no cambia de bus a mitad de viaje."""

    def test_la_sesion_conserva_su_vehiculo_aunque_otro_este_mas_cerca(
        self, aggregator, sample_route
    ):
        # La sesión 1 abre un vehículo en V_BASE.
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )

        # La sesión 2 abre otro a 345 m: fuera del radio de fusión.
        segundo, creado = aggregator.ingest(
            observation_on(sample_route, V_OTRO_BUS, session="s-2"), NOW
        )

        assert creado is True
        assert segundo.vehicle_id != primero.vehicle_id

        # La sesión 1 vuelve a publicar 314 m más adelante: más cerca del
        # segundo vehículo (31 m) que del suyo (314 m). Sin vínculo por sesión,
        # se fusionaría con el equivocado y el pasajero "cambiaría de bus".
        tercera, creado = aggregator.ingest(
            observation_on(
                sample_route, V_MAS_CERCA_DEL_OTRO, session="s-1", now=NOW + 30
            ),
            NOW + 30,
        )

        assert creado is False
        assert tercera.vehicle_id == primero.vehicle_id
        assert aggregator.vehicle_count == 2

    def test_el_vinculo_se_olvida_cuando_el_vehiculo_caduca(
        self, aggregator, sample_route, config
    ):
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )

        aggregator.expire(NOW + config.vehicle_ttl_s + 1)

        assert aggregator.bound_session_count == 0

        segundo, creado = aggregator.ingest(
            observation_on(
                sample_route,
                V_BASE,
                session="s-1",
                now=NOW + config.vehicle_ttl_s + 2,
            ),
            NOW + config.vehicle_ttl_s + 2,
        )

        assert creado is True
        assert segundo.vehicle_id == vehicle_id(SAMPLE_ROUTE_ID, 2)
        assert segundo.vehicle_id != primero.vehicle_id

    def test_el_vinculo_se_olvida_si_la_sesion_cambia_de_ruta(
        self, aggregator, feed, sample_route
    ):
        primera, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )

        otra = next(
            route
            for route in feed.routes_with_geometry()
            if route.route_id != sample_route.route_id
        )

        segunda, creado = aggregator.ingest(
            observation_on(otra, V_BASE, session="s-1", now=NOW + 1), NOW + 1
        )

        assert creado is True
        assert segunda.vehicle_id != primera.vehicle_id


class TestCoherenciaFisica:
    def test_rumbos_opuestos_no_se_fusionan(self, aggregator, sample_route):
        """Dos buses que se cruzan van a metros y en sentidos contrarios."""
        bearing = segment_bearing_deg(list(sample_route.shape), 100)

        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="ida", heading=bearing), NOW
        )

        segundo, creado = aggregator.ingest(
            observation_on(
                sample_route,
                V_BASE,
                session="vuelta",
                now=NOW + 1,
                heading=(bearing + 180) % 360,
            ),
            NOW + 1,
        )

        assert creado is True
        assert segundo.vehicle_id != primero.vehicle_id
        assert aggregator.vehicle_count == 2

    def test_un_desplazamiento_imposible_no_se_fusiona(
        self, aggregator, sample_route
    ):
        """17 km en un segundo no los hace ningún vehículo urbano."""
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )

        segundo, creado = aggregator.ingest(
            observation_on(sample_route, V_LEJOS, session="s-2", now=NOW + 1), NOW + 1
        )

        assert creado is True
        assert segundo.vehicle_id != primero.vehicle_id

    def test_un_desplazamiento_posible_si_se_fusiona(
        self, aggregator, sample_route
    ):
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_CERCA_A, session="s-1"), NOW
        )

        segundo, creado = aggregator.ingest(
            observation_on(sample_route, V_CERCA_B, session="s-2", now=NOW + 1), NOW + 1
        )

        assert creado is False
        assert segundo.vehicle_id == primero.vehicle_id

    def test_un_avance_incoherente_sobre_el_recorrido_no_se_fusiona(
        self, aggregator, sample_route
    ):
        """El avance sobre el trazado distingue lo que la distancia no puede.

        Dos lecturas pueden estar a metros —incluso en el mismo punto— y ser de
        unidades distintas si el recorrido pasa dos veces por el mismo sitio.
        Se fuerzan los `progress` para reproducir ese caso: el mismo punto con
        un 80 % del recorrido de diferencia son 27 km, imposibles en 5 s.
        """
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="s-1", progress=0.10),
            NOW,
        )

        segundo, creado = aggregator.ingest(
            observation_on(
                sample_route,
                V_BASE,
                session="s-2",
                now=NOW + 5,
                progress=0.90,
            ),
            NOW + 5,
        )

        assert creado is True
        assert segundo.vehicle_id != primero.vehicle_id
        assert aggregator.vehicle_count == 2

    def test_un_avance_normal_sobre_el_recorrido_si_se_fusiona(
        self, aggregator, sample_route
    ):
        """El avance coherente con el tiempo no debe estorbar."""
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_CERCA_A, session="s-1"), NOW
        )

        segundo, creado = aggregator.ingest(
            observation_on(sample_route, V_CERCA_B, session="s-2", now=NOW + 5),
            NOW + 5,
        )

        assert creado is False
        assert segundo.vehicle_id == primero.vehicle_id

    def test_sin_feed_no_se_comprueba_el_avance(self, config, sample_route):
        """Sin longitud de recorrido la comprobación se omite, no se inventa."""
        sin_feed = VehicleAggregator(config)

        primero, _ = sin_feed.ingest(
            observation_on(sample_route, V_BASE, session="s-1", progress=0.10),
            NOW,
        )

        segundo, creado = sin_feed.ingest(
            observation_on(
                sample_route,
                V_BASE,
                session="s-2",
                now=NOW + 5,
                progress=0.90,
            ),
            NOW + 5,
        )

        assert primero.route_length_m == 0.0
        assert creado is False

    def test_rumbo_desconocido_no_impide_la_fusion(self, aggregator, sample_route):
        """`-1` es un valor legítimo con el vehículo parado, no una señal."""
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_CERCA_A, session="s-1"), NOW
        )

        segundo, creado = aggregator.ingest(
            observation_on(
                sample_route,
                V_CERCA_B, session="s-2", now=NOW + 1, heading=-1
            ),
            NOW + 1,
        )

        assert creado is False
        assert segundo.vehicle_id == primero.vehicle_id


class TestEspacioDeNombres:
    """D02: los ordinales se pierden al reiniciar, así que no deben coincidir."""

    def test_dos_arranques_no_producen_el_mismo_identificador(
        self, feed, sample_route
    ):
        base = dict(
            gtfs_dir=feed.source_dir, database_path="", health_file=""
        )

        primero = VehicleAggregator(Config(**base))
        segundo = VehicleAggregator(Config(**base))

        id_primero, _ = primero.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )
        id_segundo, _ = segundo.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )

        assert id_primero.vehicle_id != id_segundo.vehicle_id
        assert primero.namespace != segundo.namespace

    def test_el_espacio_de_nombres_se_puede_fijar(self, aggregator, sample_route):
        """Reproducibilidad en pruebas y despliegues que quieran identificadores estables."""
        assert aggregator.namespace == "t0"

        vehiculo, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE), NOW
        )

        assert vehiculo.vehicle_id == vehicle_id(SAMPLE_ROUTE_ID, 1)

    def test_el_identificador_conserva_la_ruta_delante(self, aggregator, sample_route):
        """Se lee en el tópico y en el registro: conviene que siga siendo legible."""
        vehiculo, _ = aggregator.ingest(observation_on(sample_route, V_BASE), NOW)

        assert vehiculo.vehicle_id.startswith(f"{SAMPLE_ROUTE_ID}-")

    def test_el_ordinal_no_se_reutiliza_dentro_del_arranque(
        self, aggregator, sample_route, config
    ):
        primero, _ = aggregator.ingest(
            observation_on(sample_route, V_BASE, session="s-1"), NOW
        )
        aggregator.expire(NOW + config.vehicle_ttl_s + 1)

        segundo, _ = aggregator.ingest(
            observation_on(
                sample_route,
                V_BASE,
                session="s-2",
                now=NOW + config.vehicle_ttl_s + 2,
            ),
            NOW + config.vehicle_ttl_s + 2,
        )

        assert segundo.vehicle_id == vehicle_id(SAMPLE_ROUTE_ID, 2)
        assert segundo.vehicle_id != primero.vehicle_id
