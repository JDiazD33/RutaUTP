"""E19: el formato elegido por el entorno debe llegar al registro real del CLI.

Las comprobaciones usan un feed GTFS pequeño y no construyen el puente MQTT.
Los informes de salud conservan su texto para los supervisores y los niveles
del registro siguen filtrando mensajes independientemente del formato.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import pytest

import rutautp_backend.__main__ as cli


@pytest.fixture(autouse=True)
def isolate_cli_logging(monkeypatch):
    """`main` sustituye handlers: recuperar los de pytest al terminar cada caso."""
    root = logging.getLogger()
    previous_handlers = root.handlers[:]
    previous_level = root.level

    monkeypatch.delenv("BACKEND_LOG_JSON", raising=False)
    monkeypatch.setenv("BACKEND_LOG_LEVEL", "INFO")
    monkeypatch.setenv("BACKEND_DB_PATH", "")
    monkeypatch.setenv("BACKEND_HEALTH_FILE", "")
    monkeypatch.setenv("MQTT_TLS", "0")
    monkeypatch.setenv("MQTT_CA_CERT", "")
    monkeypatch.setenv("MQTT_USERNAME", "")
    monkeypatch.setenv("MQTT_PASSWORD", "")

    def forbidden_bridge(*args, **kwargs):
        raise AssertionError("estas comprobaciones no deben construir el puente")

    monkeypatch.setattr(cli, "Bridge", forbidden_bridge)

    try:
        yield
    finally:
        for handler in root.handlers[:]:
            if handler not in previous_handlers:
                root.removeHandler(handler)
                handler.close()
        root.handlers[:] = previous_handlers
        root.setLevel(previous_level)


@pytest.fixture
def tiny_feed(tmp_path: Path, monkeypatch) -> Path:
    feed = tmp_path / "gtfs"
    feed.mkdir()
    (feed / "routes.txt").write_text(
        "route_id,route_short_name,agency_id\nA,C-01,1\nB,C-02,1\n",
        encoding="utf-8",
    )
    (feed / "trips.txt").write_text(
        "trip_id,route_id,shape_id\ntA,A,shapeA\ntB,B,shapeB\n",
        encoding="utf-8",
    )
    (feed / "shapes.txt").write_text(
        "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n"
        "shapeA,-8.1000,-79.0300,1\nshapeA,-8.1010,-79.0310,2\n"
        "shapeB,-8.1100,-79.0400,1\nshapeB,-8.1110,-79.0410,2\n",
        encoding="utf-8",
    )
    (feed / "agency.txt").write_text(
        "agency_id,agency_name,agency_url,agency_timezone\n"
        "1,Empresa de prueba,https://example.invalid,America/Lima\n",
        encoding="utf-8",
    )
    (feed / "stops.txt").write_text(
        "stop_id,stop_name,stop_lat,stop_lon\n", encoding="utf-8"
    )
    (feed / "stop_times.txt").write_text(
        "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n",
        encoding="utf-8",
    )
    (feed / "frequencies.txt").write_text(
        "trip_id,start_time,end_time,headway_secs\n", encoding="utf-8"
    )
    monkeypatch.setenv("GTFS_DIR", str(feed))
    return feed


def log_messages(stderr: str, *, as_json: bool, level: str) -> list[str]:
    """Comprueba líneas emitidas, sin sustituir el formateador ni el logger."""
    lines = stderr.splitlines()
    assert lines

    if as_json:
        records = [json.loads(line) for line in lines]
        for record in records:
            assert record["level"] == level
            assert record["logger"] == "rutautp_backend"
            assert isinstance(record["at"], (int, float))
            assert isinstance(record["message"], str)
        return [record["message"] for record in records]

    for line in lines:
        assert not line.startswith("{")
        assert level in line
        assert "rutautp_backend:" in line
    return lines


@pytest.mark.parametrize(
    ("env_json", "plain_logs", "expect_json"),
    [
        (None, False, True),
        (None, True, False),
        ("0", False, False),
        ("0", True, False),
        ("1", False, True),
        ("1", True, False),
    ],
    ids=[
        "default-json",
        "default-cli-plain",
        "env-plain",
        "env-and-cli-plain",
        "env-json",
        "cli-overrides-json",
    ],
)
def test_check_respects_environment_and_cli_format(
    tiny_feed, monkeypatch, capsys, env_json, plain_logs, expect_json
):
    if env_json is not None:
        monkeypatch.setenv("BACKEND_LOG_JSON", env_json)

    args = ["--check"] + (["--plain-logs"] if plain_logs else [])
    assert cli.main(args) == cli.EXIT_OK

    captured = capsys.readouterr()
    assert captured.out == ""
    messages = log_messages(captured.err, as_json=expect_json, level="INFO")
    assert any("feed cargado desde" in message for message in messages)
    assert any("línea C-01" in message for message in messages)
    assert any("línea C-02" in message for message in messages)
    assert any(
        "todas las rutas tienen geometría usable" in message for message in messages
    )


@pytest.mark.parametrize("env_json", ["0", "1"], ids=["plain", "json"])
def test_feed_errors_keep_the_exit_code_and_selected_format(
    tmp_path, monkeypatch, capsys, env_json
):
    monkeypatch.setenv("BACKEND_LOG_JSON", env_json)
    monkeypatch.setenv("GTFS_DIR", str(tmp_path / "missing-feed"))

    assert cli.main(["--check"]) == cli.EXIT_CONFIG

    captured = capsys.readouterr()
    assert captured.out == ""
    messages = log_messages(captured.err, as_json=env_json == "1", level="ERROR")
    assert len(messages) == 1
    assert "no se pudo cargar el feed" in messages[0]


@pytest.mark.parametrize("env_json", ["0", "1"], ids=["plain", "json"])
def test_warning_threshold_still_filters_info_and_reports_unusable_routes(
    tiny_feed, monkeypatch, capsys, env_json
):
    (tiny_feed / "shapes.txt").write_text(
        "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n"
        "shapeA,-8.1000,-79.0300,1\nshapeA,-8.1010,-79.0310,2\n"
        "shapeB,-8.1100,-79.0400,1\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("BACKEND_LOG_JSON", env_json)
    monkeypatch.setenv("BACKEND_LOG_LEVEL", "WARNING")

    assert cli.main(["--check"]) == cli.EXIT_FEED_UNUSABLE

    captured = capsys.readouterr()
    assert captured.out == ""
    messages = log_messages(captured.err, as_json=env_json == "1", level="WARNING")
    assert len(messages) == 1
    assert "ruta(s) sin geometría usable: B" in messages[0]
    assert "feed cargado desde" not in captured.err
    assert "línea C-01" not in captured.err


@pytest.mark.parametrize("env_json", ["0", "1"], ids=["plain", "json"])
@pytest.mark.parametrize("healthy", [True, False], ids=["healthy", "disconnected"])
def test_health_report_stays_plain_and_does_not_load_or_modify_other_data(
    tmp_path, monkeypatch, capsys, env_json, healthy
):
    heartbeat = tmp_path / "health.json"
    original = json.dumps({"at": time.time(), "connected": healthy}).encode("utf-8")
    heartbeat.write_bytes(original)
    monkeypatch.setenv("BACKEND_LOG_JSON", env_json)
    monkeypatch.setenv("BACKEND_HEALTH_FILE", str(heartbeat))
    monkeypatch.setenv("GTFS_DIR", str(tmp_path / "missing-feed"))

    def forbidden_feed(*args, **kwargs):
        raise AssertionError("el informe de salud no debe cargar el feed")

    monkeypatch.setattr(cli, "load_feed", forbidden_feed)

    expected_exit = cli.EXIT_OK if healthy else cli.EXIT_UNHEALTHY
    assert cli.main(["--health-check"]) == expected_exit

    captured = capsys.readouterr()
    if healthy:
        assert captured.out.startswith("salud OK: sano:")
        assert captured.err == ""
    else:
        assert captured.out == ""
        assert captured.err.startswith(
            "salud FALLA: el backend está vivo pero desconectado"
        )
    assert not (captured.out + captured.err).startswith("{")
    assert heartbeat.read_bytes() == original
