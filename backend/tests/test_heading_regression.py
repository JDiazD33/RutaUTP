"""E15: el rumbo se compara como ángulo antes de validar y agregar.

La geometría norte de dos vértices evita ambigüedades de proyección. Los
mensajes usan el contrato real; el puente trabaja con un publicador en memoria
y, donde se comprueba el histórico, una SQLite de ``tmp_path``. No hay sockets,
reloj real, variables del entorno ni base de datos de la instalación.
"""

from __future__ import annotations

import json
import math
import sys
from dataclasses import replace

import pytest

from rutautp_backend.aggregation import VehicleAggregator
from rutautp_backend.bridge import Bridge
from rutautp_backend.geo import heading_difference_deg
from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.models import RejectReason
from rutautp_backend.persistence import ObservationStore
from rutautp_backend.validation import ObservationValidator

from .conftest import vehicle_id
from .test_bridge import CapturingPublisher, topic_for

NOW = 1_700_000_000.0
ROUTE_ID = "e15-norte"


@pytest.fixture
def north_feed() -> GtfsFeed:
    route = RouteGeometry(
        route_id=ROUTE_ID,
        linea="E-15",
        variante="",
        empresa="Prueba aislada",
        shape=((-8.11, -79.006), (-8.10, -79.006)),
    )
    return GtfsFeed(routes={route.route_id: route})


def payload(*, heading: float, now: float = NOW, session: str = "e15", **extra):
    body = {
        "schemaVersion": 1,
        "sessionId": session,
        "routeId": ROUTE_ID,
        "linea": "E-15",
        "lat": -8.105,
        "lon": -79.006,
        "speed": 8.0,
        "heading": heading,
        "accuracy": 8.0,
        "motionActivity": "automotive",
        "timestamp": now,
    }
    body.update(extra)
    return json.dumps(body)


@pytest.mark.parametrize(
    "device,route,expected",
    [
        (450.0, 90.0, 0.0),
        (1170.0, 810.0, 0.0),
        (630.0, 90.0, 180.0),
        (1350.0, 810.0, 180.0),
        (350.0, 10.0, 20.0),
        (10.0, 350.0, 20.0),
    ],
)
def test_diferencia_circular_equivalente_contraria_y_cruce(device, route, expected):
    assert heading_difference_deg(device, route) == pytest.approx(expected)
    assert heading_difference_deg(route, device) == pytest.approx(expected)


@pytest.mark.parametrize(
    "device,route",
    [
        (sys.float_info.max, 0.0),
        (0.0, sys.float_info.max),
        (sys.float_info.max, 1e308),
    ],
)
def test_diferencia_finita_grande_respeta_el_intervalo(device, route):
    # remainder aporta una referencia circular independiente y evita restar
    # primero valores enormes, lo que puede perder precisión o desbordar.
    expected = abs(
        math.remainder(
            math.remainder(device, 360.0) - math.remainder(route, 360.0), 360.0
        )
    )
    difference = heading_difference_deg(device, route)
    assert math.isfinite(difference)
    assert 0.0 <= difference <= 180.0
    assert difference == pytest.approx(expected)
    assert heading_difference_deg(route, device) == pytest.approx(expected)


@pytest.mark.parametrize(
    "device,route",
    [
        (-1.0, 0.0),
        (0.0, -1.0),
        (math.nan, 0.0),
        (0.0, math.nan),
        (math.inf, 0.0),
        (0.0, -math.inf),
    ],
)
def test_diferencia_desconocida_no_se_declara_alineada(device, route):
    assert heading_difference_deg(device, route) == 180.0


@pytest.mark.parametrize("heading,canonical,difference", [(360, 0, 0), (1080, 0, 0), (740, 20, 20)])
def test_validador_acepta_equivalente_y_guarda_rumbo_y_diferencia(
    north_feed, config, heading, canonical, difference
):
    result = ObservationValidator(north_feed, config).validate(payload(heading=heading), NOW)
    assert result.ok
    observation = result.observation
    assert observation is not None
    assert observation.heading == pytest.approx(canonical)
    assert observation.heading_diff_deg == pytest.approx(difference)
    assert observation.route_id == ROUTE_ID
    assert observation.linea == "E-15"
    assert observation.distance_to_route_m < 1.0


@pytest.mark.parametrize("heading", [540.0, 1260.0])
def test_validador_rechaza_sentido_contrario_con_varias_vueltas(north_feed, config, heading):
    result = ObservationValidator(north_feed, config).validate(payload(heading=heading), NOW)
    assert result.ok is False
    assert result.reason is RejectReason.HEADING_NOT_ALIGNED
    assert result.observation is None


@pytest.mark.parametrize(
    "side,epsilon,accepted",
    [(1, 0.0, True), (-1, 0.0, True), (1, 0.001, False), (-1, 0.001, False)],
)
def test_validador_conserva_el_umbral_en_ambos_sentidos_tras_varias_vueltas(
    north_feed, config, side, epsilon, accepted
):
    heading = 1080.0 + side * (config.max_heading_diff_deg + epsilon)
    result = ObservationValidator(north_feed, config).validate(payload(heading=heading), NOW)
    assert result.ok is accepted
    if accepted:
        assert result.observation is not None
        assert result.observation.heading == pytest.approx(heading % 360.0)
        assert result.observation.heading_diff_deg == pytest.approx(config.max_heading_diff_deg)
    else:
        assert result.reason is RejectReason.HEADING_NOT_ALIGNED
        assert result.observation is None


