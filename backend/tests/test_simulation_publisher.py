"""S06: clientes capturados y futuros manuales; jamás sockets ni broker."""

from concurrent.futures import Future
import json
from types import SimpleNamespace

import pytest

from simulation.clock import ClockSample
from simulation.publisher import (Account, BrokerSettings, MqttTransport, load_credentials,
                                  parse_control, paho_factory)
from simulation.scenario import ActorObservation
from .test_simulation_persistence import RUN, SESSION, OTHER_RUN

PRINCIPALS = frozenset(f"sim-{i:03}" for i in range(1, 31))
INSTANCE = "75b7f9de-b8cf-45db-9030-7ba8905bc7d3"


def settings():
    return BrokerSettings("invalid.example", 8883, True, None,
                          {p: Account(p, "secret-" + p) for p in PRINCIPALS})


def sample(at=0):
    return ClockSample(1000 + at, 100 + at)


def body(at=0, **changes):
    return {"schemaVersion": 1, "enabled": True, "runId": RUN, "controlRevision": 3,
            "issuedAt": 1000 + at, "validUntil": 1015 + at, "serviceEndsAt": 2000,
            "timeZone": "America/Lima", **changes}


def observation(at=0, principal="sim-001"):
    return ActorObservation(principal, SESSION, "nominal", "journey", "route", "C-01",
                            -12, -77, 5, 90, 10, 1000 + at, 0, 0, None)


class Client:
    def __init__(self, principal, client_id):
        self.principal, self.client_id = principal, client_id
        self.messages = []
        self.subscriptions = []
        self.closed = False
        self.rc = 0
    def socket(self):
        return None
    def disconnect(self):
        self.closed = True
    def loop_misc(self): return 0
    def want_write(self): return False
    def subscribe(self, topic, qos):
        self.subscriptions.append((topic, qos))
        return 0, 21
    def publish(self, topic, raw, qos, retain):
        self.messages.append((topic, json.loads(raw), qos, retain))
        return SimpleNamespace(rc=self.rc, mid=len(self.messages))


class Dialer:
    def __init__(self, complete=True):
        self.complete = complete
        self.futures = []
        self.closed = False
    @property
    def busy(self):
        return bool(self.futures and not self.futures[-1].done())
    def submit(self, client):
        future = Future()
        self.futures.append(future)
        if self.complete:
            future.set_result(0)
        return future
    def close(self):
        self.closed = True


@pytest.fixture
def transport():
    clients = []
    def factory(principal, client_id):
        client = Client(principal, client_id)
        clients.append(client)
        return client
    transport = MqttTransport(PRINCIPALS, RUN, 3, settings(), INSTANCE,
                              client_factory=factory, dialer=Dialer())
    transport.captured = clients
    yield transport
    transport.close()


def connected(transport, principal="sim-001", at=0):
    transport.ensure_connections({principal}, sample(at))
    transport.service(sample(at))
    client = transport.channels[principal].client
    client.on_connect(client, None, None, 0, None)
    client.on_subscribe(client, None, 21, [1], None)
    message = SimpleNamespace(topic="rutautp/simulacion/estado", payload=json.dumps(body(at)).encode())
    client.on_message(client, None, message)
    return client


def test_thirty_distinct_connections_accounts_clientids_and_only_control_subscription(transport):
    for principal in sorted(PRINCIPALS):
        connected(transport, principal)
    assert len(transport.captured) == 30
    assert len({c.client_id for c in transport.captured}) == 30
    assert {c.principal for c in transport.captured} == PRINCIPALS
    assert all(c.subscriptions == [("rutautp/simulacion/estado", 1)] for c in transport.captured)
    assert all(not c.messages for c in transport.captured)


def test_observation_only_v1_scoped_topic_qos1_nonretained_and_one_inflight(transport):
    client = connected(transport)
    assert transport.publish(observation(), sample())
    assert not transport.publish(observation(), sample(.1))
    topic, payload, qos, retained = client.messages[0]
    assert topic == f"rutautp/simulacion/{RUN}/observaciones/sim-001/{SESSION}/posicion"
    assert payload == observation().payload() and len(payload) == 11
    assert qos == 1 and retained is False
    assert transport.counts()["inflight"] == 1
    client.on_publish(client, None, 1, 0, None)
    assert transport.counts()["publishAcks"] == 1
    assert transport.publish(observation(.2), sample(.2))


