"""Regresiones E22 del puente demo: 48 casos, sin conexiones MQTT.

Se ejecutan Bash y Python reales. PATH contiene únicamente Python, cat y dos
clientes MQTT dobles que registran argumentos y emiten observaciones propias.
Cada proceso recibe un entorno explícito y directorios temporales exclusivos;
no hereda credenciales, rutas operativas ni configuración del servicio.

E22_BRIDGE_SCRIPT permite probar una copia anterior del script sin reemplazar
la fuente actual. Estos tests verifican reenvío, contrato y límites de argv;
no acreditan la ACL de un broker ni validación GTFS del puente inseguro.
"""

from __future__ import annotations

import csv
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import textwrap

import pytest

from rutautp_backend.gtfs import parse_short_name


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIDGE_SCRIPT = Path(
    os.environ.get("E22_BRIDGE_SCRIPT", str(REPO_ROOT / "mqtt/puente-demo.sh"))
).resolve()
SWIFT_PROVIDER = (
    REPO_ROOT / "RutaUTP/Services/Tracking/Providers/MQTTTrackingProvider.swift"
)
KNOWN_ROUTES = ("17350695", "17419574")
MISSING_ROUTE = object()


def _rows(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as source:
        yield from csv.DictReader(source)


@pytest.fixture(scope="module")
def real_routes() -> dict[str, dict]:
    """Obtiene línea y vértice del feed que la app incluye como recurso."""
    gtfs = REPO_ROOT / "gtfs"
    route_rows = {
        row["route_id"]: row
        for row in _rows(gtfs / "routes.txt")
        if row["route_id"] in KNOWN_ROUTES
    }
    assert set(route_rows) == set(KNOWN_ROUTES), "ambas rutas deben existir"
    shape_by_route = {
        row["route_id"]: row["shape_id"]
        for row in _rows(gtfs / "trips.txt")
        if row["route_id"] in KNOWN_ROUTES
    }
    assert set(shape_by_route) == set(KNOWN_ROUTES)
    first_points = {}
    for row in _rows(gtfs / "shapes.txt"):
        if row["shape_id"] in shape_by_route.values():
            if int(row["shape_pt_sequence"]) == 0:
                first_points[row["shape_id"]] = (
                    float(row["shape_pt_lat"]), float(row["shape_pt_lon"])
                )
        if len(first_points) == len(KNOWN_ROUTES):
            break
    assert set(first_points) == set(shape_by_route.values())
    return {
        route_id: {
            "routeId": route_id,
            "linea": parse_short_name(row["route_short_name"])[0],
            "point": first_points[shape_by_route[route_id]],
        }
        for route_id, row in route_rows.items()
    }


def _observation(route: dict, *, session: str = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"):
    latitude, longitude = route["point"]
    return {
        "schemaVersion": 1,
        "sessionId": session,
        "routeId": route["routeId"],
        "linea": route["linea"],
        "lat": latitude,
        "lon": longitude,
        "speed": 8.25,
        "heading": 17.5,
        "accuracy": 8.0,
        "motionActivity": "automotive",
        "timestamp": 1_800_000_010.25,
    }


def _harness(tmp_path: Path, observations: list[dict]) -> dict:
    root = tmp_path / "demo case with spaces"
    root.mkdir()
    bin_dir = root / "allowed executables"
    bin_dir.mkdir()
    temporary = root / "temporary files"
    temporary.mkdir()
    source = root / "observations.txt"
    source.write_text(
        "".join(
            "rutautp/observaciones/demo-device/"
            + observation["sessionId"]
            + "/posicion "
            + json.dumps(observation, ensure_ascii=False)
            + "\n"
            for observation in observations
        ),
        encoding="utf-8",
    )
    sub_capture = root / "subscriber-argv.json"
    pub_capture = root / "publisher-argv.jsonl"
    double = root / "client-double.py"
    double.write_text(
        textwrap.dedent(
            """\
            import json, os, sys
            from pathlib import Path
            mode, arguments = sys.argv[1], sys.argv[2:]
            if mode == "sub":
                Path(os.environ["E22_SUB_CAPTURE"]).write_text(
                    json.dumps(arguments), encoding="utf-8"
                )
                sys.stdout.write(Path(os.environ["E22_INPUT"]).read_text(encoding="utf-8"))
            elif mode == "pub":
                with open(os.environ["E22_PUB_CAPTURE"], "a", encoding="utf-8") as capture:
                    capture.write(json.dumps(arguments) + "\\n")
            else:
                raise SystemExit(97)
            """
        ),
        encoding="utf-8",
    )
    python = str(Path(sys.executable).resolve())
    # Wrappers use an absolute interpreter, including paths containing spaces.
    for command, mode in (("mosquitto_sub", "sub"), ("mosquitto_pub", "pub")):
        wrapper = bin_dir / command
        wrapper.write_text(
            "#!/bin/sh\nexec "
            + shlex.quote(python)
            + " "
            + shlex.quote(str(double))
            + " "
            + mode
            + ' "$@"\n',
            encoding="utf-8",
        )
        wrapper.chmod(0o700)
    (bin_dir / "python3").symlink_to(python)
    cat = shutil.which("cat")
    assert cat is not None, "la advertencia del puente requiere cat"
    (bin_dir / "cat").symlink_to(Path(cat).resolve())
    # A glob in credentials must remain literal even when it could match files.
    (root / "glob-expansion-sentinel").write_text("fixture", encoding="utf-8")
    return {
        "root": root,
        "sub_capture": sub_capture,
        "pub_capture": pub_capture,
        "environment": {
            "PATH": str(bin_dir),
            "LANG": "C",
            "PYTHONUTF8": "1",
            "TMPDIR": str(temporary),
            "E22_INPUT": str(source),
            "E22_SUB_CAPTURE": str(sub_capture),
            "E22_PUB_CAPTURE": str(pub_capture),
        },
    }


def _run(harness: dict, *, arguments=(), flag="1", authentication=None):
    assert BRIDGE_SCRIPT.is_file(), f"no existe el puente candidato: {BRIDGE_SCRIPT}"
    environment = dict(harness["environment"])
    if flag is not None:
        environment["PUENTE_DEMO_INSECURE"] = flag
    if authentication:
        environment.update(authentication)
    return subprocess.run(
        ["/bin/bash", str(BRIDGE_SCRIPT), *arguments],
        cwd=harness["root"],
        env=environment,
        text=True,
        capture_output=True,
        timeout=15,
        check=False,
    )


def _publications(harness: dict) -> list[list[str]]:
    capture = harness["pub_capture"]
    if not capture.is_file():
        return []
    return [json.loads(line) for line in capture.read_text(encoding="utf-8").splitlines()]


def _position(arguments: list[str]) -> dict:
    # There must be a single topic/message pair, without injected extra options.
    assert arguments.count("-t") == 1
    assert arguments.count("-m") == 1
    return json.loads(arguments[arguments.index("-m") + 1])


def _swift_message_fields() -> dict[str, str]:
    source = SWIFT_PROVIDER.read_text(encoding="utf-8")
    source = re.sub(r"//[^\n]*", "", source)
    body = re.search(
        r"\bstruct\s+VehiclePositionMessage\s*:\s*Decodable\s*\{(.*?)^\}",
        source,
        flags=re.DOTALL | re.MULTILINE,
    )
    assert body is not None, "debe existir el DTO real del proveedor MQTT"
    return dict(re.findall(r"\blet\s+(\w+)\s*:\s*(\w+\??)", body.group(1)))


# 5 cases: refusal must occur before either external MQTT executable is called.
@pytest.mark.parametrize("flag", (None, "0", "true", "01", ""), ids=("absent", "zero", "true", "01", "empty"))
def test_demo_guard_rejects_without_explicit_one(tmp_path, real_routes, flag):
    harness = _harness(tmp_path, [_observation(real_routes[KNOWN_ROUTES[0]])])
    result = _run(harness, flag=flag)
    assert result.returncode == 1, (result.stdout, result.stderr)
    assert "PUENTE_DEMO_INSECURE" in result.stderr
    assert not harness["sub_capture"].exists()
    assert not harness["pub_capture"].exists()


# 2 cases: the forwarded contract must support more than one real route.
@pytest.mark.parametrize("route_id,expected_line", (("17350695", "C-01"), ("17419574", "C-06")))
def test_real_gtfs_route_is_forwarded_with_swift_required_fields(tmp_path, real_routes, route_id, expected_line):
    route = real_routes[route_id]
    assert route["linea"] == expected_line
    observation = _observation(route)
    harness = _harness(tmp_path, [observation])
    result = _run(harness)
    assert result.returncode == 0, (result.stdout, result.stderr)
    publications = _publications(harness)
    assert len(publications) == 1
    position = _position(publications[0])
    fields = _swift_message_fields()
    assert fields["routeId"] == "String", "la ruta sigue siendo obligatoria en Swift"
    assert set(position) == set(fields)
    assert position == {
        "vehicleId": "baliza-aaaaaaaa",
        **{key: observation[key] for key in fields if key != "vehicleId"},
    }


# 10 cases: absence becomes null; existing values retain both value and type.
@pytest.mark.parametrize(
    "route_id",
    (MISSING_ROUTE, None, 17350695, True, {"id": "17350695"}, ["17350695"], "", "unknown-route", " 17350695 ", 'route ID "interno"'),
    ids=("missing", "null", "number", "boolean", "object", "array", "empty", "unknown", "spaces", "internal-characters"),
)
def test_demo_does_not_coerce_or_invent_route_id(tmp_path, real_routes, route_id):
    observation = _observation(real_routes[KNOWN_ROUTES[0]])
    if route_id is MISSING_ROUTE:
        del observation["routeId"]
    else:
        observation["routeId"] = route_id
    harness = _harness(tmp_path, [observation])
    result = _run(harness)
    assert result.returncode == 0, (result.stdout, result.stderr)
    publications = _publications(harness)
    assert len(publications) == 1
    position = _position(publications[0])
    assert "routeId" in position
    expected = None if route_id is MISSING_ROUTE else route_id
    assert position["routeId"] == expected
    assert type(position["routeId"]) is type(expected)
    assert position["linea"] == observation["linea"]


# 5 cases: compatibility must not silently add validation to the unsafe demo.
@pytest.mark.parametrize(
    "field,value",
    (("lat", 9999.125), ("lon", -9999.25), ("speed", 500.5), ("heading", 765.25), ("timestamp", -123.5)),
)
def test_demo_preserves_observed_numeric_values(tmp_path, real_routes, field, value):
    observation = _observation(real_routes[KNOWN_ROUTES[0]])
    observation[field] = value
    harness = _harness(tmp_path, [observation])
    result = _run(harness)
    assert result.returncode == 0, (result.stdout, result.stderr)
    publications = _publications(harness)
    assert len(publications) == 1
    position = _position(publications[0])
    for key in ("linea", "lat", "lon", "speed", "heading", "timestamp"):
        assert position[key] == observation[key]


# 4 cases: line labels come from the producer, never from a guessed route.
@pytest.mark.parametrize("line", ("", "mismatch-fixture", " C-01 ", 'Línea "con espacios"'))
def test_demo_preserves_line_without_synthesizing_it(tmp_path, real_routes, line):
    observation = _observation(real_routes[KNOWN_ROUTES[0]])
    observation["linea"] = line
    harness = _harness(tmp_path, [observation])
    result = _run(harness)
    assert result.returncode == 0, (result.stdout, result.stderr)
    publications = _publications(harness)
    assert len(publications) == 1
    assert _position(publications[0])["linea"] == line


# 1 case: each publication retains its route, body ID, topic ID and reading time.
def test_multiple_observations_keep_body_and_topic_identity(tmp_path, real_routes):
    first = _observation(real_routes[KNOWN_ROUTES[0]])
    second = _observation(real_routes[KNOWN_ROUTES[1]], session="bbbbbbbb-cccc-dddd-eeee-ffffffffffff")
    older = dict(first, timestamp=first["timestamp"] - 5, speed=-1, heading=-1)
    observations = [first, second, older]
    harness = _harness(tmp_path, observations)
    result = _run(harness)
    assert result.returncode == 0, (result.stdout, result.stderr)
    publications = _publications(harness)
    assert len(publications) == len(observations)
    for arguments, observation in zip(publications, observations, strict=True):
        position = _position(arguments)
        vehicle_id = "baliza-" + observation["sessionId"][:8]
        assert position["vehicleId"] == vehicle_id
        assert arguments[arguments.index("-t") + 1] == f"rutautp/vehiculos/{vehicle_id}/posicion"
        assert position["routeId"] == observation["routeId"]
        assert position["linea"] == observation["linea"]
        assert position["timestamp"] == observation["timestamp"]
        assert position["speed"] == observation["speed"]
        assert position["heading"] == observation["heading"]


AUTH_CASES = (
    {},
    {"MQTT_PASS": "ignored-without-user"},
    {"MQTT_USER": "demo-bridge", "MQTT_PASS": "fixture-pass"},
    {"MQTT_USER": "demo-bridge"},
    {"MQTT_USER": "demo bridge", "MQTT_PASS": "fixture pass with spaces"},
    {"MQTT_USER": "*", "MQTT_PASS": "*"},
    {"MQTT_USER": "demo -t rogue/topic", "MQTT_PASS": "pass -t rogue/topic -m injected"},
)


# 21 cases: defaults/custom/TLS times seven credential boundaries.
@pytest.mark.parametrize("arguments", ((), ("fixture.invalid", "28883"), ("fixture.invalid", "28883", "--tls")), ids=("default", "custom", "tls"))
@pytest.mark.parametrize("authentication", AUTH_CASES, ids=("none", "password-only", "normal", "empty-pass", "spaces", "globs", "option-tokens"))
def test_client_argv_keeps_authentication_values_as_single_arguments(tmp_path, real_routes, arguments, authentication):
    observation = _observation(real_routes[KNOWN_ROUTES[0]])
    harness = _harness(tmp_path, [observation])
    result = _run(harness, arguments=arguments, authentication=authentication)
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert harness["sub_capture"].is_file()
    subscriber = json.loads(harness["sub_capture"].read_text(encoding="utf-8"))
    publications = _publications(harness)
    assert len(publications) == 1
    publisher = publications[0]
    connection = ["-h", arguments[0] if arguments else "127.0.0.1", "-p", arguments[1] if arguments else "1883"]
    if len(arguments) == 3:
        connection += ["--cafile", "/etc/ssl/cert.pem"]
    if authentication.get("MQTT_USER"):
        connection += ["-u", authentication["MQTT_USER"], "-P", authentication.get("MQTT_PASS", "")]
    assert subscriber == [*connection, "-t", "rutautp/observaciones/#", "-v"]
    assert publisher[:len(connection)] == connection
    assert publisher[len(connection):len(connection) + 3] == ["-t", "rutautp/vehiculos/baliza-aaaaaaaa/posicion", "-m"]
    assert len(publisher) == len(connection) + 4
    assert json.loads(publisher[-1])["routeId"] == observation["routeId"]
