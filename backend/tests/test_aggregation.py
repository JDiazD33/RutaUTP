"""Pruebas de la agregación de observaciones en vehículos.

Lo que se comprueba aquí es la parte que el teléfono no puede hacer: decidir
cuándo varias observaciones anónimas pertenecen a la misma unidad.
"""

from __future__ import annotations

import pytest

from rutautp_backend.aggregation import VehicleAggregator
from rutautp_backend.config import Config
from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.models import Observation

from .conftest import SAMPLE_ROUTE_ID, offset_meters

NOW = 1_700_000_000.0


def make_observation(
    route,
    *,
    now: float = NOW,
    session: str = "session-0001",
    progress: float = 0.5,
    offset_north_m: float = 0.0,
    offset_east_m: float = 0.0,
    speed: float = 8.0,
) -> Observation:
    """Observación sobre el recorrido, opcionalmente desplazada."""
    index = min(int(progress * (len(route.shape) - 1)), len(route.shape) - 2)
    latitude, longitude = route.shape[index]

    latitude, longitude = offset_meters(
        latitude, longitude, north_m=offset_north_m, east_m=offset_east_m
    )

    return Observation(
        session_id=session,
        route_id=route.route_id,
        linea=route.linea,
        lat=latitude,
        lon=longitude,
        speed=speed,
        heading=segment_bearing_deg(list(route.shape), index),
        accuracy=8.0,
        motion_activity="automotive",
        timestamp=now,
        distance_to_route_m=0.0,
        heading_diff_deg=0.0,
        progress=progress,
    )


@pytest.fixture
def aggregator(config: Config) -> VehicleAggregator:
    return VehicleAggregator(config)


class TestCreacion:
    def test_la_primera_observacion_crea_un_vehiculo(self, aggregator, sample_route):
        vehicle, created = aggregator.ingest(make_observation(sample_route), NOW)

        assert created is True
        assert aggregator.vehicle_count == 1
        assert vehicle.linea == sample_route.linea

    def test_el_identificador_lo_deriva_el_servidor(self, aggregator, sample_route):
        """Nunca se toma del mensaje del cliente.

        Si se aceptara un identificador enviado por el teléfono, cualquiera con
        credenciales válidas podría suplantar a un vehículo ante los demás.
        """
        vehicle, _ = aggregator.ingest(make_observation(sample_route), NOW)

        assert vehicle.vehicle_id == f"{SAMPLE_ROUTE_ID}-01"
        assert "session-0001" not in vehicle.vehicle_id

    def test_dos_sesiones_lejanas_son_dos_vehiculos(self, aggregator, sample_route):
        aggregator.ingest(make_observation(sample_route), NOW)

        # 5 km al norte: fuera del radio de fusión.
        vehicle, created = aggregator.ingest(
            make_observation(sample_route, session="session-0002", offset_north_m=5000),
            NOW + 1,
        )

        assert created is True
        assert vehicle.vehicle_id == f"{SAMPLE_ROUTE_ID}-02"
        assert aggregator.vehicle_count == 2


class TestFusion:
    def test_dos_pasajeros_del_mismo_bus_son_un_vehiculo(
        self, aggregator, sample_route
    ):
        first, _ = aggregator.ingest(make_observation(sample_route), NOW)

        second, created = aggregator.ingest(
            make_observation(
                sample_route, session="session-0002", offset_north_m=50
            ),
            NOW + 5,
        )

        assert created is False
        assert second.vehicle_id == first.vehicle_id
        assert aggregator.vehicle_count == 1

    def test_se_acumulan_las_sesiones(self, aggregator, sample_route):
        for index in range(4):
            aggregator.ingest(
                make_observation(
                    sample_route,
                    session=f"session-{index:04d}",
                    offset_north_m=index * 10,
                ),
                NOW + index,
            )

        vehicle = aggregator.snapshot()[0]

        assert len(vehicle.sessions) == 4
        assert vehicle.sample_count == 4

    def test_mas_alla_del_radio_no_se_fusiona(self, aggregator, sample_route):
        aggregator.ingest(make_observation(sample_route), NOW)

        _, created = aggregator.ingest(
            make_observation(sample_route, offset_north_m=1500), NOW + 5
        )

        assert created is True

    def test_mas_alla_de_la_ventana_temporal_no_se_fusiona(
        self, aggregator, sample_route, config
    ):
        aggregator.ingest(make_observation(sample_route), NOW)

        _, created = aggregator.ingest(
            make_observation(sample_route),
            NOW + config.merge_window_s + 1,
        )

        assert created is True

    def test_rutas_distintas_nunca_se_fusionan(self, aggregator, feed, sample_route):
        otra = next(
            route
            for route in feed.routes_with_geometry()
            if route.route_id != sample_route.route_id
        )

        aggregator.ingest(make_observation(sample_route), NOW)

        _, created = aggregator.ingest(make_observation(otra), NOW + 1)

        assert created is True
        assert aggregator.vehicle_count == 2