def test_no_publish_before_connack_suback_current_control(transport):
    transport.ensure_connections({"sim-001"}, sample())
    transport.service(sample())
    client = transport.channels["sim-001"].client
    assert not transport.publish(observation(), sample())
    client.on_connect(client, None, None, 0, None)
    assert not transport.publish(observation(), sample())
    client.on_subscribe(client, None, 21, [1], None)
    assert not transport.publish(observation(), sample())


@pytest.mark.parametrize("change", [dict(schemaVersion=True), dict(enabled=1), dict(controlRevision=True),
    dict(validUntil=1016), dict(issuedAt=1001), dict(issuedAt=float("nan")), dict(timeZone="UTC"),
    dict(runId="x"), dict(serviceEndsAt=1010), dict(extra=1)])
def test_malformed_or_future_control_rejected(change):
    with pytest.raises((ValueError, TypeError)):
        parse_control(json.dumps(body(**change)).encode(), 1000)


@pytest.mark.parametrize("change", [dict(enabled=False, validUntil=1000), dict(controlRevision=4), dict(runId=OTHER_RUN)])
def test_disable_new_revision_or_wrong_run_revokes_all_before_socket_write(transport, change):
    client = connected(transport)
    client.on_message(client, None, SimpleNamespace(topic="rutautp/simulacion/estado",
                      payload=json.dumps(body(**change)).encode()))
    assert transport.revoked and not transport.publish(observation(), sample())
    transport.service(sample())
    assert transport.closed and client.closed


def test_old_control_ignored_and_heartbeat_renews_same_revision(transport):
    client = connected(transport)
    transport.sample = sample(5)
    for value in (body(5), body(0), body(controlRevision=2)):
        client.on_message(client, None, SimpleNamespace(topic="rutautp/simulacion/estado", payload=json.dumps(value).encode()))
    assert transport.channels["sim-001"].lease["issuedAt"] == 1005
    assert transport.ready("sim-001", sample(19))
    assert not transport.ready("sim-001", sample(20))


def test_expired_inflight_destroyed_and_new_client_does_not_replay_it(transport):
    first = connected(transport)
    assert transport.publish(observation(), sample())
    transport.service(sample(10))
    assert first.closed and transport.channels["sim-001"].pending is None
    transport.ensure_connections({"sim-001"}, sample(10.9))
    assert len(transport.captured) == 1
    second = connected(transport, at=11.3)
    assert second is not first and second.client_id != first.client_id and not second.messages
    first.on_publish(first, None, 1, 0, None)
    first.on_message(first, None, SimpleNamespace(topic="rutautp/simulacion/estado",
                     payload=json.dumps(body(enabled=False, validUntil=1000)).encode()))
    assert not transport.revoked and transport.acknowledged == 0
    assert transport.publish(observation(11.3), sample(11.3))
    assert len(second.messages) == 1


def test_failed_publish_never_queues_or_reconnects_same_paho_instance(transport):
    client = connected(transport)
    client.rc = 4
    assert not transport.publish(observation(), sample())
    assert client.closed and transport.channels["sim-001"].client is None


def test_reconnect_backoff_doubles_and_caps_at_sixty_seconds(transport):
    current = sample()
    for expected in (1, 2, 4, 8, 16, 32, 60, 60):
        transport.sample = current
        transport.discard("sim-001")
        delay = transport.channels["sim-001"].retry_at - current.monotonic
        assert expected <= delay <= min(60, expected + .25)
        current = sample(current.monotonic - 100 + delay)


def test_only_one_dial_can_be_pending_and_shutdown_closes_late_connect(transport):
    transport.dialer = Dialer(complete=False)
    transport.ensure_connections(set(PRINCIPALS), sample())
    transport.ensure_connections(set(PRINCIPALS), sample())
    assert len(transport.captured) == 1
    client = transport.captured[0]
    transport.close()
    assert not client.closed
    transport.dialer.futures[0].set_result(0)
    assert client.closed and not client.messages


def credentials_file(tmp_path, **changes):
    path = tmp_path / "credentials.json"
    value = {"schemaVersion": 1, "host": "invalid.example", "port": 8883, "tls": True, "caFile": None,
             "accounts": {p: {"username": p, "password": "secret-" + p} for p in PRINCIPALS}, **changes}
    path.write_text(json.dumps(value))
    path.chmod(0o600)
    return path


