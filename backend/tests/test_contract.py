"""Pruebas del contrato entre el servidor Python y el cliente Swift.

Estas pruebas leen los `struct` reales del proyecto de Xcode y comparan sus
campos con los que produce y consume el backend.

Es la prueba más valiosa del conjunto: un nombre mal escrito no rompe nada de
forma visible. El `JSONDecoder` del teléfono descartaría el mensaje en silencio
y el mapa se quedaría vacío sin un solo error en los registros.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from rutautp_backend.models import OBSERVATION_FIELDS, EstimatedVehicle
from rutautp_backend.simulation_models import DataOrigin, SourceContext

REPO_ROOT = Path(__file__).resolve().parents[2]

MQTT_TRACKING_PROVIDER = (
    REPO_ROOT / "RutaUTP/Services/Tracking/Providers/MQTTTrackingProvider.swift"
)
VEHICLE_TRACKING_RECEPTION = REPO_ROOT / 'RutaUTP/Services/Tracking/Models/VehicleTrackingReception.swift'
MQTT_OBSERVATION_PUBLISHER = (
    REPO_ROOT / "RutaUTP/Services/Tracking/Publishers/MQTTObservationPublisher.swift"
)


def swift_struct_fields(path: Path, struct_name: str) -> set[str]:
    """Nombres de las propiedades `let` de un `struct` de Swift.

    Se descartan los comentarios antes de buscar: si no, un `// let ...` dentro
    de un comentario contaría como campo.

    Si el archivo no existe, la prueba **falla**. Antes hacía `skip`, y eso
    convertía el caso más peligroso —que alguien mueva o renombre el archivo del
    contrato— en un resultado verde que no verificaba nada. Una prueba que se
    salta a sí misma no protege de nada.
    """
    if not path.is_file():
        pytest.fail(
            f"no se encontró {path}: la comprobación del contrato no puede "
            "saltarse, porque un contrato sin verificar es indistinguible de "
            "uno roto"
        )

    source = path.read_text(encoding="utf-8")
    source = re.sub(r"//[^\n]*", "", source)

    marker = f"struct {struct_name}"

    assert marker in source, f"no existe {marker} en {path.name}"

    start = source.index(marker)
    opening = source.index("{", start)

    depth = 0
    body = ""

    for index in range(opening, len(source)):
        character = source[index]

        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1

            if depth == 0:
                body = source[opening + 1 : index]
                break

    return set(re.findall(r"\blet\s+(\w+)\s*:", body))


def swift_vehicle_wire_fields() -> tuple[set[str], set[str]]:
    """S07 reemplazó el DTO plano por claves explícitas de red v1/v2."""
    assert VEHICLE_TRACKING_RECEPTION.is_file(), 'falta el decodificador Swift de red'
    assert 'VehicleTrackingWire.position' in MQTT_TRACKING_PROVIDER.read_text(encoding='utf-8')
    source = re.sub(r'//[^\n]*', '', VEHICLE_TRACKING_RECEPTION.read_text(encoding='utf-8'))
    assert 'struct VehiclePositionWire: Decodable' in source
    body = source.split('struct VehiclePositionWire: Decodable', 1)[1]
    keys = re.search(r'enum Keys: String, CodingKey\s*\{([^}]+)\}', body)
    legacy = re.search(r'let legacyKeys: Set<String>\s*=\s*\[([^]]+)\]', body)
    assert keys is not None and legacy is not None, 'el contrato de red dejó de declarar sus claves'
    v2 = {key.strip() for line in keys[1].splitlines() if 'case ' in line
          for key in line.split('case ', 1)[1].split(',')}
    return set(re.findall(r'"([^"]+)"', legacy[1])), v2 - {"scenarioOccupancy", "occupancyScriptVersion"}


class TestSalidaVehicular:
    """Lo que publica el backend debe encajar con el decoder de red actual."""

    def test_las_claves_coinciden_con_el_cliente(self):
        esperadas, _ = swift_vehicle_wire_fields()

        vehicle = EstimatedVehicle(
            vehicle_id="17350695-01",
            route_id="17350695",
            linea="C-01",
            lat=-8.1,
            lon=-79.03,
            speed=8.0,
            heading=90.0,
            timestamp=1_700_000_000.0,
            last_seen=1_700_000_000.0,
        )

        publicadas = set(vehicle.to_vehicle_position().keys())

        assert publicadas == esperadas, (
            "el contrato de salida no coincide con el struct Swift: "
            f"sobran {publicadas - esperadas}, faltan {esperadas - publicadas}"
        )

    def test_el_cliente_exige_las_claves_incluso_si_admiten_null(self):
        vehicle = EstimatedVehicle(
            vehicle_id="x",
            route_id="x",
            linea="x",
            lat=0.0,
            lon=0.0,
            speed=-1.0,
            heading=-1.0,
            timestamp=0.0,
            last_seen=0.0,
        )

        payload = vehicle.to_vehicle_position_v2(SourceContext(DataOrigin.OBSERVED))
        _, required = swift_vehicle_wire_fields()
        assert set(payload) == required
        assert payload['simulationRunId'] is None and payload['controlRevision'] is None

    @pytest.mark.parametrize('origin', [DataOrigin.OBSERVED, DataOrigin.SIMULATED])
    def test_salida_v2_coincide_con_claves_swift(self, origin):
        run = '5bdb08e8-e971-4a9e-a18e-47f359841321'
        source = SourceContext(origin, run if origin is DataOrigin.SIMULATED else None)
        vehicle = EstimatedVehicle(vehicle_id=f'sim:{run}:bus' if source.run_id else 'observed-bus',
            route_id='route', linea='T', lat=-8.1, lon=-79.03, speed=0, heading=-1,
            timestamp=1700000000, last_seen=1700000000)
        payload = vehicle.to_vehicle_position_v2(source, 3 if source.run_id else None)
        _, required = swift_vehicle_wire_fields()
        assert set(payload) == required
        assert payload['schemaVersion'] == 2 and payload['dataOrigin'] == origin.value
        assert payload['simulationRunId'] == source.run_id

    def test_los_tipos_son_numericos_donde_el_cliente_espera_dobles(self):
        vehicle = EstimatedVehicle(
            vehicle_id="x",
            route_id="x",
            linea="C-01",
            lat=-8.1,
            lon=-79.03,
            speed=8.5,
            heading=90.0,
            timestamp=1_700_000_000.5,
            last_seen=0.0,
        )

        payload = vehicle.to_vehicle_position()

        for key in ("lat", "lon", "speed", "heading", "timestamp"):
            assert isinstance(payload[key], float), f"{key} debe ser Double"

        assert isinstance(payload["vehicleId"], str)
        assert isinstance(payload["linea"], str)

    def test_la_carga_util_es_json_valido(self):
        import json

        vehicle = EstimatedVehicle(
            vehicle_id="17350695-01",
            route_id="17350695",
            linea="C-01",
            lat=-8.1,
            lon=-79.03,
            speed=8.0,
            heading=90.0,
            timestamp=1_700_000_000.0,
            last_seen=0.0,
        )

        decoded = json.loads(vehicle.encode())

        assert decoded["vehicleId"] == "17350695-01"


class TestEntradaDeObservaciones:
    """Lo que el backend exige debe ser lo que el cliente publica."""

    def test_los_campos_exigidos_coinciden_con_el_cliente(self):
        publicados = swift_struct_fields(
            MQTT_OBSERVATION_PUBLISHER, "PassengerObservationPayload"
        )

        exigidos = set(OBSERVATION_FIELDS.keys())

        assert exigidos == publicados, (
            "el contrato de entrada no coincide con el struct Swift: "
            f"sobran {exigidos - publicados}, faltan {publicados - exigidos}"
        )

    def test_los_nombres_usan_camelCase(self):
        """El cliente codifica con las claves tal cual, sin convertidor."""
        for field_name in OBSERVATION_FIELDS:
            assert "_" not in field_name, (
                f"{field_name} parece snake_case; el cliente usa camelCase"
            )

        assert "sessionId" in OBSERVATION_FIELDS
        assert "schemaVersion" in OBSERVATION_FIELDS
