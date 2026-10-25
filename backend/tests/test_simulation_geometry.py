"""S05: distancias, shape exacto y adaptación de paraderos; sin red."""

import csv
import json
from dataclasses import replace
from types import SimpleNamespace

import pytest

from rutautp_backend.gtfs import GtfsFeed, RouteGeometry
from rutautp_backend.simulation_profile import SimulationProfile
from simulation.geometry import RoutePath, load_trip_geometries
from .conftest import GTFS_DIR


@pytest.fixture(scope="session")
def profile_s05():
    return SimulationProfile.load("pasajeros-30", GTFS_DIR)


@pytest.fixture(scope="session")
def geometries_s05(profile_s05, feed):
    return load_trip_geometries(profile_s05, GTFS_DIR, feed)


def test_interpolates_by_meters_instead_of_vertex_number():
    path = RoutePath([(0, 0), (0, 0.0001), (0, 0.001)])
    middle = path.at(path.length_m / 2)
    assert middle.lon == pytest.approx(0.0005)
    assert middle.lat == 0 and middle.heading == pytest.approx(90)


def test_repeated_vertices_are_skipped_and_boundaries_do_not_wrap():
    path = RoutePath([(0, 0), (0, 0), (0, 0.001), (0, 0.001)])
    assert len(path.points) == 2
    assert path.at(-10).lon == 0
    assert path.at(path.length_m + 100).lon == 0.001
    assert path.at(path.length_m).distance_m == path.length_m


@pytest.mark.parametrize("points", [[], [(0, 0)], [(0, 0), (0, 0)],
                                     [(0, 0), (float("nan"), 0)], [(0, 0), (True, 0)]])
def test_rejects_unusable_geometry(points):
    with pytest.raises(ValueError):
        RoutePath(points)


def test_segment_direction_comes_from_selected_shape():
    east = RoutePath([(0, 0), (0, .001)])
    west = RoutePath([(0, .001), (0, 0)])
    assert east.at(10).heading == pytest.approx(90)
    assert west.at(10).heading == pytest.approx(270)


def test_stop_projection_reports_distance_and_rejects_out_of_order():
    path = RoutePath([(0, 0), (0, .001)])
    projection, reason = path.project_stop(.00001, .0005, -1, 50)
    assert reason == "" and projection.distance_m < 2
    assert projection.along_m == pytest.approx(path.length_m / 2)
    assert path.project_stop(1, .0005, -1, 50)[1] == "too_far_from_shape"
    assert path.project_stop(0, .0001, path.length_m / 2, 50)[1] == "out_of_sequence"


def test_closed_loop_ambiguity_is_not_assigned_arbitrarily():
    path = RoutePath([(0, 0), (0, .001), (.001, .001), (.001, 0), (0, 0)])
    assert path.project_stop(0, 0, -1, 50)[1] == "ambiguous_projection"
    projected, reason = path.project_stop(0, 0, 100, 50)
    assert reason == "" and projected.along_m == pytest.approx(path.length_m)


def test_overlapping_opposite_segments_report_uncertainty_without_faking_direction():
    path = RoutePath([(0, 0), (0, .001), (0, 0)])
    assert path.reported_heading(0, .0005, 90, 3) == (90, None)
    assert path.reported_heading(0, .0005, 270, 3) == (-1, "ambiguous_gtfs_heading")
    assert path.at(path.length_m * .75).heading == pytest.approx(270)


def test_indexed_heading_match_agrees_with_original_shape_order():
    from rutautp_backend.geo import match_point_to_polyline, segment_bearing_deg, heading_difference_deg
    coordinates = [(0, 0), (0, .001), (0, .001), (.001, .001), (0, 0)]
    path = RoutePath(coordinates)
    for step in range(1, 20):
        point = path.at(path.length_m * step / 20)
        lat, lon = point.lat + .00001, point.lon - .000005
        match = match_point_to_polyline(lat, lon, coordinates)
        canonical = segment_bearing_deg(coordinates, match.segment_index)
        reported, _ = path.reported_heading(lat, lon, point.heading, 3)
        expected = -1 if heading_difference_deg(point.heading, canonical) > 60 else point.heading
        assert reported == expected


def test_real_catalog_is_exact_and_uses_only_selected_trip_stops(profile_s05, geometries_s05):
    manifest = json.loads(profile_s05.raw)
    with (GTFS_DIR / "stop_times.txt").open(encoding="utf-8-sig", newline="") as stream:
        memberships = {(r["trip_id"], r["stop_id"], int(r["stop_sequence"])) for r in csv.DictReader(stream)}
    assert len(geometries_s05) == 10
    for spec in manifest["vehicles"]:
        geometry = geometries_s05[spec["routeId"]]
        assert geometry.trip_id == spec["tripId"] and geometry.shape_id == spec["shapeId"]
        assert geometry.linea == spec["linea"] and geometry.path.length_m > 0
        distances = [stop.distance_m for stop in geometry.stops]
        assert distances == sorted(set(distances))
        assert all((geometry.trip_id, s.stop_id, s.sequence) in memberships for s in geometry.stops)


def test_catalog_cannot_silently_change_backend_line(profile_s05, feed):
    routes = dict(feed.routes)
    route_id = json.loads(profile_s05.raw)["vehicles"][0]["routeId"]
    routes[route_id] = replace(routes[route_id], linea="wrong-line")
    with pytest.raises(ValueError, match="no coinciden"):
        load_trip_geometries(profile_s05, GTFS_DIR, GtfsFeed(routes=routes, source_dir=GTFS_DIR))


def test_changed_feed_is_rejected_before_catalog_load(profile_s05, monkeypatch):
    monkeypatch.setattr(SimulationProfile, "signatures", lambda *_: ("changed",))
    with pytest.raises(ValueError, match="cambiados"):
        load_trip_geometries(profile_s05, GTFS_DIR)


def test_invalid_or_unrelated_stops_do_not_enter_route(tmp_path):
    files = {
        "trips.txt": "trip_id,route_id,shape_id\ntrip,route,shape\nother,elsewhere,other-shape\n",
        "shapes.txt": "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nshape,0,0,0\nshape,0,0.001,1\n",
        "stops.txt": "stop_id,stop_lat,stop_lon\nfirst,0,0.0002\nfar,1,1\nback,0,0.0001\nlast,0,0.0008\nunrelated,0,0.0004\n",
        "stop_times.txt": "trip_id,stop_sequence,stop_id\ntrip,0,first\ntrip,1,far\ntrip,2,back\ntrip,3,last\ntrip,bad,first\nother,0,unrelated\n",
    }
    for name, content in files.items():
        (tmp_path / name).write_text(content)
    profile = SimpleNamespace(raw=json.dumps({"vehicles": [{"routeId": "route", "tripId": "trip", "shapeId": "shape", "linea": "R"}],
        "movement": {"maxStopProjectionDistanceMeters": 50}}), verified_signatures=(), signatures=lambda _: ())
    feed = GtfsFeed(routes={"route": RouteGeometry("route", "R", "", "", ((0, 0), (0, .001)))})
    geometry = load_trip_geometries(profile, tmp_path, feed)["route"]
    assert [s.stop_id for s in geometry.stops] == ["first", "last"]
    assert {i.reason for i in geometry.issues} == {"too_far_from_shape", "out_of_sequence", "invalid_stop_sequence"}
