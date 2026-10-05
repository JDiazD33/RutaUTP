"""E20: el margen adicional puede ser cero sin desactivar la continuidad.

La configuración se construye con valores explícitos, nunca desde el entorno
real. Las trayectorias usan una recta norte y distancias esféricas conocidas;
la integración mantiene publicación en memoria y SQLite dentro de tmp_path.
"""

from __future__ import annotations

import json
import math
from dataclasses import replace

import pytest

from rutautp_backend.bridge import Bridge
from rutautp_backend.config import Config, ConfigError
from rutautp_backend.geo import EARTH_RADIUS_M
from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.models import RejectReason
from rutautp_backend.persistence import ObservationStore
from rutautp_backend.validation import ObservationValidator

from .conftest import vehicle_id
from .test_bridge import CapturingPublisher, topic_for

NOW = 1_700_000_000.0
ROUTE_ID = "e20-norte"
LONGITUDE = -79.006
ORIGIN_LATITUDE = -8.115
MARGIN_VARIABLE = "BACKEND_MAX_DISPLACEMENT_MARGIN_M"


def isolated_env(**overrides) -> dict[str, str]:
    return {"BACKEND_DB_PATH": "", "BACKEND_HEALTH_FILE": "", **overrides}


@pytest.mark.parametrize("margin", [0.0, -0.0, 0.5], ids=["cero", "menos-cero", "positivo"])
@pytest.mark.parametrize("factory", ["directa", "entorno"])
def test_margen_finito_no_negativo_se_puede_configurar(margin, factory):
    if factory == "directa":
        configured = Config(
            database_path="", health_file="", max_displacement_margin_m=margin
        )
    else:
        configured = Config.from_env(isolated_env(**{MARGIN_VARIABLE: str(margin)}))

    assert configured.max_displacement_margin_m == margin
    assert math.isfinite(configured.max_displacement_margin_m)
    assert configured.max_speed_ms == 30.0
    assert configured.max_accuracy_m == 50.0
    assert configured.dedupe_window_s == 120.0


def test_construccion_directa_conserva_el_margen_por_defecto():
    assert Config(database_path="", health_file="").max_displacement_margin_m == 250.0


@pytest.mark.parametrize("raw", [None, "", "   "], ids=["ausente", "vacio", "espacios"])
def test_entorno_omitido_o_vacio_conserva_el_margen_por_defecto(raw):
    env = isolated_env()
    if raw is not None:
        env[MARGIN_VARIABLE] = raw
    assert Config.from_env(env).max_displacement_margin_m == 250.0


@pytest.mark.parametrize("margin", [-0.01, math.nan, math.inf, -math.inf])
@pytest.mark.parametrize("factory", ["directa", "entorno"])
def test_margen_negativo_o_no_finito_se_rechaza(margin, factory):
    name = "max_displacement_margin_m" if factory == "directa" else MARGIN_VARIABLE
    with pytest.raises(ConfigError, match=name):
        if factory == "directa":
            Config(database_path="", health_file="", max_displacement_margin_m=margin)
        else:
            Config.from_env(isolated_env(**{MARGIN_VARIABLE: str(margin)}))


@pytest.mark.parametrize(
    "field,variable",
    [
        ("max_speed_ms", "BACKEND_MAX_SPEED_MS"),
        ("max_accuracy_m", "BACKEND_MAX_ACCURACY_M"),
        ("dedupe_window_s", "BACKEND_DEDUPE_WINDOW_S"),
    ],
)
def test_admitir_margen_cero_no_admite_cero_en_los_otros_limites(field, variable):
    with pytest.raises(ConfigError, match=field):
        Config(database_path="", health_file="", **{field: 0.0})
    with pytest.raises(ConfigError, match=variable):
        Config.from_env(isolated_env(**{variable: "0"}))


@pytest.fixture
def straight_feed() -> GtfsFeed:
    route = RouteGeometry(
        route_id=ROUTE_ID,
        linea="E-20",
        variante="",
        empresa="Prueba aislada",
        shape=((-8.12, LONGITUDE), (-8.06, LONGITUDE)),
    )
    return GtfsFeed(routes={ROUTE_ID: route})


def latitude_at(meters: float) -> float:
    return ORIGIN_LATITUDE + math.degrees(meters / EARTH_RADIUS_M)


def payload(meters: float, timestamp: float, *, session: str = "e20") -> str:
    return json.dumps(
        {
            "schemaVersion": 1,
            "sessionId": session,
            "routeId": ROUTE_ID,
            "linea": "E-20",
            "lat": latitude_at(meters),
            "lon": LONGITUDE,
            "speed": 8.0,
            "heading": 0.0,
            "accuracy": 8.0,
            "motionActivity": "automotive",
            "timestamp": timestamp,
        }
    )


def constrained_config(config, *, margin=0.0):
    return replace(
        config, max_speed_ms=10.0, max_accuracy_m=10.0, max_displacement_margin_m=margin
    )


@pytest.mark.parametrize("direction", [-1.0, 1.0])
@pytest.mark.parametrize("distance,accepted", [(19.99, True), (20.01, False)])
def test_margen_cero_conserva_techo_de_velocidad_y_una_precision(
    straight_feed, config, direction, distance, accepted
):
    # En un segundo: 10 m/s * 1 s + 10 m de precisión + 0 m = 20 m.
    # Los centímetros a cada lado evitan una igualdad sensible al redondeo.
    validator = ObservationValidator(straight_feed, constrained_config(config))
    assert validator.validate(payload(2_000, NOW), NOW).ok

    result = validator.validate(
        payload(2_000 + direction * distance, NOW + 1), NOW + 1
    )

    assert result.ok is accepted
    if not accepted:
        assert result.reason is RejectReason.IMPLAUSIBLE_JUMP