class TestPosicion:
    # Pasos de progreso deliberadamente pequeños: el radio de fusión son 300 m
    # y este recorrido mide 34 km, así que un salto de 0.01 serían 340 m y
    # crearía un vehículo distinto.
    AVANCE_CORTO = 0.005

    def test_la_posicion_sigue_a_la_observacion_mas_reciente(
        self, aggregator, sample_route
    ):
        first, _ = aggregator.ingest(
            make_observation(sample_route, now=NOW, progress=0.2), NOW
        )
        lat_inicial = first.lat

        vehicle, created = aggregator.ingest(
            make_observation(
                sample_route, now=NOW + 5, progress=0.2 + self.AVANCE_CORTO
            ),
            NOW + 5,
        )

        assert created is False, "debería fusionarse: son 170 m de diferencia"
        assert vehicle.lat != lat_inicial
        assert vehicle.timestamp == NOW + 5

    def test_una_observacion_vieja_no_mueve_el_vehiculo_hacia_atras(
        self, aggregator, sample_route
    ):
        """Los mensajes pueden llegar desordenados por la red."""
        aggregator.ingest(
            make_observation(sample_route, now=NOW + 10, progress=0.5), NOW + 10
        )

        vehicle, _ = aggregator.ingest(
            make_observation(
                sample_route, now=NOW, progress=0.5 + self.AVANCE_CORTO
            ),
            NOW,
        )

        assert vehicle.timestamp == NOW + 10

    def test_last_seen_no_retrocede(self, aggregator, sample_route):
        aggregator.ingest(
            make_observation(sample_route, now=NOW + 10), NOW + 10
        )

        vehicle, _ = aggregator.ingest(make_observation(sample_route, now=NOW), NOW)

        assert vehicle.last_seen == NOW + 10


class TestCaducidad:
    def test_el_vehiculo_caduca_al_superar_el_ttl(
        self, aggregator, sample_route, config
    ):
        aggregator.ingest(make_observation(sample_route), NOW)

        assert aggregator.expire(NOW + config.vehicle_ttl_s - 1) == []
        assert aggregator.vehicle_count == 1

        expired = aggregator.expire(NOW + config.vehicle_ttl_s + 1)

        assert expired == [f"{SAMPLE_ROUTE_ID}-01"]
        assert aggregator.vehicle_count == 0

    def test_una_rafaga_de_mensajes_viejos_no_mantiene_vivo_el_vehiculo(
        self, aggregator, sample_route, config
    ):
        """El TTL se mide contra la marca de tiempo, no contra el procesamiento."""
        aggregator.ingest(make_observation(sample_route), NOW)

        # Llegan más mensajes, pero con la misma marca de tiempo antigua.
        for index in range(5):
            aggregator.ingest(
                make_observation(sample_route, session=f"sesion-{index}"), NOW
            )

        expired = aggregator.expire(NOW + config.vehicle_ttl_s + 1)

        assert len(expired) == 1

    def test_el_ordinal_no_se_reutiliza(self, aggregator, sample_route, config):
        """Reutilizar el identificador haría saltar el marcador en el mapa."""
        aggregator.ingest(make_observation(sample_route), NOW)
        aggregator.expire(NOW + config.vehicle_ttl_s + 1)

        vehicle, _ = aggregator.ingest(
            make_observation(sample_route), NOW + config.vehicle_ttl_s + 2
        )

        assert vehicle.vehicle_id == f"{SAMPLE_ROUTE_ID}-02"


class TestRitmoDePublicacion:
    def test_publica_la_primera_vez(self, aggregator, sample_route):
        vehicle, _ = aggregator.ingest(make_observation(sample_route), NOW)

        assert aggregator.should_publish(vehicle, NOW) is True

    def test_no_publica_dentro_del_intervalo(
        self, aggregator, sample_route, config
    ):
        vehicle, _ = aggregator.ingest(make_observation(sample_route), NOW)

        aggregator.mark_published(vehicle, NOW)

        assert aggregator.should_publish(vehicle, NOW + 1) is False

    def test_vuelve_a_publicar_pasado_el_intervalo(
        self, aggregator, sample_route, config
    ):
        vehicle, _ = aggregator.ingest(make_observation(sample_route), NOW)

        aggregator.mark_published(vehicle, NOW)

        assert aggregator.should_publish(vehicle, NOW + config.publish_interval_s) is True


class TestInstantanea:
    def test_la_instantanea_esta_ordenada(self, aggregator, feed, sample_route):
        for route in feed.routes_with_geometry()[:5]:
            aggregator.ingest(make_observation(route), NOW)

        ids = [vehicle.vehicle_id for vehicle in aggregator.snapshot()]

        assert ids == sorted(ids)

    def test_sin_vehiculos_la_instantanea_esta_vacia(self, aggregator):
        assert aggregator.snapshot() == []
