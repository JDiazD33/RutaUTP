"""Pruebas del latido y de la comprobación de salud (B04 y Q03).

El objetivo de esta pieza es que un supervisor pueda distinguir tres
situaciones que antes se confundían: el puente está sano, está vivo pero
desconectado del broker, o se detuvo. Cada una tiene su prueba.
"""

from __future__ import annotations

import json
from pathlib import Path

from rutautp_backend.bridge import Bridge
from rutautp_backend.config import Config
from rutautp_backend.gtfs import GtfsFeed
from rutautp_backend.health import (
    check_health,
    read_heartbeat,
    remove_heartbeat,
    write_heartbeat,
)
from rutautp_backend.__main__ import main

NOW = 1_700_000_000.0


class TestEscrituraYLectura:
    def test_ida_y_vuelta(self, tmp_path: Path):
        destino = str(tmp_path / "health.json")

        write_heartbeat(destino, {"at": NOW, "connected": True})

        assert read_heartbeat(destino) == {"at": NOW, "connected": True}

    def test_no_deja_archivos_temporales(self, tmp_path: Path):
        """La escritura es atómica: nada de JSON a medio escribir."""
        destino = str(tmp_path / "health.json")

        write_heartbeat(destino, {"at": NOW})

        sobrantes = [p.name for p in tmp_path.iterdir() if p.name != "health.json"]

        assert sobrantes == []

    def test_crea_el_directorio_si_falta(self, tmp_path: Path):
        destino = str(tmp_path / "sub" / "dir" / "health.json")

        write_heartbeat(destino, {"at": NOW})

        assert Path(destino).is_file()

    def test_ruta_vacia_no_hace_nada(self, tmp_path: Path):
        write_heartbeat("", {"at": NOW})
        remove_heartbeat("")

        assert list(tmp_path.iterdir()) == []

    def test_json_corrupto_no_lanza(self, tmp_path: Path):
        destino = tmp_path / "health.json"
        destino.write_text("{esto no es json", encoding="utf-8")

        assert read_heartbeat(str(destino)) is None

    def test_un_fallo_de_escritura_no_lanza(self, tmp_path: Path):
        """Un disco lleno no debe tumbar el puente."""
        bloqueado = tmp_path / "archivo"
        bloqueado.write_text("x", encoding="utf-8")

        # El "directorio" es en realidad un archivo: `mkdir` fallará.
        write_heartbeat(str(bloqueado / "health.json"), {"at": NOW})

    def test_remove_borra_el_latido(self, tmp_path: Path):
        destino = str(tmp_path / "health.json")
        write_heartbeat(destino, {"at": NOW})

        remove_heartbeat(destino)

        assert not Path(destino).exists()

    def test_remove_sobre_algo_que_no_existe_no_lanza(self, tmp_path: Path):
        remove_heartbeat(str(tmp_path / "no-existe.json"))


class TestComprobacionDeSalud:
    def test_sin_latido_esta_enfermo(self, tmp_path: Path):
        sano, detalle = check_health(str(tmp_path / "nada.json"), 30.0, now=NOW)

        assert sano is False
        assert "no llegó a arrancar o se detuvo" in detalle

    def test_latido_fresco_y_conectado_esta_sano(self, tmp_path: Path):
        destino = str(tmp_path / "health.json")
        write_heartbeat(destino, {"at": NOW - 1, "connected": True})

        sano, detalle = check_health(destino, 30.0, now=NOW)

        assert sano is True
        assert "sano" in detalle

    def test_latido_viejo_esta_enfermo(self, tmp_path: Path):
        """El proceso existe pero dejó de ciclar: es el caso que un `pgrep`
        no distingue."""
        destino = str(tmp_path / "health.json")
        write_heartbeat(destino, {"at": NOW - 120, "connected": True})

        sano, detalle = check_health(destino, 30.0, now=NOW)

        assert sano is False
        assert "dejó de ciclar" in detalle

    def test_desconectado_del_broker_esta_enfermo(self, tmp_path: Path):
        destino = str(tmp_path / "health.json")
        write_heartbeat(destino, {"at": NOW, "connected": False})

        sano, detalle = check_health(destino, 30.0, now=NOW)

        assert sano is False
        assert "desconectado del broker" in detalle

    def test_comprobacion_desactivada_siempre_esta_sana(self, tmp_path: Path):
        sano, detalle = check_health("", 30.0, now=NOW)

        assert sano is True
        assert "desactivada" in detalle

    def test_marca_de_tiempo_booleana_no_cuela(self, tmp_path: Path):
        """`bool` es subclase de `int`; `True` no es una marca de tiempo."""
        destino = str(tmp_path / "health.json")
        write_heartbeat(destino, {"at": True, "connected": True})

        sano, _ = check_health(destino, 30.0, now=NOW)

        assert sano is False


class TestLatidoDelPuente:
    def test_tick_escribe_el_latido(self, feed: GtfsFeed, tmp_path: Path):
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file=str(tmp_path / "health.json"),
        )
        bridge = Bridge(config=config, feed=feed)

        bridge.tick(NOW, connected=True)

        latido = read_heartbeat(config.health_file)

        assert latido is not None
        assert latido["at"] == NOW
        assert latido["connected"] is True
        assert latido["vehicles"] == 0

    def test_el_latido_refleja_la_desconexion(self, feed: GtfsFeed, tmp_path: Path):
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file=str(tmp_path / "health.json"),
        )
        bridge = Bridge(config=config, feed=feed)

        bridge.tick(NOW, connected=False)

        sano, detalle = check_health(config.health_file, 30.0, now=NOW)

        assert sano is False
        assert "desconectado" in detalle

    def test_sin_estado_conocido_no_se_declara_desconectado(
        self, feed: GtfsFeed, tmp_path: Path
    ):
        """Una prueba que no tiene broker no debe parecer una caída real."""
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file=str(tmp_path / "health.json"),
        )
        bridge = Bridge(config=config, feed=feed)

        bridge.tick(NOW)

        latido = read_heartbeat(config.health_file)

        assert latido is not None
        assert "connected" not in latido

        sano, _ = check_health(config.health_file, 30.0, now=NOW)

        assert sano is True

    def test_la_ultima_publicacion_queda_registrada(
        self, feed: GtfsFeed, tmp_path: Path
    ):
        """Q03: distinguir «no hay pasajeros» de «dejó de publicar»."""
        config = Config(
            gtfs_dir=feed.source_dir,
            database_path="",
            health_file=str(tmp_path / "health.json"),
        )
        bridge = Bridge(config=config, feed=feed)

        bridge.tick(NOW, connected=True)

        assert read_heartbeat(config.health_file)["lastPublishAt"] is None


class TestLineaDeComandos:
    """`--health-check` es lo que invocará el supervisor, así que se ejecuta."""

    def test_sin_latido_devuelve_uno(self, tmp_path: Path, monkeypatch):
        monkeypatch.setenv("BACKEND_HEALTH_FILE", str(tmp_path / "nada.json"))

        assert main(["--health-check"]) == 1

    def test_con_latido_fresco_devuelve_cero(self, tmp_path: Path, monkeypatch):
        destino = tmp_path / "health.json"
        destino.write_text(
            json.dumps({"at": __import__("time").time(), "connected": True}),
            encoding="utf-8",
        )
        monkeypatch.setenv("BACKEND_HEALTH_FILE", str(destino))

        assert main(["--health-check"]) == 0