@pytest.mark.parametrize("distance,accepted", [(29.99, True), (30.01, False)])
def test_margen_cero_sigue_calculando_el_tiempo_transcurrido(
    straight_feed, config, distance, accepted
):
    validator = ObservationValidator(straight_feed, constrained_config(config))
    assert validator.validate(payload(0, NOW), NOW).ok
    result = validator.validate(payload(distance, NOW + 2), NOW + 2)
    assert result.ok is accepted
    if not accepted:
        assert result.reason is RejectReason.IMPLAUSIBLE_JUMP


@pytest.mark.parametrize("margin,accepted", [(0.0, False), (2.0, True)])
def test_margen_positivo_solo_anade_su_tolerancia_al_mismo_recorrido(
    straight_feed, config, margin, accepted
):
    validator = ObservationValidator(straight_feed, constrained_config(config, margin=margin))
    assert validator.validate(payload(0, NOW), NOW).ok
    result = validator.validate(payload(21, NOW + 1), NOW + 1)
    assert result.ok is accepted
    if not accepted:
        assert result.reason is RejectReason.IMPLAUSIBLE_JUMP


def bridge_send(bridge, meters, timestamp, *, now, session="e20", principal="cuenta-a"):
    return bridge.handle_message(
        topic_for(session=session, principal=principal),
        payload(meters, timestamp, session=session),
        now,
    )


def test_margen_cero_preserva_quorum_estado_historial_y_recuperacion_tras_rechazo(
    straight_feed, config, tmp_path
):
    publisher = CapturingPublisher()
    store = ObservationStore(tmp_path / "e20.sqlite")
    try:
        bridge = Bridge(
            config=replace(constrained_config(config), min_publish_principals=2),
            feed=straight_feed,
            publisher=publisher,
            store=store,
        )
        first = bridge_send(bridge, 0, NOW, now=NOW)
        second = bridge_send(
            bridge, 0, NOW + 1, now=NOW + 1, session="corrobora", principal="cuenta-b"
        )
        expected_id = vehicle_id(ROUTE_ID, 1)
        assert first.accepted and first.created_vehicle and not first.published
        assert second.accepted and second.published and not second.created_vehicle
        assert first.vehicle_id == second.vehicle_id == expected_id

        # Las lecturas atrasadas siguen aceptándose y guardándose, sin tomar
        # el lugar de la referencia más reciente (la garantía reparada en E16).
        delayed = bridge_send(bridge, 800, NOW - 10, now=NOW + 2)
        assert delayed.accepted and not delayed.published and not delayed.created_vehicle
        vehicle = bridge.aggregator.snapshot()[0]
        before = (
            dict(vehicle.to_vehicle_position()),
            vehicle.sample_count,
            dict(vehicle.principals),
        )
        assert vehicle.lat == pytest.approx(latitude_at(0))
        assert vehicle.timestamp == NOW + 1
        assert publisher.count == 1

        duplicate = bridge_send(bridge, 800, NOW, now=NOW + 2)
        rejected = bridge_send(bridge, 800, NOW + 2, now=NOW + 3)
        assert not duplicate.accepted and duplicate.reason is RejectReason.DUPLICATE
        assert not rejected.accepted and rejected.reason is RejectReason.IMPLAUSIBLE_JUMP
        assert bridge.aggregator.vehicle_count == 1
        assert (vehicle.to_vehicle_position(), vehicle.sample_count, vehicle.principals) == before
        assert publisher.count == 1
        assert len(store.query("SELECT * FROM observations")) == 3
        assert len(store.query("SELECT * FROM vehicle_positions")) == 1

        # El rechazo no consume el timestamp: una posición corregida puede
        # volver a publicarse con la misma identidad y el quorum anterior.
        recovered = bridge_send(bridge, 10, NOW + 2, now=NOW + 7)
        assert recovered.accepted and recovered.published and not recovered.created_vehicle
        assert recovered.vehicle_id == expected_id
        assert publisher.count == 2
        assert publisher.last()["vehicleId"] == expected_id
        assert publisher.last()["lat"] == pytest.approx(latitude_at(10))
        assert publisher.last()["timestamp"] == NOW + 2
        assert vehicle.principals == {"cuenta-a": NOW + 2, "cuenta-b": NOW + 1}
        assert store.query(
            "SELECT observed_at, lat, vehicle_id FROM observations ORDER BY id"
        ) == [
            (NOW, latitude_at(0), expected_id),
            (NOW + 1, latitude_at(0), expected_id),
            (NOW - 10, latitude_at(800), expected_id),
            (NOW + 2, latitude_at(10), expected_id),
        ]
        assert store.query(
            "SELECT observed_at, lat, vehicle_id FROM vehicle_positions ORDER BY id"
        ) == [
            (NOW + 1, latitude_at(0), expected_id),
            (NOW + 2, latitude_at(10), expected_id),
        ]
        assert store.query("SELECT reason FROM rejections ORDER BY id") == [
            (RejectReason.DUPLICATE.value,),
            (RejectReason.IMPLAUSIBLE_JUMP.value,),
        ]
        assert store.counts.write_errors == 0
    finally:
        store.close()