@pytest.mark.parametrize("heading", [math.nan, math.inf, -math.inf])
def test_validador_no_acepta_no_finitos_como_desconocidos(north_feed, config, heading):
    result = ObservationValidator(north_feed, config).validate(payload(heading=heading), NOW)
    assert result.ok is False
    assert result.reason is RejectReason.NON_FINITE_NUMBER
    assert result.observation is None


@pytest.mark.parametrize("speed", [0.0, 8.0])
@pytest.mark.parametrize("heading", [-1.0, -5.0])
def test_puente_conserva_rumbo_desconocido_bus_detenido_y_contrato(
    north_feed, config, speed, heading
):
    publisher = CapturingPublisher()
    bridge = Bridge(config=config, feed=north_feed, publisher=publisher)
    outcome = bridge.handle_message(
        topic_for(session="e15"), payload(heading=heading, speed=speed), NOW
    )
    assert outcome.accepted and outcome.published
    assert bridge.store.enabled is False
    body = publisher.last()
    assert set(body) == {
        "vehicleId", "routeId", "linea", "lat", "lon", "speed", "heading", "timestamp"
    }
    assert body["heading"] == -1.0
    assert body["speed"] == speed
    assert body["routeId"] == ROUTE_ID
    assert body["linea"] == "E-15"
    assert body["timestamp"] == NOW


def test_rechazos_no_crean_vehiculos_historial_posiciones_ni_quorum(
    north_feed, config, tmp_path
):
    publisher = CapturingPublisher()
    secure_config = replace(config, min_publish_principals=2)
    store = ObservationStore(tmp_path / "e15.sqlite")
    try:
        bridge = Bridge(config=secure_config, feed=north_feed, publisher=publisher, store=store)
        rejected = bridge.handle_message(
            topic_for(session="contrario", principal="cuenta-b"),
            payload(heading=540, session="contrario"),
            NOW,
        )
        assert rejected.accepted is False
        assert rejected.reason is RejectReason.HEADING_NOT_ALIGNED
        assert bridge.aggregator.vehicle_count == 0
        assert store.query("SELECT * FROM observations") == []
        assert store.query("SELECT * FROM vehicle_positions") == []
        assert publisher.count == 0

        first = bridge.handle_message(
            topic_for(session="uno", principal="cuenta-a"),
            payload(heading=360, session="uno", now=NOW + 1),
            NOW + 1,
        )
        rotated = bridge.handle_message(
            topic_for(session="dos", principal="cuenta-a"),
            payload(heading=720, session="dos", now=NOW + 2),
            NOW + 2,
        )
        assert first.accepted and first.created_vehicle and not first.published
        assert first.vehicle_id == vehicle_id(ROUTE_ID, 1)
        assert rotated.accepted and not rotated.created_vehicle and not rotated.published
        vehicle = bridge.aggregator.snapshot()[0]
        before = (dict(vehicle.to_vehicle_position()), vehicle.sample_count, dict(vehicle.principals))

        rejected_again = bridge.handle_message(
            topic_for(session="tres", principal="cuenta-b"),
            payload(heading=1260, session="tres", now=NOW + 3),
            NOW + 3,
        )
        assert rejected_again.reason is RejectReason.HEADING_NOT_ALIGNED
        assert bridge.aggregator.vehicle_count == 1
        assert (vehicle.to_vehicle_position(), vehicle.sample_count, vehicle.principals) == before
        assert len(store.query("SELECT * FROM observations")) == 2
        assert store.query("SELECT * FROM vehicle_positions") == []
        assert publisher.count == 0

        corroborated = bridge.handle_message(
            topic_for(session="tres", principal="cuenta-b"),
            # Mismo sessionId/timestamp que el rechazado: no debe haber
            # consumido deduplicación ni el historial de continuidad.
            payload(heading=1080, session="tres", now=NOW + 3),
            NOW + 3,
        )
        assert corroborated.accepted and not corroborated.created_vehicle and corroborated.published
        assert corroborated.vehicle_id == first.vehicle_id
        assert publisher.count == 1
        assert publisher.last()["heading"] == 0.0
        assert publisher.last()["routeId"] == ROUTE_ID
        assert len(store.query("SELECT * FROM observations")) == 3
        assert len(store.query("SELECT * FROM vehicle_positions")) == 1
        assert store.query("SELECT reason FROM rejections") == [
            ("heading_not_aligned",), ("heading_not_aligned",)
        ]
        assert bridge.metrics.snapshot()["internalErrors"] == 0
    finally:
        store.close()


def test_agregador_compara_rumbos_multivuelta_sin_fusionar_opuestos(north_feed, config):
    result = ObservationValidator(north_feed, config).validate(payload(heading=0), NOW)
    assert result.observation is not None
    aggregator = VehicleAggregator(config, north_feed)
    first, _ = aggregator.ingest(result.observation, NOW, principal="cuenta-a")
    # Este consumidor interno también comparte el cálculo angular. Sesiones
    # distintas ejercitan la coherencia por proximidad, sin cambiar su vínculo.
    second, created = aggregator.ingest(
        replace(result.observation, session_id="otra", heading=540.0, timestamp=NOW + 1),
        NOW + 1,
        principal="cuenta-b",
    )
    assert created is True
    assert second.vehicle_id != first.vehicle_id
    assert aggregator.vehicle_count == 2


def test_validador_conserva_la_comprobacion_de_linea(north_feed, config):
    result = ObservationValidator(north_feed, config).validate(
        payload(heading=720, linea="otra"), NOW
    )
    assert result.ok is False
    assert result.reason is RejectReason.LINE_MISMATCH
    assert result.observation is None
