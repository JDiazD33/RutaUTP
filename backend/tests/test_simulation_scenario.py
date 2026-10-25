"""S05: física, sesiones, ruido, reloj y contrato; ejecución offline autorizada."""

from dataclasses import replace
from datetime import datetime
import io
import json
import math

import pytest

from rutautp_backend.config import Config
from rutautp_backend.models import OBSERVATION_FIELDS
from rutautp_backend.simulation_profile import lima_zone
from rutautp_backend.validation import ObservationValidator
from simulation.clock import ClockDiscontinuity, ClockGuard, ClockSample
from simulation.geometry import RoutePath, RouteStop, TripGeometry
from simulation.scenario import MotionSettings, PassengerActor, ScenarioEngine, VehicleJourney
from .conftest import GTFS_DIR
from .test_simulation_geometry import profile_s05, geometries_s05
from .test_simulation_persistence import RUN

NOW = datetime(2026, 10, 21, 12, tzinfo=lima_zone()).timestamp()
NAMESPACE = "4bf2741e-0999-4c80-9dcc-7adf42e82302"


@pytest.fixture
def settings(profile_s05):
    return replace(MotionSettings.from_profile(profile_s05), cruise_min=10, cruise_max=10)


def straight_geometry(stops=()):
    path = RoutePath([(0, 0), (0, .01)])
    return TripGeometry("route", "trip", "shape", "R", path,
        tuple(RouteStop(str(i), i, distance, path.at(distance).lat, path.at(distance).lon) for i, distance in enumerate(stops)))


def engine(profile, geometries, namespace=NAMESPACE):
    return ScenarioEngine(profile, geometries, RUN, GTFS_DIR, session_namespace=namespace)


def sample(elapsed, *, wall=None):
    return ClockSample(NOW + (elapsed if wall is None else wall), 100 + elapsed)


def test_acceleration_cruise_and_braking_are_continuous_in_meters(settings):
    geometry = straight_geometry()
    journey = VehicleJourney(geometry, settings, 12)
    assert journey.at(5).speed == pytest.approx(5)
    assert journey.at(5).distance_m == pytest.approx(12.5)
    assert journey.at(20).speed == pytest.approx(10)
    assert journey.at(20).distance_m == pytest.approx(150)
    end = journey.at(journey.arrival_time - 2)
    assert end.speed == pytest.approx(3)
    assert geometry.path.length_m - end.distance_m == pytest.approx(3)


def test_short_leg_brakes_without_overshooting_or_reaching_cruise(settings):
    geometry = straight_geometry((5,))
    journey = VehicleJourney(geometry, settings, 3)
    arrival, duration, _ = journey.dwell_windows[0]
    distances = [journey.at(arrival * i / 100).distance_m for i in range(101)]
    assert all(a <= b + 1e-8 for a, b in zip(distances, distances[1:]))
    assert max(distances) <= 5 + 1e-8
    stopped = journey.at(arrival + duration / 2)
    assert stopped.speed == 0 and stopped.heading == -1
    assert stopped.distance_m == pytest.approx(5)


def test_terminal_never_wraps_to_beginning(settings):
    journey = VehicleJourney(straight_geometry(), settings, 9, initial_progress=.5)
    assert journey.at(0).distance_m == pytest.approx(journey.geometry.path.length_m / 2)
    terminal = journey.at(journey.arrival_time)
    finished = journey.at(journey.finished_at + 1000)
    assert terminal.phase == "terminal" and finished.phase == "finished"
    assert terminal.distance_m == finished.distance_m == journey.geometry.path.length_m
    assert terminal.speed == finished.speed == 0


@pytest.mark.parametrize("changes", [{"cruise_max": 31}, {"acceleration": 0}, {"deceleration": float("nan")},
    {"noise_max": 20}, {"accuracy_max": 51}, {"dwell_min": True}, {"noise_period": 0}])
def test_invalid_motion_parameters_are_rejected(settings, changes):
    with pytest.raises(ValueError):
        replace(settings, **changes)


