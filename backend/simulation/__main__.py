"""CLI explícita S06. Sin subcomando solo muestra ayuda; no conecta al importar."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import sys
import threading

from rutautp_backend.config import DEFAULT_GTFS_DIR
from rutautp_backend.persistence import ObservationStore, SimulationPersistenceUnavailable
from rutautp_backend.simulation_control_store import ControlStore, ControlUnavailable
from rutautp_backend.simulation_profile import SimulationProfile, PROFILE_SPECS
from .actors import ActorRunner, LocalAuthority, ProducerLock, ProducerStopped, new_instance_id, validate_publication
from .clock import RealtimeClock
from .publisher import load_credentials, MqttTransport
from .scenario import ScenarioEngine


def build_parser():
    parser = argparse.ArgumentParser(description='Productor privado de balizas RutaUTP; apagado por defecto')
    parser.add_argument("--control-db", required=True, type=Path)
    parser.add_argument("--history-db", required=True, type=Path)
    parser.add_argument("--credentials-file", required=True, type=Path)
    parser.add_argument("--gtfs-dir", type=Path, default=Path(DEFAULT_GTFS_DIR))
    parser.add_argument("--profile", choices=tuple(PROFILE_SPECS), default="pasajeros-30")
    parser.add_argument("--reference-jsonl", type=Path, help="archivo nuevo explícito; nunca sobrescribe")
    parser.add_argument("command", choices=["check", "run"], help="check valida archivos; solo run abre MQTT")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    history = transport = lock = runner = reference = None
    clock = RealtimeClock()
    previous_signals = {}
    try:
        repository = Path(__file__).resolve().parents[2]
        credentials_path = args.credentials_file.absolute()
        if credentials_path.resolve().is_relative_to(repository):
            raise ValueError("las credenciales deben quedar fuera del repositorio")
        profile = SimulationProfile.load(args.profile, args.gtfs_dir)
        validate_publication(profile)
        settings = load_credentials(credentials_path, profile.principals)
        control = ControlStore(args.control_db)
        state = control.read()
        if args.command == "check":
            print(json.dumps({"configurationValid": True, "actors": len(profile.principals),
                "requestedEnabled": state["enabled"], "historyVerified": False,
                "networkStarted": False, "prerequisites": "S07/S08 y ACL/migración verificadas antes de run"}))
            return 0
        # En producción el operador debe haber completado S07/S08 y verificado
        # ACL/migración. S06 entrega el código; no habilita ni instala nada.
        authority = LocalAuthority(control, profile, state["runId"], state["revision"], state["owner"], args.gtfs_dir)
        authority.current(clock.read())
        lock = ProducerLock(control)
        history = ObservationStore(args.history_db, existing_only=True)
        history.require_simulation_run(state["runId"])
        engine = ScenarioEngine.from_profile(profile, args.gtfs_dir, state["runId"])
        instance = new_instance_id()
        transport = MqttTransport(profile.principals, state["runId"], state["revision"], settings, instance)
        if args.reference_jsonl is not None:
            descriptor = os.open(args.reference_jsonl, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            reference = os.fdopen(descriptor, "w", encoding="utf-8")
        runner = ActorRunner(engine, control, history, transport, authority, instance, lock, reference=reference, clock=clock)
        stopping = threading.Event()
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_signals[signum] = signal.signal(signum, lambda *_: stopping.set())
        runner.run(stopping, clock=clock)
        print(json.dumps({"producerStatus": "stopped", "reason": runner.reason,
                          "reservedPublishCallsRun": runner.calls}))
        return 0 if runner.reason == "operator_stop" else 2
    except (ControlUnavailable, SimulationPersistenceUnavailable, ProducerStopped,
            OSError, ValueError, TypeError, KeyError) as error:
        # Nunca imprimir excepciones Paho/configuración: pueden incluir secretos.
        print(json.dumps({"producerStatus": "not_running", "error": type(error).__name__}), file=sys.stderr)
        return 2
    finally:
        if runner is not None:
            runner.stop(clock.read(), "operator_stop")
        if transport is not None:
            transport.close()
        if history is not None:
            history.close()
        if lock is not None:
            lock.close()
        if reference is not None:
            reference.close()
        for signum, handler in previous_signals.items():
            signal.signal(signum, handler)


if __name__ == "__main__":
    raise SystemExit(main())
