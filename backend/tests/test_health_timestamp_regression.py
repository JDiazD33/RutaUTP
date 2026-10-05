"""E23: el supervisor no acepta latidos con fechas inválidas o futuras.

Se leen JSON reales en un directorio temporal. Ninguna prueba usa el latido,
la base de datos, el entorno MQTT ni el feed operativos.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import pytest

from rutautp_backend import __main__ as cli
from rutautp_backend import health
from rutautp_backend.config import Config

NOW = 1_700_000_000.0
MAX_AGE = 30.0
EXPECTED_SKEW = 5.0
MISSING = object()

# También se prueban exponentes de JSON válido: json.loads("1e400") produce
# infinito sin que el archivo contenga la extensión no estándar Infinity.
INVALID_NUMBERS = [
    pytest.param("NaN", id="nan"),
    pytest.param("Infinity", id="positive-infinity"),
    pytest.param("-Infinity", id="negative-infinity"),
    pytest.param(str(10**400), id="positive-integer-overflow"),
    pytest.param(str(-(10**400)), id="negative-integer-overflow"),
    pytest.param("1e400", id="positive-json-exponent-overflow"),
    pytest.param("-1e400", id="negative-json-exponent-overflow"),
]


def write_raw_timestamp(directory: Path, token: str) -> Path:
    target = directory / "health.json"
    target.write_text(
        '{"at": ' + token + ', "connected": true}', encoding="utf-8"
    )
    return target


def write_payload(directory: Path, at=NOW, connected=True) -> Path:
    payload = {}
    if at is not MISSING:
        payload["at"] = at
    if connected is not MISSING:
        payload["connected"] = connected
    target = directory / "health.json"
    target.write_text(json.dumps(payload), encoding="utf-8")
    return target


def assert_unhealthy(target: Path) -> str:
    healthy, detail = health.check_health(str(target), MAX_AGE, now=NOW)
    assert healthy is False
    assert isinstance(detail, str) and detail
    assert not detail.startswith("sano:")
    return detail


@pytest.mark.parametrize("token", INVALID_NUMBERS)
def test_invalid_numbers_fail_without_escaping_exception(tmp_path: Path, token: str):
    assert_unhealthy(write_raw_timestamp(tmp_path, token))


@pytest.mark.parametrize(
    "at",
    [
        pytest.param(MISSING, id="missing"),
        pytest.param(None, id="null"),
        pytest.param(True, id="true-is-not-a-timestamp"),
        pytest.param(False, id="false-is-not-a-timestamp"),
        pytest.param(str(NOW), id="numeric-string"),
        pytest.param([NOW], id="array"),
        pytest.param({"value": NOW}, id="object"),
    ],
)
def test_timestamp_type_contract_is_preserved(tmp_path: Path, at):
    assert_unhealthy(write_payload(tmp_path, at=at))


@pytest.mark.parametrize(
    ("at", "expected"),
    [
        pytest.param(NOW, True, id="present"),
        pytest.param(NOW + 1.0, True, id="minor-clock-shift"),
        pytest.param(NOW + 4.999, True, id="inside-tolerance"),
        pytest.param(NOW + EXPECTED_SKEW, True, id="exact-inclusive-limit"),
        pytest.param(
            math.nextafter(NOW + EXPECTED_SKEW, math.inf),
            False,
            id="next-representable-value-outside-limit",
        ),
        pytest.param(NOW + 1_000_000_000.0, False, id="distant-future"),
        pytest.param(float.fromhex("0x1.fffffffffffffp+1023"), False, id="max-float"),
    ],
)
def test_future_tolerance_has_an_inclusive_five_second_boundary(
    tmp_path: Path, at: float, expected: bool
):
    target = write_payload(tmp_path, at=at)

    healthy, detail = health.check_health(str(target), MAX_AGE, now=NOW)

    assert healthy is expected
    assert isinstance(detail, str) and detail


@pytest.mark.parametrize(
    ("at", "expected"),
    [
        pytest.param(int(NOW) - 1, True, id="finite-integer"),
        pytest.param(NOW - 29.999, True, id="inside-age-limit"),
        pytest.param(NOW - MAX_AGE, True, id="exact-inclusive-age-limit"),
        pytest.param(
            math.nextafter(NOW - MAX_AGE, -math.inf),
            False,
            id="next-representable-value-too-old",
        ),
        pytest.param(NOW - 60.0, False, id="old-heartbeat"),
    ],
)
def test_expiration_still_uses_strict_greater_than(
    tmp_path: Path, at: float, expected: bool
):
    target = write_payload(tmp_path, at=at)

    healthy, detail = health.check_health(str(target), MAX_AGE, now=NOW)

    assert healthy is expected
    if not expected:
        assert "dejó de ciclar" in detail


@pytest.mark.parametrize(
    ("connected", "expected"),
    [
        pytest.param(MISSING, True, id="unknown-state-omitted"),
        pytest.param(True, True, id="connected"),
        pytest.param(False, False, id="explicitly-disconnected"),
        pytest.param(None, True, id="null-is-not-false"),
        pytest.param(0, True, id="zero-is-not-false"),
        pytest.param("false", True, id="string-is-not-false"),
        pytest.param({}, True, id="falsey-object-is-not-false"),
    ],
)
def test_only_explicit_false_means_disconnected(
    tmp_path: Path, connected, expected: bool
):
    target = write_payload(tmp_path, connected=connected)

    healthy, detail = health.check_health(str(target), MAX_AGE, now=NOW)

    assert healthy is expected
    if not expected:
        assert "desconectado del broker" in detail


@pytest.mark.parametrize("path", ["", " ", "\t\n"])
def test_disabled_health_never_reads_or_creates_a_heartbeat(
    tmp_path: Path, monkeypatch, path: str
):
    def unexpected_read(_path):
        pytest.fail("la comprobación desactivada intentó leer un latido")

    monkeypatch.setattr(health, "read_heartbeat", unexpected_read)

    healthy, detail = health.check_health(path, MAX_AGE, now=NOW)

    assert healthy is True
    assert "desactivada" in detail
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize(
    "token",
    [
        pytest.param(str(NOW), id="healthy"),
        pytest.param("NaN", id="non-finite"),
        pytest.param(str(10**400), id="overflow"),
        pytest.param(str(NOW + 6.0), id="future"),
    ],
)
def test_health_check_is_read_only_even_when_timestamp_is_invalid(
    tmp_path: Path, token: str
):
    target = write_raw_timestamp(tmp_path, token)
    (tmp_path / "health.json.tmp").write_bytes(b"sentinela temporal ajena")
    (tmp_path / "sentinel.bin").write_bytes(b"\x00\xffdatos vecinos\x00")
    before = {
        path.name: (path.read_bytes(), path.stat().st_mtime_ns)
        for path in tmp_path.iterdir()
    }

    health.check_health(str(target), MAX_AGE, now=NOW)

    after = {
        path.name: (path.read_bytes(), path.stat().st_mtime_ns)
        for path in tmp_path.iterdir()
    }
    assert after == before


def test_missing_heartbeat_is_not_recreated(tmp_path: Path):
    target = tmp_path / "absent" / "health.json"

    assert_unhealthy(target)

    assert list(tmp_path.iterdir()) == []


def isolate_health_cli(monkeypatch, tmp_path: Path, health_file: str) -> None:
    """Usa la rama CLI real con configuración validada y recursos ficticios."""
    config = Config.from_env(
        {
            "GTFS_DIR": str(tmp_path / "feed-inexistente"),
            "BACKEND_DB_PATH": "",
            "BACKEND_HEALTH_FILE": health_file,
            "BACKEND_HEALTH_MAX_AGE_S": str(MAX_AGE),
        }
    )
    monkeypatch.setattr(cli.Config, "from_env", staticmethod(lambda: config))
    monkeypatch.setattr(health.time, "time", lambda: NOW)

    def unexpected_feed(_path):
        pytest.fail("--health-check intentó cargar GTFS")

    def unexpected_bridge(*args, **kwargs):
        pytest.fail("--health-check intentó arrancar el puente")

    monkeypatch.setattr(cli, "load_feed", unexpected_feed)
    monkeypatch.setattr(cli, "Bridge", unexpected_bridge)


@pytest.mark.parametrize("token", INVALID_NUMBERS)
def test_cli_reports_invalid_timestamps_as_unhealthy_instead_of_crashing(
    tmp_path: Path, monkeypatch, capsys, token: str
):
    target = write_raw_timestamp(tmp_path, token)
    isolate_health_cli(monkeypatch, tmp_path, str(target))

    exit_code = cli.main(["--health-check", "--plain-logs"])

    captured = capsys.readouterr()
    assert exit_code == cli.EXIT_UNHEALTHY
    assert captured.out == ""
    assert captured.err.startswith("salud FALLA: ")


@pytest.mark.parametrize("disabled", [False, True], ids=["fresh", "disabled"])
def test_cli_healthy_and_disabled_contracts_stay_successful(
    tmp_path: Path, monkeypatch, capsys, disabled: bool
):
    target = write_payload(tmp_path)
    isolate_health_cli(monkeypatch, tmp_path, "" if disabled else str(target))

    exit_code = cli.main(["--health-check", "--plain-logs"])

    captured = capsys.readouterr()
    assert exit_code == cli.EXIT_OK
    assert captured.err == ""
    assert captured.out.startswith("salud OK: ")
    if disabled:
        assert "desactivada" in captured.out


@pytest.mark.parametrize(
    "raw",
    [
        pytest.param(
            b'{"at": 1700000000, "connected": true, "x": "\xff"}',
            id="invalid-utf8",
        ),
        pytest.param(
            b'{"at": ' + b"9" * 5000 + b', "connected": true}',
            id="json-integer-over-parser-digit-limit",
        ),
    ],
)
def test_unreadable_health_files_fail_in_checker_and_cli_without_modifying_file(
    tmp_path: Path, monkeypatch, capsys, raw: bytes
):
    target = tmp_path / "health.json"
    target.write_bytes(raw)
    before = (target.read_bytes(), target.stat().st_mtime_ns)

    assert_unhealthy(target)
    isolate_health_cli(monkeypatch, tmp_path, str(target))
    exit_code = cli.main(["--health-check", "--plain-logs"])

    captured = capsys.readouterr()
    assert exit_code == cli.EXIT_UNHEALTHY
    assert captured.out == ""
    assert captured.err.startswith("salud FALLA: ")
    assert (target.read_bytes(), target.stat().st_mtime_ns) == before
    assert {path.name for path in tmp_path.iterdir()} == {"health.json"}