def test_noise_is_bounded_smooth_and_independent_per_actor(settings):
    a = PassengerActor("sim-001", "bus", 3, 8)
    b = PassengerActor("sim-002", "bus", 4, 8)
    assert a.noise(1, settings) != b.noise(1, settings)
    for index in range(101):
        north, east = a.noise(index / 10, settings)
        assert math.hypot(north, east) <= settings.noise_max + 1e-8
    left, right = a.noise(5 - .0001, settings), a.noise(5 + .0001, settings)
    assert math.dist(left, right) < .001


def test_engine_starts_thirty_boardings_with_shared_physics_and_exact_payload(profile_s05, geometries_s05):
    model = engine(profile_s05, geometries_s05)
    frame = model.advance(sample(0))
    assert len(frame.vehicles) == 10 and len(frame.observations) == len(frame.events) == 30
    assert all(v.contributors == 3 for v in frame.vehicles)
    assert all(o.speed == 0 and o.heading == -1 for o in frame.observations)
    assert all(set(o.payload()) == set(OBSERVATION_FIELDS) for o in frame.observations)
    assert all(o.payload()["motionActivity"] == "stationary" for o in frame.observations)
    assert len({o.session_id for o in frame.observations}) == 30
    assert all(event.boarding_record(RUN).run_id == RUN for event in frame.events)
    assert len({(o.lat, o.lon) for o in frame.observations}) == 30


def test_seed_replay_and_tick_partition_do_not_change_movement(profile_s05, geometries_s05):
    a, b = engine(profile_s05, geometries_s05), engine(profile_s05, geometries_s05)
    a.advance(sample(0)); b.advance(sample(0))
    for time in range(1, 11):
        frame_a = a.advance(sample(time))
    for time in range(2, 11, 2):
        frame_b = b.advance(sample(time))
    assert frame_a.vehicles == frame_b.vehicles
    assert frame_a.observations == frame_b.observations


def test_restart_uses_new_session_namespace_without_changing_motion(profile_s05, geometries_s05):
    a = engine(profile_s05, geometries_s05).advance(sample(0))
    b = engine(profile_s05, geometries_s05, "b080198b-1ae4-4524-b7c0-d5ac5930a30f").advance(sample(0))
    assert {o.session_id for o in a.observations}.isdisjoint(o.session_id for o in b.observations)
    assert [(o.lat, o.lon) for o in a.observations] == [(o.lat, o.lon) for o in b.observations]


def test_exchange_at_stop_keeps_two_contributors_and_rotates_session(profile_s05, geometries_s05):
    model = engine(profile_s05, geometries_s05)
    initial = model.advance(sample(0))
    old_sessions = {o.session_id for o in initial.observations}
    exchange = min(e[0] for e in model._scheduled if e[2] == "leave")
    frames = []
    # Pasos menores que el hiato de 2 segundos, con reloj coherente inyectado.
    for step in range(1, int((exchange + 3) * 2) + 2):
        frames.append(model.advance(sample(step / 2)))
    leaves = [event for frame in frames for event in frame.events if event.kind == "leave"]
    assert leaves
    assert all(v.contributors >= 2 for frame in frames for v in frame.vehicles if v.position.phase not in ("terminal", "finished"))
    assert any(o.session_id not in old_sessions for o in frames[-1].observations)


@pytest.mark.parametrize("reading", [sample(1, wall=30), sample(1, wall=-1), sample(20)])
def test_clock_fault_stops_without_backlog_or_automatic_resume(profile_s05, geometries_s05, reading):
    model = engine(profile_s05, geometries_s05)
    model.advance(sample(0))
    paused = model.advance(reading)
    assert paused.state == "paused" and not paused.observations
    assert len(paused.events) == 30 and all(e.kind == "leave" for e in paused.events)
    assert not model.advance(sample(21)).observations
    with pytest.raises(ValueError):
        model.continue_trip("scenario-bus-01", "17350695")


