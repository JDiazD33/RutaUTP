"""Pruebas del histórico SQLite (`persistence.py`).

Este módulo tenía **cero cobertura** pese a que el README lo da por funcional y
a que sostiene garantías concretas: una transacción por segundo, un disco que
falla sin tumbar el puente, y una retención que no borra por defecto. Nada de
eso estaba comprobado.

Se usan bases de datos en directorios temporales, nunca la del repositorio.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from rutautp_backend.models import EstimatedVehicle, Observation, RejectReason
from rutautp_backend.persistence import (
    MAX_DETAIL_LENGTH,
    ObservationStore,
    default_database_path,
    open_store,
)

NOW = 1_700_000_000.0


def make_observation(*, now: float = NOW, session: str = "s-1") -> Observation:
    return Observation(
        session_id=session,
        route_id="17350695",
        linea="C-01",
        lat=-8.11,
        lon=-79.006,
        speed=8.0,
        heading=170.0,
        accuracy=8.0,
        motion_activity="automotive",
        timestamp=now,
        distance_to_route_m=3.5,
        heading_diff_deg=4.2,
        progress=0.51,
    )


def make_vehicle() -> EstimatedVehicle:
    return EstimatedVehicle(
        vehicle_id="17350695-t0-01",
        route_id="17350695",
        linea="C-01",
        lat=-8.11,
        lon=-79.006,
        speed=8.0,
        heading=170.0,
        timestamp=NOW,
        last_seen=NOW,
        progress=0.51,
        route_length_m=34_200.0,
    )


@pytest.fixture
def store(tmp_path: Path) -> ObservationStore:
    almacen = ObservationStore(tmp_path / "historico.sqlite")

    yield almacen

    almacen.close()


class TestSinPersistencia:
    def test_una_ruta_vacia_desactiva_el_almacen(self):
        """`BACKEND_DB_PATH=` debe permitir correr sin escribir en disco."""
        almacen = open_store("", 0.0)

        assert almacen.enabled is False

    def test_un_almacen_desactivado_no_escribe_nada(self, tmp_path: Path):
        almacen = ObservationStore(None)

        almacen.record_observation(make_observation(), "v-1", NOW)
        almacen.record_rejection(RejectReason.MALFORMED_JSON, "detalle", NOW)
        almacen.record_vehicle(make_vehicle(), NOW)
        almacen.flush()
        almacen.prune(NOW)

        assert almacen.query("SELECT * FROM observations") == []
        assert almacen.counts.observations == 0

    def test_cerrar_un_almacen_desactivado_no_falla(self):
        ObservationStore(None).close()


class TestEsquema:
    def test_crea_las_tres_tablas(self, store: ObservationStore):
        nombres = {
            fila[0]
            for fila in store.query(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }

        assert {"observations", "rejections", "vehicle_positions"} <= nombres

    def test_crea_el_directorio_si_falta(self, tmp_path: Path):
        destino = tmp_path / "sub" / "dir" / "historico.sqlite"

        almacen = ObservationStore(destino)

        assert destino.is_file()

        almacen.close()

    def test_activa_wal(self, store: ObservationStore):
        """WAL permite leer mientras se escribe y aguanta mejor un corte."""
        assert store.query("PRAGMA journal_mode")[0][0].lower() == "wal"

    def test_una_ruta_imposible_no_tumba_el_arranque(self, tmp_path: Path):
        """No poder guardar el histórico no debe impedir el puente."""
        ocupado = tmp_path / "archivo"
        ocupado.write_text("x", encoding="utf-8")

        almacen = ObservationStore(ocupado / "historico.sqlite")

        assert almacen.enabled is False


class TestEscritura:
    def test_guarda_la_observacion_con_todos_sus_campos(
        self, store: ObservationStore
    ):
        observacion = make_observation()

        store.record_observation(observacion, "17350695-t0-01", NOW)
        store.flush()

        filas = store.query(
            "SELECT session_id, route_id, linea, lat, lon, distance_to_route_m, "
            "heading_diff_deg, progress, vehicle_id, observed_at FROM observations"
        )

        assert len(filas) == 1

        (
            session_id,
            route_id,
            linea,
            lat,
            lon,
            distancia,
            rumbo,
            progress,
            vehicle_id,
            observed_at,
        ) = filas[0]

        assert session_id == "s-1"
        assert route_id == "17350695"
        assert linea == "C-01"
        assert lat == pytest.approx(-8.11)
        assert lon == pytest.approx(-79.006)
        assert distancia == pytest.approx(3.5)
        assert rumbo == pytest.approx(4.2)
        assert progress == pytest.approx(0.51)
        assert vehicle_id == "17350695-t0-01"
        assert observed_at == pytest.approx(NOW)

    def test_guarda_el_rechazo_con_su_motivo(self, store: ObservationStore):
        store.record_rejection(RejectReason.TOO_FAR_FROM_ROUTE, "1200 m", NOW)
        store.flush()

        filas = store.query("SELECT reason, detail FROM rejections")

        assert filas == [("too_far_from_route", "1200 m")]

    def test_trunca_el_detalle_del_rechazo(self, store: ObservationStore):
        """Un mensaje manipulado de 10 MB no debe acabar almacenado entero."""
        store.record_rejection(
            RejectReason.MESSAGE_TOO_LARGE, "x" * 5_000, NOW
        )
        store.flush()

        detalle = store.query("SELECT detail FROM rejections")[0][0]

        assert len(detalle) == MAX_DETAIL_LENGTH

    def test_guarda_la_posicion_vehicular(self, store: ObservationStore):
        store.record_vehicle(make_vehicle(), NOW)
        store.flush()

        filas = store.query(
            "SELECT vehicle_id, route_id, sessions, samples FROM vehicle_positions"
        )

        assert filas == [("17350695-t0-01", "17350695", 0, 0)]

    def test_cuenta_las_filas_escritas(self, store: ObservationStore):
        store.record_observation(make_observation(), "v-1", NOW)
        store.record_observation(make_observation(session="s-2"), "v-1", NOW)
        store.record_rejection(RejectReason.DUPLICATE, "", NOW)
        store.record_vehicle(make_vehicle(), NOW)

        assert store.counts.observations == 2
        assert store.counts.rejections == 1
        assert store.counts.vehicle_positions == 1
        assert store.counts.write_errors == 0

    def test_las_claves_del_resumen_son_las_esperadas(self, store: ObservationStore):
        assert set(store.counts.as_dict()) == {
            "dbObservations",
            "dbRejections",
            "dbVehiclePositions",
            "dbWriteErrors",
        }


class TestConfirmacion:
    def test_sin_pendientes_no_hay_nada_que_confirmar(self, store: ObservationStore):
        store.flush()
        store.flush()

        assert store.counts.write_errors == 0

    def test_lo_escrito_es_visible_desde_otra_conexion_tras_confirmar(
        self, store: ObservationStore, tmp_path: Path
    ):
        """Es la garantía de «una transacción por segundo»: hasta el `commit`,
        otra conexión no ve los datos; después, sí."""
        store.record_observation(make_observation(), "v-1", NOW)

        otra = sqlite3.connect(str(tmp_path / "historico.sqlite"))

        try:
            sin_confirmar = otra.execute(
                "SELECT COUNT(*) FROM observations"
            ).fetchone()[0]

            store.flush()

            tras_confirmar = otra.execute(
                "SELECT COUNT(*) FROM observations"
            ).fetchone()[0]
        finally:
            otra.close()

        assert sin_confirmar == 0
        assert tras_confirmar == 1


class TestResistencia:
    def test_un_fallo_de_escritura_no_lanza_ni_detiene_el_puente(
        self, store: ObservationStore
    ):
        """La garantía documentada: un disco lleno no debe tumbar el mapa."""
        # Se rompe la conexión por dentro a propósito: es la única forma de
        # reproducir el fallo de disco que la documentación promete tolerar.
        store._connection.close()  # noqa: SLF001

        store.record_observation(make_observation(), "v-1", NOW)
        store.record_rejection(RejectReason.DUPLICATE, "", NOW)
        store.record_vehicle(make_vehicle(), NOW)

        assert store.counts.write_errors == 3
        assert store.counts.observations == 0

    def test_el_cierre_es_idempotente(self, tmp_path: Path):
        almacen = ObservationStore(tmp_path / "historico.sqlite")

        almacen.close()
        almacen.close()

        assert almacen.enabled is False


class TestRetencion:
    def test_sin_retencion_no_borra_nada(self, store: ObservationStore):
        """El valor por defecto es no borrar nunca, y debe respetarse."""
        store.record_observation(make_observation(), "v-1", NOW - 400 * 86_400)
        store.flush()

        assert store.prune(NOW) == 0
        assert store.query("SELECT COUNT(*) FROM observations")[0][0] == 1

    def test_borra_lo_anterior_a_la_retencion(self, tmp_path: Path):
        almacen = ObservationStore(tmp_path / "h.sqlite", retention_days=1.0)

        # La retención mira la fecha de **registro** (`at`), no la de la
        # medición: es cuánto tiempo se conserva lo que ya se guardó.
        almacen.record_observation(make_observation(), "v-1", NOW - 5 * 86_400)
        almacen.record_observation(make_observation(), "v-1", NOW)
        almacen.flush()

        borradas = almacen.prune(NOW)

        assert borradas == 1
        assert almacen.query("SELECT COUNT(*) FROM observations")[0][0] == 1

        almacen.close()

    def test_una_medicion_vieja_registrada_ahora_no_se_poda(self, tmp_path: Path):
        """Se fija la decisión: la antigüedad de la medición no decide nada.

        Un teléfono puede publicar una observación con marca de tiempo antigua
        —dentro del margen que acepta la validación— y se registra ahora. La
        retención no debe borrarla por eso.
        """
        almacen = ObservationStore(tmp_path / "h.sqlite", retention_days=1.0)

        almacen.record_observation(
            make_observation(now=NOW - 400 * 86_400), "v-1", NOW
        )
        almacen.flush()

        assert almacen.prune(NOW) == 0

        almacen.close()

    def test_respeta_el_intervalo_entre_pasadas(self, tmp_path: Path):
        """La retención no debe ejecutarse en cada ciclo de mantenimiento."""
        almacen = ObservationStore(tmp_path / "h.sqlite", retention_days=1.0)

        almacen.record_observation(make_observation(), "v-1", NOW - 5 * 86_400)
        almacen.flush()

        assert almacen.prune(NOW) == 1

        almacen.record_observation(make_observation(), "v-1", NOW - 5 * 86_400)
        almacen.flush()

        # Dentro del intervalo no se vuelve a mirar.
        assert almacen.prune(NOW + 10) == 0

        # Pasado el intervalo, sí.
        assert almacen.prune(NOW + 3_601) == 1

        almacen.close()

    def test_los_rechazos_tambien_se_podan(self, tmp_path: Path):
        almacen = ObservationStore(tmp_path / "h.sqlite", retention_days=1.0)

        almacen.record_rejection(RejectReason.DUPLICATE, "", NOW - 5 * 86_400)
        almacen.flush()

        assert almacen.prune(NOW) == 1

        almacen.close()

    def test_las_posiciones_vehiculares_tambien_se_podan(self, tmp_path: Path):
        almacen = ObservationStore(tmp_path / "h.sqlite", retention_days=1.0)

        almacen.record_vehicle(make_vehicle(), NOW - 5 * 86_400)
        almacen.flush()

        assert almacen.prune(NOW) == 1

        almacen.close()


class TestApertura:
    def test_expande_el_directorio_personal(self, tmp_path: Path):
        almacen = open_store(str(tmp_path / "h.sqlite"), 0.0)

        assert almacen.enabled is True

        almacen.close()

    def test_la_ruta_por_defecto_vive_junto_al_paquete(self):
        ruta = default_database_path()

        assert ruta.name == "rutautp.sqlite"
        assert ruta.parent.name == "data"
