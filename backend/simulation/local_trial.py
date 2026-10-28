"""Ensayo conectado con procesos/datos/cuentas nuevos.

Importar no arranca nada. La CLI run requiere ejecución deliberada. No lee .env,
credenciales existentes ni bases activas o EMQX. Loopback por defecto;
una IP privada explícita permite un observador iPhone deliberado.
"""

from __future__ import annotations

import argparse
from contextlib import ExitStack
import json
import ipaddress
import math
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid

from rutautp_backend.config import DEFAULT_GTFS_DIR
from rutautp_backend.health import read_heartbeat
from rutautp_backend.simulation_admin import status
from rutautp_backend.simulation_control_store import ControlStore, ControlUnavailable
from rutautp_backend.simulation_profile import PROFILE_SPECS, SimulationProfile
from rutautp_backend.simulation_reporting import run_report, export_comparison, history_reader
from .measurement import capture

HOST = '127.0.0.1'


def trial_host(value: str) -> str:
    address = ipaddress.IPv4Address(value)
    networks = ('127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')
    if not any(address in ipaddress.IPv4Network(n) for n in networks):
        raise ValueError('solo loopback o una interfaz IPv4 privada explícita')
    return str(address)


def private_json(path: Path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, allow_nan=False, indent=2)
        stream.write('\n')


def trial_disk(output: Path) -> dict:
    paths = ['history.sqlite', 'history.sqlite-wal', 'history.sqlite-shm', 'reference.jsonl']
    return {name: (output/name).stat().st_size if (output/name).exists() else 0 for name in paths}


def isolated_environment(root: Path, output: Path, port: int, password: str, host: str = HOST) -> dict:
    # Lista positiva: no heredar configuración de broker, histórico, APNs o pruebas.
    return {'PATH': os.environ.get('PATH', '/usr/bin:/bin'), 'LANG': 'C',
        'PYTHONPATH': str(root/'backend'), 'GTFS_DIR': str(root/'gtfs'),
        'MQTT_HOST': trial_host(host), 'MQTT_PORT': str(port), 'MQTT_TLS': '0',
        'MQTT_USERNAME': 'backend', 'MQTT_PASSWORD': password,
        'BACKEND_DB_PATH': str(output/'history.sqlite'), 'BACKEND_DB_RETENTION_DAYS': '0',
        'BACKEND_HEALTH_FILE': str(output/'health.json'),
        'BACKEND_SIMULATION_CONTROL_PATH': str(output/'control/control.sqlite'),
        'BACKEND_SIMULATION_INGRESS_ENABLED': '1', 'BACKEND_VEHICLE_POSITION_SCHEMA_VERSION': '2',
        'BACKEND_MIN_PUBLISH_PRINCIPALS': '2'}


def local_acl(principals) -> str:
    lines = ['user backend', 'topic read rutautp/observaciones/+/+/posicion',
        'topic read rutautp/simulacion/+/observaciones/+/+/posicion',
        'topic write rutautp/vehiculos/+/posicion', 'topic write rutautp/simulacion/estado',
        'topic write rutautp/cambios/estado', 'topic write rutautp/ocupacion/estado',
        'user reader', 'topic read rutautp/vehiculos/+/posicion', 'topic read rutautp/simulacion/estado']
    for principal in sorted(principals):
        lines.extend([f'user {principal}', 'topic read rutautp/simulacion/estado',
            f'topic write rutautp/simulacion/+/observaciones/{principal}/+/posicion'])
    return '\n'.join(lines)+'\n'


def probe_disable_delivery_seconds(snapshot: dict, requested_revision: int, requested_uptime: float):
    """Solo la entrega del OFF solicitado; otro OFF no mide esta operación."""
    body = snapshot.get('control') or {}
    seen = snapshot.get('controlSeenAtUptime')
    if (body.get('enabled') is not False or type(body.get('controlRevision')) is not int
            or body['controlRevision'] != requested_revision
            or type(seen) not in (int, float) or not math.isfinite(seen) or seen < requested_uptime):
        return None
    return seen-requested_uptime