def test_private_thirty_account_credentials_and_secret_safe_repr(tmp_path):
    parsed = load_credentials(credentials_file(tmp_path), PRINCIPALS)
    assert set(parsed.accounts) == PRINCIPALS
    assert "secret-" not in repr(parsed) and "secret-" not in repr(parsed.accounts["sim-001"])


@pytest.mark.parametrize("case", ["permissions", "missing", "phone", "shared", "duplicate", "symlink", "nan"])
def test_invalid_credentials_never_fall_back_or_leak_secrets(tmp_path, case):
    path = credentials_file(tmp_path)
    content = json.loads(path.read_text())
    if case == "permissions": path.chmod(0o644)
    elif case == "missing": content["accounts"].pop("sim-030")
    elif case == "phone": content["accounts"]["sim-001"]["username"] = "phone-account"
    elif case == "shared": content["accounts"]["sim-002"]["password"] = "secret-sim-001"
    elif case == "nan": content["port"] = float("nan")
    elif case == "symlink":
        link = tmp_path / "link.json"
        link.symlink_to(path)
        path = link
    if case not in ("permissions", "symlink"):
        path.write_text(json.dumps(content))
    if case == "duplicate": path.write_text('{"host":"secret-sim-001","host":"repeat"}')
    with pytest.raises((OSError, ValueError)) as error:
        load_credentials(path, PRINCIPALS)
    assert "secret-sim-001" not in str(error.value)


def test_real_paho_configuration_uses_public_api_and_never_connects(monkeypatch):
    import paho.mqtt.client as mqtt
    captured = []
    class ConfigClient:
        def __init__(self, **kwargs): self.configuration = kwargs; captured.append(self)
        def username_pw_set(self, username, password): self.username = username
        def max_queued_messages_set(self, value): self.queue = value
        def max_inflight_messages_set(self, value): self.inflight = value
        def tls_set_context(self, value): self.tls = value
    monkeypatch.setattr(mqtt, "Client", ConfigClient)
    client = paho_factory(settings())("sim-001", "unique")
    assert client.username == "sim-001" and client.queue == client.inflight == 1
    assert client.configuration["clean_session"] is True
    assert client.configuration["reconnect_on_failure"] is False
    assert client.tls.check_hostname and client.connect_timeout == 2


def test_revocation_read_precedes_all_pending_socket_writes(transport, monkeypatch):
    first = connected(transport)
    second = connected(transport, "sim-002")
    writes = []
    class Socket:
        def close(self): pass
    for client in (first, second):
        sock = Socket()
        client.socket = lambda sock=sock: sock
        client.want_write = lambda: True
        client.loop_write = lambda client=client: writes.append(client.principal) or 0
    def revoke():
        first.on_message(first, None, SimpleNamespace(topic="rutautp/simulacion/estado",
            payload=json.dumps(body(enabled=False, validUntil=1000)).encode()))
        return 0
    first.loop_read = revoke
    monkeypatch.setattr("simulation.publisher.select.select", lambda *args: ([first.socket()], [], []))
    transport.service(sample())
    assert transport.closed and first.closed and second.closed and not writes


def test_expiry_drops_partial_socket_packet_before_loop_write(transport, monkeypatch):
    client = connected(transport)
    assert transport.publish(observation(), sample())
    writes = []
    class Socket:
        def close(self): pass
    sock = Socket()
    client.socket = lambda: sock
    client.want_write = lambda: True
    client.loop_write = lambda: writes.append(1) or 0
    monkeypatch.setattr("simulation.publisher.select.select", lambda *args: ([], [], []))
    transport.service(sample(10))
    assert client.closed and not writes


@pytest.mark.parametrize("reasons", [[], [0], [128]])
def test_subscription_refused_or_downgraded_never_publishes(transport, reasons):
    transport.ensure_connections({"sim-001"}, sample())
    transport.service(sample())
    client = transport.channels["sim-001"].client
    client.on_connect(client, None, None, 0, None)
    client.on_subscribe(client, None, 21, reasons, None)
    assert client.closed and not transport.publish(observation(), sample())


def test_missing_heartbeat_disconnects_at_expiry_even_without_inflight(transport):
    client = connected(transport)
    transport.service(sample(15))
    assert client.closed and not transport.ready("sim-001", sample(15))


def test_old_observation_is_not_queued(transport):
    client = connected(transport)
    assert not transport.publish(observation(), sample(10))
    assert not client.messages and transport.channels["sim-001"].pending is None