def test_outside_service_never_boards_and_duration_is_bounded(profile_s05, geometries_s05):
    outside = ClockSample(datetime(2026, 10, 21, 23, tzinfo=lima_zone()).timestamp(), 100)
    model = engine(profile_s05, geometries_s05)
    frame = model.advance(outside)
    assert frame.state == "stopped" and not frame.observations and not frame.events
    model = engine(profile_s05, geometries_s05)
    model.advance(sample(0))
    for time in range(10, 901, 10):
        frame = model.advance(sample(time))
    assert frame.reason == "max_run_duration" and not frame.observations


def test_engine_reference_separates_truth_and_observations_without_wire_metadata(profile_s05, geometries_s05):
    model = engine(profile_s05, geometries_s05)
    output = io.StringIO()
    model.write_reference(output, model.advance(sample(0)), include_header=True)
    header, frame = [json.loads(line) for line in output.getvalue().splitlines()]
    assert header["dataOrigin"] == "simulated" and header["simulationRunId"] == RUN
    assert header["manifestSha256"] == profile_s05.sha256
    assert len(frame["vehicles"]) == 10 and len(frame["observations"]) == 30
    assert "position" in frame["vehicles"][0] and "noise_north_m" in frame["observations"][0]


def short_catalog(profile, *, first_closed=False):
    catalog = {}
    for index, spec in enumerate(json.loads(profile.raw)["vehicles"]):
        lon = index * .01
        coordinates = [(0, lon), (0, lon + .001)]
        if index == 0 and first_closed:
            coordinates += [(.001, lon + .001), (0, lon)]
        catalog[spec["routeId"]] = TripGeometry(spec["routeId"], spec["tripId"], spec["shapeId"],
                                                spec["linea"], RoutePath(coordinates), ())
    return catalog


def finish_short_engine(model):
    initial = model.advance(sample(0))
    for time in range(5, 301, 5):
        frame = model.advance(sample(time))
        if frame.state == "finished":
            return initial, frame
    pytest.fail("el catálogo corto debe terminar sin alcanzar el presupuesto de 900 s")


def test_open_route_cannot_teleport_to_its_start(profile_s05):
    model = engine(profile_s05, short_catalog(profile_s05))
    _, finished = finish_short_engine(model)
    assert not finished.observations
    with pytest.raises(ValueError, match="no conecta"):
        model.continue_trip("scenario-bus-01", "17350695")


def test_explicit_connected_trip_gets_new_sessions_after_terminal_pause(profile_s05):
    model = engine(profile_s05, short_catalog(profile_s05, first_closed=True))
    initial, finished = finish_short_engine(model)
    previous = finished.vehicles[0]
    assert previous.position.phase == "finished"
    model.continue_trip("scenario-bus-01", "17350695")
    next_frame = model.advance(sample(finished.elapsed))
    current = next_frame.vehicles[0]
    assert current.position.lat == pytest.approx(previous.position.lat)
    assert current.position.lon == pytest.approx(previous.position.lon)
    assert current.journey_id != previous.journey_id
    assert len(next_frame.observations) == 3
    assert {o.session_id for o in initial.observations}.isdisjoint(o.session_id for o in next_frame.observations)


def test_terminal_continuation_is_forbidden_while_still_moving(profile_s05, geometries_s05):
    model = engine(profile_s05, geometries_s05)
    model.advance(sample(0))
    with pytest.raises(ValueError, match="falta finalizar"):
        model.continue_trip("scenario-bus-01", "17350695")


def test_generated_observations_use_existing_validation_without_threshold_changes(profile_s05, geometries_s05, feed):
    model = engine(profile_s05, geometries_s05)
    validator = ObservationValidator(feed, Config(gtfs_dir=GTFS_DIR, database_path="", health_file=""))
    rejected = []
    for time in range(0, 61, 5):
        frame = model.advance(sample(time))
        for observation in frame.observations:
            result = validator.validate(json.dumps(observation.payload()), frame.at, observation.principal)
            if not result.ok:
                rejected.append((observation.principal, time, result.reason, result.detail))
    assert rejected == []