def disable_measurements(before: dict, requested_revision: int, device: dict | None = None) -> dict:
    was_enabled = before.get('requestedEnabled') is True
    uninterrupted = requested_revision == before['controlRevision']+1
    usable = was_enabled and uninterrupted
    diagnostic = (device or {}).get('cleanupUpperBoundSeconds')
    valid_diagnostic = (type(diagnostic) in (int, float)
        and math.isfinite(diagnostic) and diagnostic >= 0)
    return {'controlWasEnabledBeforeDisable': was_enabled,
        'disableRequestedRevision': requested_revision,
        'automaticDisableReason': before.get('reason') if not was_enabled else None,
        'controlChangedBeforeManualDisable': not uninterrupted,
        'iosCleanupTimingUsable': usable and valid_diagnostic,
        'iosCleanupSeconds': diagnostic if usable and valid_diagnostic else None}


def wait_until(predicate, seconds: float = 30):
    deadline = time.monotonic()+seconds
    while time.monotonic() < deadline:
        try:
            if predicate(): return
        except (OSError, ValueError, KeyError, ControlUnavailable):
            pass
        time.sleep(.1)
    raise RuntimeError('prerrequisito local no confirmado dentro del plazo')


class Probe:
    """Lector Python de contraste. Nunca se presenta como recepción/limpieza iOS."""
    def __init__(self, port: int, password: str, host: str = HOST):
        import paho.mqtt.client as mqtt
        self.lock = threading.Lock()
        self.connected = False; self.control = None; self.control_seen = None
        self.positions = {}; self.received = 0; self.invalid = 0
        self.occupancy_counts = {}
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                                  client_id='s10-reader-'+uuid.uuid4().hex)
        self.client.username_pw_set('reader', password)
        def connected(client, userdata, flags, reason, properties):
            self.connected = reason == 0
            if self.connected:
                client.subscribe([('rutautp/simulacion/estado', 1), ('rutautp/vehiculos/+/posicion', 1)])
        def message(client, userdata, value):
            try:
                body = json.loads(value.payload)
                with self.lock:
                    if value.topic == 'rutautp/simulacion/estado':
                        self.control, self.control_seen = body, time.monotonic()
                    else:
                        expected = {'vehicleId', 'routeId', 'linea', 'lat', 'lon', 'heading', 'speed',
                            'timestamp', 'schemaVersion', 'dataOrigin', 'simulationRunId', 'controlRevision'}
                        version = body.get('schemaVersion')
                        if version == 3:
                            expected |= {'scenarioOccupancy', 'occupancyScriptVersion'}
                        occupancy_ok = version != 3 or (body.get('scenarioOccupancy') in ('empty', 'space', 'full')
                            and type(body.get('occupancyScriptVersion')) is int and body['occupancyScriptVersion'] == 1)
                        if (set(body) != expected or version not in (2, 3) or not occupancy_ok
                                or body['dataOrigin'] != 'simulated' or value.retain):
                            self.invalid += 1
                        else:
                            self.received += 1
                            self.positions[body['vehicleId']] = body
                            if version == 3:
                                state = body['scenarioOccupancy']
                                self.occupancy_counts[state] = self.occupancy_counts.get(state, 0) + 1
            except (ValueError, TypeError, KeyError):
                with self.lock: self.invalid += 1
        self.client.on_connect = connected; self.client.on_message = message
        self.client.connect(host, port, 20); self.client.loop_start()

    def snapshot(self):
        with self.lock:
            return {'connected': self.connected, 'control': self.control, 'controlSeenAtUptime': self.control_seen,
                'receivedPositions': self.received, 'estimatedIdsSeen': len(self.positions),
                'invalidPositions': self.invalid, 'scenarioOccupancyMessages': dict(self.occupancy_counts), 'readerKind': 'python_probe_not_iOS'}

    def close(self):
        self.client.disconnect(); self.client.loop_stop()


