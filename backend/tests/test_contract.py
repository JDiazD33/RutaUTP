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

REPO_ROOT = Path(__file__).resolve().parents[2]

MQTT_TRACKING_PROVIDER = (
    REPO_ROOT / "RutaUTP/Services/Tracking/Providers/MQTTTrackingProvider.swift"
)
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


class TestSalidaVehicular:
    """Lo que el backend publica debe encajar con `VehiclePositionMessage`."""

    def test_las_claves_coinciden_con_el_cliente(self):
        esperadas = swift_struct_fields(
            MQTT_TRACKING_PROVIDER, "VehiclePositionMessage"
        )

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

    def test_el_cliente_no_tiene_campos_opcionales(self):
        """Un campo ausente haría fallar el `Decodable` entero.

        En Swift, `let speed: Double` (sin `?`) obliga a que la clave exista
        siempre. Si el backend omitiera una, el mensaje se descartaría.
        """
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

        payload = vehicle.to_vehicle_position()

        for key in swift_struct_fields(MQTT_TRACKING_PROVIDER, "VehiclePositionMessage"):
            assert key in payload

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
