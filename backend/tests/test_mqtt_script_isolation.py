"""Los scripts MQTT aíslan la configuración y limpian incluso si fallan.

Se ejecuta Bash real, pero todos los ejecutables MQTT y el backend son dobles:
no se abre un socket ni se escribe ningún archivo operativo del servicio.
El doble de Python registra solo la configuración relevante y falla al arrancar
el backend. Esto permite comprobar las rutas de cierre de ambos scripts.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import textwrap

import pytest


BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = BACKEND_DIR.parent
SCRIPT_NAMES = ("smoke_test.sh", "reconnect_test.sh")
CONFIG_KEYS = (
    "BACKEND_DB_PATH",
    "BACKEND_HEALTH_FILE",
    "MQTT_HOST",
    "MQTT_PORT",
    "MQTT_TLS",
    "MQTT_CA_CERT",
    "MQTT_USERNAME",
    "MQTT_PASSWORD",
    "MQTT_CLIENT_ID",
    "GTFS_DIR",
    "BACKEND_OBSERVATIONS_TOPIC",
    "BACKEND_VEHICLES_TOPIC_PREFIX",
    "BACKEND_MIN_PUBLISH_PRINCIPALS",
)


def _executable(path: Path, source: str) -> Path:
    path.write_text(
        "#!/usr/bin/env python3\n" + textwrap.dedent(source), encoding="utf-8"
    )
    path.chmod(0o700)
    return path


def _harness(tmp_path: Path, *, with_spaces: bool) -> dict:
    root = tmp_path / ("case with spaces" if with_spaces else "case")
    root.mkdir()
    bin_dir = root / "double executables"
    bin_dir.mkdir()
    temporary = root / "temporary files"
    temporary.mkdir()
    capture = root / "backend-config.json"
    directories = root / "created-directories.jsonl"
    database = root / "protected.sqlite"
    heartbeat = root / "protected-health.json"
    database_bytes = b"protected database sentinel\x00\xff\n"
    health_bytes = b'{"owner":"another-instance","timestamp":12345}\n'
    database.write_bytes(database_bytes)
    heartbeat.write_bytes(health_bytes)
    real_mktemp = shutil.which("mktemp")
    assert real_mktemp is not None, "los scripts requieren mktemp"

    _executable(
        bin_dir / "mktemp",
        f"""
        import json, os, subprocess, sys
        arguments = sys.argv[1:]
        if arguments == ["-d"]:
            # BSD mktemp no garantiza usar TMPDIR para esta forma de llamada.
            # Una plantilla explícita mantiene el fixture dentro de tmp_path.
            arguments.append(os.path.join(os.environ["TEST_TEMP_ROOT"], "mqtt.XXXXXXXX"))
        result = subprocess.run(
            [{real_mktemp!r}, *arguments], capture_output=True, text=True
        )
        if result.returncode == 0:
            with open(os.environ["TEST_DIRECTORIES"], "a", encoding="utf-8") as log:
                log.write(json.dumps(result.stdout.strip()) + "\\n")
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
        """,
    )
    python_double = _executable(
        bin_dir / "python-double",
        f"""
        import json, os, sys
        from pathlib import Path
        if sys.argv[1:3] == ["-m", "rutautp_backend"]:
            record = {{
                "argv": sys.argv[1:],
                "config": {{key: os.environ.get(key) for key in {CONFIG_KEYS!r}}},
            }}
            Path(os.environ["TEST_CAPTURE"]).write_text(json.dumps(record), encoding="utf-8")
            raise SystemExit(23)
        if len(sys.argv) > 1 and sys.argv[1] == "-":
            print('{{"schemaVersion": 1, "sessionId": "double"}}')
            raise SystemExit(0)
        raise SystemExit(24)
        """,
    )
    for tool in ("mosquitto", "mosquitto_pub"):
        _executable(bin_dir / tool, "raise SystemExit(0)\n")
    _executable(bin_dir / "mosquitto_sub", "raise SystemExit(1)\n")
    _executable(
        bin_dir / "sleep",
        """
        import sys, time
        time.sleep(min(float(sys.argv[1]) / 20, 0.25))
        """,
    )
    # Lista explícita: no se heredan credenciales ni rutas del entorno de pytest.
    environment = {
        "PATH": os.pathsep.join((str(bin_dir), str(Path(sys.executable).parent), "/usr/bin", "/bin")),
        "LANG": "C",
        "TMPDIR": str(temporary),
        "PYTHON": str(python_double),
        "TEST_CAPTURE": str(capture),
        "TEST_DIRECTORIES": str(directories),
        "TEST_TEMP_ROOT": str(temporary),
    }
    return {
        "environment": environment,
        "capture": capture,
        "directories": directories,
        "temporary": temporary,
        "database": database,
        "heartbeat": heartbeat,
        "database_bytes": database_bytes,
        "health_bytes": health_bytes,
    }


def _run(script_name: str, harness: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/bin/bash", str(BACKEND_DIR / "tools" / script_name), "18899"],
        cwd=BACKEND_DIR,
        env=harness["environment"],
        text=True,
        capture_output=True,
        timeout=15,
        check=False,
    )


@pytest.mark.parametrize("script_name", SCRIPT_NAMES)
@pytest.mark.parametrize("hostile_environment", (False, True), ids=("unset", "hostile"))
@pytest.mark.parametrize("with_spaces", (False, True), ids=("plain-path", "spaces"))
def test_script_failure_isolates_data_and_broker_settings(
    tmp_path, script_name, hostile_environment, with_spaces
):
    harness = _harness(tmp_path, with_spaces=with_spaces)
    if hostile_environment:
        harness["environment"].update(
            {
                "BACKEND_DB_PATH": str(harness["database"]),
                "BACKEND_HEALTH_FILE": str(harness["heartbeat"]),
                "MQTT_HOST": "production.invalid",
                "MQTT_PORT": "8883",
                "MQTT_TLS": "1",
                "MQTT_CA_CERT": str(tmp_path / "parent-ca.pem"),
                "MQTT_USERNAME": "parent-user-fixture",
                "MQTT_PASSWORD": "parent-secret-fixture",
                "MQTT_CLIENT_ID": "parent-instance-fixture",
                "GTFS_DIR": str(tmp_path / "parent-feed"),
                "BACKEND_OBSERVATIONS_TOPIC": "another-service/observations/#",
                "BACKEND_VEHICLES_TOPIC_PREFIX": "another-service/vehicles",
            }
        )

    result = _run(script_name, harness)

    assert result.returncode == 1, (result.stdout, result.stderr)
    assert harness["capture"].is_file(), "el doble debe alcanzar el arranque del backend"
    record = json.loads(harness["capture"].read_text(encoding="utf-8"))
    created = [
        Path(json.loads(line))
        for line in harness["directories"].read_text(encoding="utf-8").splitlines()
    ]
    assert len(created) == 1
    work_dir = created[0]
    assert work_dir.parent == harness["temporary"]
    assert not work_dir.exists(), "EXIT debe borrar el directorio propio también en fallo"
    assert list(harness["temporary"].iterdir()) == []
    assert harness["database"].read_bytes() == harness["database_bytes"]
    assert harness["heartbeat"].read_bytes() == harness["health_bytes"]
    assert record["argv"] == ["-m", "rutautp_backend", "--plain-logs"]
    config = record["config"]
    assert config["BACKEND_DB_PATH"] == "", "el histórico se debe desactivar explícitamente"
    health_path = Path(config["BACKEND_HEALTH_FILE"] or "")
    assert health_path.is_absolute() and health_path.parent == work_dir
    assert config["MQTT_HOST"] == "127.0.0.1"
    assert config["MQTT_PORT"] == "18899"
    assert config["MQTT_TLS"] == "0"
    assert config["MQTT_CA_CERT"] == ""
    assert config["MQTT_USERNAME"] == ""
    assert config["MQTT_PASSWORD"] == ""
    assert config["MQTT_CLIENT_ID"] == ""
    assert config["GTFS_DIR"] == str(REPO_DIR / "gtfs")
    assert config["BACKEND_OBSERVATIONS_TOPIC"] == "rutautp/observaciones/+/+/posicion"
    assert config["BACKEND_VEHICLES_TOPIC_PREFIX"] == "rutautp/vehiculos"
    assert config["BACKEND_MIN_PUBLISH_PRINCIPALS"] == "2"


@pytest.mark.parametrize("script_name", SCRIPT_NAMES)
@pytest.mark.parametrize("invalid_quorum", ("0", "-1", "not-an-integer"))
def test_invalid_quorum_exits_before_creating_temporary_resources(
    tmp_path, script_name, invalid_quorum
):
    harness = _harness(tmp_path, with_spaces=True)
    harness["environment"]["BACKEND_MIN_PUBLISH_PRINCIPALS"] = invalid_quorum

    result = _run(script_name, harness)

    assert result.returncode == 1
    assert "BACKEND_MIN_PUBLISH_PRINCIPALS" in result.stderr
    assert not harness["capture"].exists()
    assert not harness["directories"].exists(), "validar antes de mktemp evita un directorio sin trap"
    assert list(harness["temporary"].iterdir()) == []
    assert harness["database"].read_bytes() == harness["database_bytes"]
    assert harness["heartbeat"].read_bytes() == harness["health_bytes"]