def verify_local_acl(host: str, port: int, accounts: dict[str, str], run_id: str) -> list[dict]:
    """PUBACK MQTT 5 real: no inferir permisos de una publicación capturada."""
    import paho.mqtt.client as mqtt
    actor = min(p for p in accounts if p.startswith('sim-'))
    results = []
    for user, topic in [(actor, f'rutautp/observaciones/{actor}/s10/posicion'),
                        ('reader', f'rutautp/simulacion/{run_id}/observaciones/{actor}/s10/posicion'),
                        (actor, 'rutautp/vehiculos/s10-denied/posicion'),
                        (actor, 'rutautp/simulacion/estado')]:
        connected = threading.Event(); published = threading.Event(); codes = []
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='s10-acl-'+uuid.uuid4().hex,
                             protocol=mqtt.MQTTv5)
        client.username_pw_set(user, accounts[user])
        client.on_connect = lambda _c, _u, _f, reason, _p: connected.set() if reason == 0 else None
        def acknowledged(_c, _u, _mid, reason, _p):
            codes.append(reason.value); published.set()
        client.on_publish = acknowledged
        try:
            client.connect(host, port, 20); client.loop_start()
            if not connected.wait(5): raise RuntimeError('no se confirmó conexión para verificar ACL')
            client.publish(topic, '{}', qos=1, retain=False)
            if not published.wait(5): raise RuntimeError('no se confirmó PUBACK de ACL')
            results.append({'user': user, 'topic': topic, 'pubackCode': codes[0], 'denied': codes[0] == 135})
        finally:
            client.disconnect(); client.loop_stop()
    if not all(r['denied'] for r in results): raise RuntimeError('una ACL local no rechazó la escritura')
    return results


