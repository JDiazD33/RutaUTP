import json
from types import SimpleNamespace

import pytest

from rutautp_backend.occupancy import Occupancy, WINDOW, SNAPSHOT_TOPIC

NOW = 1_790_000_000


@pytest.fixture
def setup():
    vehicles = [SimpleNamespace(vehicle_id=f"bus-{i}", last_seen=NOW,
                               principals={f"person-{p}": NOW for p in range(1, 6)})
                for i in (1, 2)]
    return Occupancy(lambda: vehicles), vehicles


def send(service, principal="person-1", vehicle_id="bus-1", state="empty", now=NOW, **updates):
    body = dict(schemaVersion=1, requestId="test-1", vehicleId=vehicle_id, state=state, timestamp=now)
    body.update(updates)
    return service.handle(f"rutautp/ocupacion/{principal}/reporte", json.dumps(body), now)


def test_single_account_and_repeated_taps_never_confirm(setup):
    service, vehicles = setup
    assert send(service)[1]["code"] == "pending"
    assert send(service, now=NOW+1)[1]["code"] == "rate_limit"
    assert send(service, now=NOW+30)[1]["code"] == "pending"
    assert service.snapshot(NOW+30)["buses"] == []


def test_two_accounts_confirm_same_vehicle(setup):
    service, _ = setup
    send(service)
    assert send(service, "person-2")[1]["code"] == "confirmed"
    reading = service.snapshot(NOW)["buses"][0]
    assert reading == dict(vehicleId="bus-1", state="empty", confirmations=2,
                           updatedAt=NOW, expiresAt=NOW+WINDOW)
    assert "person-" not in json.dumps(reading)


def test_different_buses_never_share_votes(setup):
    service, _ = setup
    send(service)
    send(service, "person-2", vehicle_id="bus-2")
    assert service.snapshot(NOW)["buses"] == []


def test_conflicting_reports_and_ties_are_unconfirmed(setup):
    service, _ = setup
    send(service)
    send(service, "person-2", state="full")
    assert service.snapshot(NOW)["buses"] == []
    send(service, "person-3", state="full")
    assert service.snapshot(NOW)["buses"][0]["state"] == "full"
    send(service, "person-4", state="empty")
    assert service.snapshot(NOW)["buses"] == []


def test_changing_vote_replaces_old_state(setup):
    service, _ = setup
    send(service)
    send(service, "person-2")
    assert send(service, state="full", now=NOW+30)[1]["code"] == "pending"
    assert service.snapshot(NOW+30)["buses"] == []
    send(service, "person-2", state="full", now=NOW+30)
    assert service.snapshot(NOW+30)["buses"][0]["state"] == "full"


def test_switching_buses_removes_previous_vote(setup):
    service, _ = setup
    send(service)
    send(service, "person-2")
    send(service, vehicle_id="bus-2", now=NOW+30)
    assert service.snapshot(NOW+30)["buses"] == []


def test_votes_expire_even_if_bus_keeps_moving(setup):
    service, vehicles = setup
    send(service)
    send(service, "person-2", now=NOW+10)
    vehicles[0].last_seen = NOW+WINDOW
    assert service.snapshot(NOW+WINDOW)["buses"] == []
    assert len(service.votes["bus-1"]) == 1


def test_departed_vehicle_loses_occupancy(setup):
    service, vehicles = setup
    send(service)
    send(service, "person-2")
    assert service.snapshot(NOW+46)["buses"] == []
    vehicles[0].last_seen = NOW+47
    assert service.snapshot(NOW+47)["buses"] == []


def test_only_recently_detected_passengers_can_report(setup):
    service, vehicles = setup
    assert send(service, "outsider")[1]["code"] == "not_onboard"
    vehicles[0].principals["person-1"] = NOW-61
    assert send(service)[1]["code"] == "not_onboard"
    assert send(service, vehicle_id="demo-bus")[1]["code"] == "unavailable"


@pytest.mark.parametrize("updates", [dict(schemaVersion=True), dict(state="half"), dict(vehicleId=[]),
    dict(timestamp=True), dict(timestamp=float("nan")), dict(timestamp=NOW-61),
    dict(timestamp=NOW+11), dict(vehicleId=""), dict(requestId="bad/#")])
def test_invalid_reports_do_not_count(setup, updates):
    service, _ = setup
    result = send(service, **updates)
    assert result is None or result[1]["accepted"] is False
    assert service.votes == {}


@pytest.mark.parametrize("payload", [b"null", b"[]", b"{", b"x"*1025, b'"text"'])
def test_malformed_report_does_not_crash(setup, payload):
    service, _ = setup
    assert service.handle("rutautp/ocupacion/person-1/reporte", payload, NOW) is None


def test_publish_retry_and_empty_snapshot(setup):
    service, _ = setup
    messages = []
    service.publish_snapshot(NOW, lambda *args: False)
    service.publish_snapshot(NOW+1, lambda *args: messages.append(args) or True)
    assert messages[0][0] == SNAPSHOT_TOPIC
    assert json.loads(messages[0][1])["buses"] == []
    service.publish_snapshot(NOW+2, lambda *args: messages.append(args) or True)
    assert len(messages) == 1


def test_passenger_identity_is_reused_from_real_tracking_pipeline(feed, config, sample_route):
    from rutautp_backend.bridge import Bridge
    from .test_bridge import payload_for

    bridge = Bridge(config, feed)
    vehicle_id = None
    for principal in ("person-1", "person-2"):
        session = f"session-{principal}"
        outcome = bridge.handle_message(
            f"rutautp/observaciones/{principal}/{session}/posicion",
            payload_for(sample_route, now=NOW, session=session), NOW)
        assert outcome.accepted
        if vehicle_id is not None:
            assert outcome.vehicle_id == vehicle_id
        vehicle_id = outcome.vehicle_id
    assert send(bridge.occupancy, vehicle_id=vehicle_id)[1]["code"] == "pending"
    assert send(bridge.occupancy, "person-2", vehicle_id=vehicle_id)[1]["code"] == "confirmed"
    assert send(bridge.occupancy, "outsider", vehicle_id=vehicle_id)[1]["code"] == "not_onboard"
    assert bridge.occupancy.snapshot(NOW)["buses"][0]["vehicleId"] == vehicle_id
    bridge.store.close()