def run_trial(output: Path, name: str, seconds: int, *, gtfs_dir: Path = Path(DEFAULT_GTFS_DIR),
              host: str = HOST, observer=None, scenario_occupancy: bool = False,
              control_only: bool = False, check_reconnect: bool = False,
              check_active_faults: bool = False) -> dict:
    root = Path(__file__).resolve().parents[2]
    output = output.expanduser().absolute()
    host = trial_host(host)
    if output.resolve().is_relative_to(root):
        raise ValueError('el ensayo requiere un directorio nuevo fuera del repositorio Git')
    if check_active_faults and (observer is None or name != 'pasajeros-30' or seconds != 35
            or control_only or check_reconnect or not scenario_occupancy):
        raise ValueError('active-faults requiere iPhone, pasajeros-30, ocupación, baseline de 35 s y modo exclusivo')
    profile = SimulationProfile.load(name, gtfs_dir)
    if type(seconds) is not int or not 10 <= seconds <= profile.max_run_seconds-30:
        raise ValueError('captura de al menos 10 s y margen de 30 s antes del máximo del perfil')
    if control_only and observer is None:
        raise ValueError('el diagnóstico sin actores requiere observador iPhone')
    if check_reconnect and not control_only:
        raise ValueError('la comprobación de reconexión aislada requiere control-only')
    if not control_only and not profile.window(time.time())[0]:
        raise ValueError('ensayo conectado solo dentro del horario del perfil')
    broker_exe, password_exe = shutil.which('mosquitto'), shutil.which('mosquitto_passwd')
    if not broker_exe or not password_exe:
        raise ValueError('faltan ejecutables locales de Mosquitto; no se instalan automáticamente')
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    accounts = {p: secrets.token_urlsafe(32) for p in [*sorted(profile.principals), 'backend', 'reader']}
    password_file = output/'passwords'; credentials_file = output/'actors-credentials.json'
    probe = None; children = []; control = None; report = {'complete': False, 'profile': name,
        'host': host, 'externalBrokerContacted': False, 'iPhoneMeasured': False, 'iosCleanupSeconds': None,
        'iosCleanupTimingUsable': False, 'captureEndedEarly': None,
        'localACLVerified': False, 'externalACLVerified': False, 'capturedSecondsRequested': seconds, 'failure': None}
    with ExitStack() as stack:
        hard_deadline = None
        def trial_wait(predicate, seconds=30):
            if check_active_faults and hard_deadline is not None:
                remaining = hard_deadline-20-time.monotonic()
                if remaining <= 0:
                    from .device_faults import ActiveFaultError
                    raise ActiveFaultError('global_deadline_exhausted')
                seconds = min(seconds,remaining)
            return wait_until(predicate,seconds)
        try:
            fd = os.open(password_file, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(fd, 'w') as passwords:
                passwords.write(''.join(f'{p}:{secret}\n' for p, secret in accounts.items()))
            hashed = subprocess.run([password_exe, '-U', str(password_file)], capture_output=True, timeout=30)
            if hashed.returncode: raise RuntimeError('no se pudieron preparar las cuentas temporales')
            password_file.chmod(0o600)
            (output/'acl').write_text(local_acl(profile.principals))
            with socket.socket() as reservation:
                reservation.bind((host, 0)); port = reservation.getsockname()[1]
            (output/'mosquitto.conf').write_text(f'listener {port} {host}\nallow_anonymous false\n'
                f'password_file {password_file}\nacl_file {output/"acl"}\npersistence false\nlog_type all\n')
            env = isolated_environment(root, output, port, accounts['backend'], host)
            env['GTFS_DIR'] = str(gtfs_dir)
            env['BACKEND_SIMULATION_OCCUPANCY_ENABLED'] = '1' if scenario_occupancy else '0'
            report['scenarioOccupancyEnabled'] = scenario_occupancy
            def spawn(command, filename):
                log = stack.enter_context((output/filename).open('w'))
                child = subprocess.Popen(command, cwd=root/'backend', env=env, stdout=log, stderr=subprocess.STDOUT)
                children.append(child); return child
            broker = spawn([broker_exe, '-c', str(output/'mosquitto.conf')], 'broker.log')
            def broker_ready():
                if broker.poll() is not None: raise RuntimeError('el broker propio no arrancó')
                try:
                    with socket.create_connection((host, port), timeout=.2): return True
                except OSError: return False
            trial_wait(broker_ready, 10)
            control = ControlStore.initialize(output/'control/control.sqlite', time.time())
            backend = spawn([sys.executable, '-m', 'rutautp_backend'], 'backend.log')
            trial_wait(lambda: (read_heartbeat(str(output/'health.json')) or {}).get('connected') is True)
            probe = Probe(port, accounts['reader'], host); trial_wait(lambda: probe.snapshot()['connected'])
            report['aclChecks'] = verify_local_acl(host, port, accounts, str(uuid.uuid4()))
            report['localACLVerified'] = True
            if observer is not None: observer.started(host, port, accounts['reader'], output)
            report['diskBeforeRunBytes'] = trial_disk(output)
            if control_only:
                # Diagnóstico deliberado fuera de horario: no enable, productor,
                # actores ni posiciones. La cuenta iOS es solo lectora.
                report['mode'] = 'disabled_control_no_actors'
                observer.capture_started(require_positions=False)
                capture_started = time.monotonic()
                report['resources'] = capture({'backend': backend.pid, 'broker': broker.pid},
                    output/'resources.jsonl', seconds)
                report['captureElapsedSeconds'] = time.monotonic()-capture_started
                report['captureEndedEarly'] = report['captureElapsedSeconds'] < seconds
                observer.prepare_disable()
                if check_reconnect:
                    def disconnect():
                        broker.terminate(); broker.wait(timeout=7)
                    def reconnect():
                        nonlocal broker
                        broker=spawn([broker_exe, '-c', str(output/'mosquitto.conf')], 'broker-reconnected.log')
                        wait_until(broker_ready, 10)
                    report['reconnection']=observer.check_reconnection(disconnect,reconnect)
                report['device'] = observer.finished(time.monotonic(), require_positions=False)
                report['iPhoneMeasured'] = report['device']['cpu']['complete']
                report['statusAfterDisable'] = status(control, time.time())
                report['probe'] = probe.snapshot()
                with history_reader(output/'history.sqlite') as db:
                    report['controlOnlyStorageCounts'] = {table: db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
                        for table in ('simulation_runs', 'observations', 'vehicle_positions')}
                report['functionalComplete'] = (report['resources']['complete']
                    and not control.read()['enabled'] and report['probe']['receivedPositions'] == 0
                    and report['probe']['invalidPositions'] == 0 and report['device']['maxFleet'] == 0
                    and all(value == 0 for value in report['controlOnlyStorageCounts'].values()))
                report['complete'] = report['functionalComplete'] and report['iPhoneMeasured']
            else:
                if check_active_faults:
                    started = time.monotonic()
                    hard_deadline = started+300
                    observer.begin_active_run(started)
                    report['mode'] = 'active_fleet_faults'
                    report['globalDeadlineSeconds'] = 300
                control.enable(profile.pinned(), time.time())
                def applied():
                    state = status(control, time.time())
                    return (state['runOwner'] is not None and state['backend']['fresh']
                        and state['mqtt']['lastAckedRevision'] == state['controlRevision'])
                trial_wait(applied)
                state = status(control, time.time()); report['runId'] = state['runId']
                report['controlRevision'] = state['controlRevision']
                private_json(credentials_file, {'schemaVersion': 1, 'host': host, 'port': port, 'tls': False,
                    'caFile': None, 'accounts': {p: {'username': p, 'password': accounts[p]} for p in profile.principals}})
                actor = spawn([sys.executable, '-m', 'simulation', '--control-db', str(control.path),
                    '--history-db', str(output/'history.sqlite'), '--credentials-file', str(credentials_file),
                    '--profile', name, '--gtfs-dir', str(gtfs_dir), '--reference-jsonl', str(output/'reference.jsonl'), 'run'], 'producer.log')
                trial_wait(lambda: status(control, time.time())['counts']['mqttConnections'] == len(profile.principals), 45)
                print(json.dumps({'phase': 'capture', 'profile': name, 'seconds': seconds}), flush=True)
                if observer is not None: observer.capture_started()
                if check_active_faults and observer.remaining() < seconds:
                    from .device_faults import ActiveFaultError
                    raise ActiveFaultError('insufficient_time_for_baseline')
                capture_started = time.monotonic()
                report['resources'] = capture({'backend': backend.pid, 'producer': actor.pid,
                    'broker': broker.pid}, output/'resources.jsonl', seconds)
                report['captureElapsedSeconds'] = time.monotonic()-capture_started
                report['captureEndedEarly'] = report['captureElapsedSeconds'] < seconds
                if check_active_faults:
                    observer.prepare_disable()  # CPU termina ANTES de cualquier fallo.
                    def active_disconnect():
                        broker.terminate()
                        broker.wait(timeout=min(7,observer.remaining()))
                    def active_reconnect():
                        nonlocal broker
                        broker = spawn([broker_exe,'-c',str(output/'mosquitto.conf')], 'broker-reconnected.log')
                        trial_wait(broker_ready,10)
                    def active_status():
                        current = status(control,time.time())
                        current['producerProcessExited'] = actor.poll() is not None
                        return current
                    report['activeFaults'] = observer.check_active_faults(active_disconnect,active_reconnect,
                        active_status)
                report['statusBeforeDisable'] = status(control, time.time())
                report['heartbeatBeforeDisable'] = read_heartbeat(str(output/'health.json'))
                report['diskBeforeDisableBytes'] = trial_disk(output)
                if observer is not None and not check_active_faults: observer.prepare_disable()
                requested = time.monotonic()
                disabled = control.disable(time.time(), 's10_local_trial_finished')
                report.update(disable_measurements(report['statusBeforeDisable'], disabled['revision']))
                report['disableRequestedWall'] = time.time()
                if observer is not None:
                    report['device'] = (observer.finished(requested,require_positions=False)
                        if check_active_faults else observer.finished(requested))
                    report['iPhoneMeasured'] = report['device']['cpu']['complete']
                    report.update(disable_measurements(report['statusBeforeDisable'], disabled['revision'], report['device']))
                    report['device']['manualDisableTimingUsable'] = report['iosCleanupTimingUsable']
                delivery_seconds = None
                def off():
                    nonlocal delivery_seconds
                    delivery_seconds = probe_disable_delivery_seconds(probe.snapshot(), disabled['revision'], requested)
                    return delivery_seconds is not None
                trial_wait(off, 15)
                report['probeDisableDeliverySeconds'] = delivery_seconds
                trial_wait(lambda: (actor.poll() is not None if check_active_faults else
                    status(control, time.time())['producer'].get('status') == 'stopped'), 15)
                trial_wait(lambda: status(control, time.time())['backend']['appliedRevision'] == control.read()['revision'], 15)
                report['probe'] = probe.snapshot()
                report['history'] = run_report(output/'history.sqlite', report['runId'], time.time())
                with (output/'comparison.csv').open('x') as exported:
                    export_comparison(output/'history.sqlite', report['runId'], exported, format='csv')
                report['statusAfterDisable'] = status(control, time.time())
                report['functionalComplete'] = (report['resources']['complete'] and not report['captureEndedEarly']
                    and (report['controlWasEnabledBeforeDisable'] if not check_active_faults else (
                        report['activeFaults']['complete'] and report['iPhoneMeasured']
                        and not report['statusAfterDisable']['requestedEnabled']
                        and actor.poll() is not None))
                    and report['probe']['receivedPositions'] > 0
                    and report['probe']['invalidPositions'] == 0 and report['history']['historyComplete']
                    and report['history']['stored']['observations']['rows'] > 0)
                report['complete'] = report['functionalComplete'] and (observer is None or report['iPhoneMeasured'])
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, KeyboardInterrupt) as error:
            report['failure'] = type(error).__name__
            if check_active_faults:
                from .device_faults import ActiveFaultError
                if isinstance(error,ActiveFaultError): report['failureReason'] = error.reason_code
                if observer is not None: report['activeFaults'] = observer.active_faults
        finally:
            if check_active_faults and observer is not None:
                from .device_faults import ActiveFaultError
                try:
                    observer.resume_for_cleanup()
                    report['suspendedProcessResumedOrNeverSuspended'] = not observer.suspended
                except ActiveFaultError as error:
                    report['suspendedProcessResumedOrNeverSuspended'] = False
                    report['resumeCleanupFailureReason'] = error.reason_code
                    report['complete'] = False
            if control is not None:
                try:
                    if control.read()['enabled']: control.disable(time.time(), 's10_local_trial_cleanup')
                except ControlUnavailable: report['cleanupControlConfirmed'] = False
            if probe is not None:
                try: probe.close()
                except (OSError, ValueError, RuntimeError): report['probeCloseConfirmed'] = False
            # Solo objetos Popen propios. No buscar ni terminar procesos existentes.
            for child in reversed(children):
                if child.poll() is None:
                    child.terminate()
                    if hard_deadline is None:
                        try: child.wait(timeout=7)
                        except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=3)
                        continue
                    remaining = (hard_deadline-time.monotonic()) if hard_deadline is not None else 7
                    try: child.wait(timeout=max(.01,min(7,remaining)))
                    except subprocess.TimeoutExpired:
                        child.kill()
                        remaining = (hard_deadline-time.monotonic()) if hard_deadline is not None else 3
                        try: child.wait(timeout=max(.01,min(3,remaining)))
                        except subprocess.TimeoutExpired: pass
            report['ownedProcessesStopped'] = all(p.poll() is not None for p in children)
            password_file.unlink(missing_ok=True); credentials_file.unlink(missing_ok=True)
            report['diskAfterStopBytes'] = trial_disk(output)
            if check_active_faults and observer is not None:
                observer.close()
                report['suspendedProcessResumedOrNeverSuspended'] = not observer.suspended
                if hard_deadline is not None:
                    report['activeRunElapsedSeconds'] = time.monotonic()-(hard_deadline-300)
                    report['globalDeadlineExceeded'] = report['activeRunElapsedSeconds'] > 300
                    if report['globalDeadlineExceeded'] or observer.suspended:
                        report['complete'] = report['functionalComplete'] = False
                        report.setdefault('failureReason','global_deadline_exceeded' if report['globalDeadlineExceeded']
                            else 'suspended_process_resume_not_confirmed')
        private_json(output/'result.json', report)
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Ensayo local deliberado, sin EMQX ni datos activos')
    parser.add_argument('--profile', required=True, choices=tuple(PROFILE_SPECS))
    parser.add_argument('--output', required=True, type=Path, help='directorio nuevo fuera de Git; padre existente')
    parser.add_argument('--seconds', required=True, type=int)
    parser.add_argument('--listen-host', default=HOST, type=trial_host,
                        help='interfaz IPv4 privada explícita; loopback por defecto')
    parser.add_argument('--scenario-occupancy', action='store_true', help='guion de ocupación v1, salida sintética v3')
    parser.add_argument('--control-only', action='store_true', help='diagnóstico iPhone con control OFF; cero actores, permitido fuera de horario')
    parser.add_argument('--check-reconnect', action='store_true', help='reiniciar solo el broker propio después de la captura de CPU; requiere control-only')
    parser.add_argument('--check-active-faults', action='store_true', help='ensayo iPhone opt-in: baseline35 s, background/suspend y corte del broker propio; máximo300 s')
    parser.add_argument('--instruments', action='store_true', help='una traza adicional opcional; su guardado no valida CPU')
    parser.add_argument('--device', help='UDID del iPhone; requiere Release instalado y una IP LAN')
    parser.add_argument('--bundle-id', default='apolito.RutaUTP.dev-joaquindiaz.RutaUTP')
    parser.add_argument('command', choices=['run'])
    args = parser.parse_args(argv)
    previous = {}; observer = None
    def interrupted(*_): raise KeyboardInterrupt()
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, interrupted)
        if args.check_active_faults and args.instruments:
            raise ValueError('active-faults no combina Instruments')
        if args.device:
            if ipaddress.ip_address(args.listen_host).is_loopback:
                raise ValueError('el iPhone requiere la interfaz LAN privada de la Mac')
            if args.check_active_faults:
                from .device_faults import ActiveFaultObserver
                observer = ActiveFaultObserver(args.device,args.bundle_id)
            else:
                from .device_trial import DeviceObserver
                observer = DeviceObserver(args.device, args.bundle_id, instruments=args.instruments)
        result = run_trial(args.output, args.profile, args.seconds, host=args.listen_host, observer=observer,
            scenario_occupancy=args.scenario_occupancy, control_only=args.control_only, check_reconnect=args.check_reconnect,
            check_active_faults=args.check_active_faults)
        print(json.dumps({'phase': 'finished', 'complete': result['complete'],
            'profile': args.profile, 'failure': result['failure']}), flush=True)
        return 130 if result['failure'] == 'KeyboardInterrupt' else (0 if result['complete'] else 2)
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, RuntimeError) as error:
        print(json.dumps({'complete': False, 'failure': type(error).__name__}), flush=True)
        return 2
    finally:
        if observer is not None: observer.close()
        for signum, handler in previous.items(): signal.signal(signum, handler)


if __name__ == '__main__':
    raise SystemExit(main())
