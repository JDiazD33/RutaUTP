"""Fallos físicos opt-in; importar no consulta ni modifica un dispositivo."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from .device_trial import DeviceObserver, app_process_id, console_events
from .device_resources import summarize_device_cpu


class ActiveFaultError(RuntimeError):
    def __init__(self, code: str):
        self.reason_code = code
        super().__init__(code)


def empty_map(event: dict) -> bool:
    counts = event.get('counts', {})
    return event.get('event') == 'map' and all(counts.get(k) == 0 for k in (
        'received', 'fleet', 'occupancyEmpty', 'occupancySpace', 'occupancyFull'))


def full_map(event: dict) -> bool:
    counts = event.get('counts', {})
    return (event.get('event') == 'map' and counts.get('received') == counts.get('fleet') == 10
        and all(type(counts.get(k)) is int and counts[k] >= 0 for k in (
            'occupancyEmpty', 'occupancySpace', 'occupancyFull'))
        and sum(counts[k] for k in ('occupancyEmpty', 'occupancySpace', 'occupancyFull')) == 10)


def background_cleared(events: list[dict], pid: int) -> bool:
    background = False
    for event in events:
        counts = event['counts']
        if (event['event'] == 'providerLifecycle' and counts.get('processID') == pid
                and counts.get('stage') == 10 and counts.get('applicationState') == 2):
            background = True
        elif background and empty_map(event):
            return True
    return False


def foreground_recovered(events: list[dict], pid: int, revision: int) -> bool:
    foreground = active = control = fleet = False
    for event in events:
        counts = event['counts']
        if event['event'] == 'providerLifecycle' and counts.get('processID') == pid:
            foreground |= counts.get('stage') == 11
            active |= counts.get('stage') == 9 and counts.get('applicationState') == 0
        elif (foreground and event['event'] == 'control' and counts.get('enabled') == 1
                and counts.get('revision') == revision):
            control = True
        elif event['event'] == 'map' and counts.get('fleet', 0) > 0:
            if not control:
                raise ActiveFaultError('fleet_before_foreground_control')
            fleet = full_map(event)
    return foreground and active and control and fleet


def network_recovered_disabled(events: list[dict], minimum_revision: int) -> bool:
    stage = 0
    for event in events:
        counts = event['counts']
        if event['event'] == 'map' and counts.get('fleet', 0) > 0:
            raise ActiveFaultError('fleet_resurrected_after_broker_cut')
        if stage == 0 and event['event'] == 'connection' and counts.get('accepted') == 1:
            stage = 1
        elif stage == 1 and event['event'] == 'subscription' and counts.get('control') == 1:
            stage = 2
        elif (stage == 2 and event['event'] == 'control' and counts.get('enabled') == 0
                and counts.get('revision', 0) >= minimum_revision):
            return True
    return False


class ActiveFaultObserver(DeviceObserver):
    """Un PID propio, un broker propio y un plazo total de 300 s desde enable.

    CoreDevice fuerza la suspensión del proceso: esto no demuestra que iOS
    hubiera elegido suspenderlo automáticamente por su política de background.
    """
    def __init__(self, device, bundle_id, *, runner=subprocess.run,
                 monotonic=time.monotonic, sleep=time.sleep, notifier=print):
        super().__init__(device, bundle_id)
        self.runner, self.monotonic, self.sleep, self.notifier = runner, monotonic, sleep, notifier
        self.hard_deadline = self.phase_deadline = None
        self.activation_environment = None
        self.suspended = False
        self.resume_confirmed = False
        self.active_faults = None

    def begin_active_run(self, started: float):
        self.hard_deadline = started + 300
        self.phase_deadline = started + 280  # Reservar limpieza y resume final.
        self._log('active_run_started', globalDeadlineHostUptime=self.hard_deadline)

    def remaining(self, *, cleanup=False):
        deadline = self.hard_deadline if cleanup else self.phase_deadline
        if deadline is None:
            return 600.0
        remaining = deadline-self.monotonic()
        if remaining <= 0:
            raise ActiveFaultError('global_deadline_exhausted')
        return remaining

    def _log(self, event, **fields):
        row = {'event': event, 'hostUptime': self.monotonic(), 'hostWall': time.time(), **fields}
        if self.output is not None:
            with (self.output/'device-faults.jsonl').open('a') as stream:
                stream.write(json.dumps(row, allow_nan=False)+'\n')

    def _events(self):
        return console_events(self.output/'device-console.log')

    def _wait(self, predicate, seconds=60):
        if self.phase_deadline is None:
            return super()._wait(predicate, seconds)
        end = self.monotonic()+min(seconds, self.remaining())
        while self.monotonic() < end:
            if self.app is not None and self.app.poll() is not None:
                raise ActiveFaultError('device_console_ended')
            value = predicate()
            if value:
                return value
            self.sleep(max(0,min(.1, end-self.monotonic())))
        raise ActiveFaultError('phase_condition_timeout')

    def _hold(self, seconds):
        if self.remaining() < seconds:
            raise ActiveFaultError('insufficient_time_for_phase')
        end = self.monotonic()+seconds
        while self.monotonic() < end:
            self.sleep(min(.1, end-self.monotonic()))

    def started(self, host, port, password, output):
        # Conservar solo en memoria. Nunca pasar secretos en argv o JSON.
        self.activation_environment = {k:v for k,v in os.environ.items()
            if not k.startswith('DEVICECTL_CHILD_')}
        values = {'RUTAUTP_S10_TRIAL':'1', 'RUTAUTP_S10_RESOURCE_SAMPLING':'1',
            'MQTT_HOST':host, 'MQTT_PORT':str(port), 'MQTT_TLS':'0',
            'MQTT_USERNAME':'reader', 'MQTT_PASSWORD':password}
        self.activation_environment.update({'DEVICECTL_CHILD_'+k:v for k,v in values.items()})
        super().started(host, port, password, output)

    def _device_command(self, operation, args, *, cleanup=False, activation=False):
        timeout = min(10.0, self.remaining(cleanup=cleanup))
        descriptor, raw_path = tempfile.mkstemp(prefix='s10-fault-', suffix='.json')
        os.close(descriptor)
        # launch admite argumentos de la app después del bundle posicional.
        # Colocar las opciones de CoreDevice antes evita pasárselas a RutaUTP.
        command = ['xcrun','devicectl','device',*args[:2],'--device',self.device,
            '--timeout',f'{timeout:g}','--json-output',raw_path,*args[2:]]
        try:
            try:
                result = self.runner(command, capture_output=True, timeout=timeout,
                    env=self.activation_environment if activation else None)
                raw = json.loads(Path(raw_path).read_text())
            except (OSError, ValueError, subprocess.SubprocessError):
                self._log('os_command', operation=operation, success=False, pid=self.pid)
                raise ActiveFaultError('device_'+operation+'_failed') from None
            success = result.returncode == 0 and raw.get('info',{}).get('outcome') == 'success'
            # El JSON original puede contener entorno/argumentos: no conservarlo.
            safe_result = {k:v for k,v in raw.get('result',{}).items()
                if k in ('processIdentifier','processState','state','isSuspended','suspended')
                and type(v) in (str,int,float,bool,type(None))}
            self._log('os_command', operation=operation, success=success,
                exitCode=result.returncode, pid=self.pid, result=safe_result)
            if not success:
                raise ActiveFaultError('device_'+operation+'_failed')
            return raw.get('result',{})
        finally:
            Path(raw_path).unlink(missing_ok=True)

    def _own_pid(self, stage, *, cleanup=False):
        # Buscar solo RutaUTP, pero todas sus instancias: filtrar por el PID
        # previo ocultaría una segunda instancia inesperada de la misma app.
        args = ['info','processes','--search','RutaUTP.app']
        data = self._device_command('pid_check',args,cleanup=cleanup)
        try:
            pid = app_process_id(data['runningProcesses'])
        except (KeyError, TypeError, RuntimeError):
            raise ActiveFaultError('own_pid_not_confirmed_'+stage) from None
        if self.pid is not None and pid != self.pid:
            raise ActiveFaultError('own_pid_changed_'+stage)
        self._log('own_pid_confirmed', stage=stage, pid=pid)
        return pid

    def capture_started(self, *, require_positions=True):
        self._wait(lambda:any(full_map(e) for e in self._events()),30)
        maps = [e for e in self._events() if full_map(e)]
        self.cpu_start = maps[-1]['uptime']
        self.pid = self._own_pid('baseline')
        (self.output/'device-process.json').write_text(json.dumps({
            'processIdentifier':self.pid,'name':'RutaUTP'})+'\n')

    def _resume(self):
        if not self.suspended:
            return
        self._own_pid('before_resume',cleanup=True)
        self._device_command('resume',['process','resume','--pid',str(self.pid)],cleanup=True)
        self.suspended = False
        self.resume_confirmed = True
        self._log('suspension_resume_confirmed',pid=self.pid)

    def resume_for_cleanup(self):
        self._resume()

    def _background_suspension(self, revision):
        mark = len(self._events())
        wait = min(90,self.remaining())
        self._log('background_iphone_request',waitSeconds=wait,pid=self.pid)
        self.notifier(json.dumps({'phase':'background_iphone_request','waitSeconds':wait}),flush=True)
        self._wait(lambda:background_cleared(self._events()[mark:],self.pid),wait)
        self._own_pid('before_suspend')
        # Si CoreDevice pierde la respuesta después de suspender, aun así
        # intentar resume del PID verificado; no dejar una pausa incierta.
        self.suspended = True
        resumed_mark = None
        try:
            self._device_command('suspend',['process','suspend','--pid',str(self.pid)])
            self._hold(.5)  # Permitir que el puente entregue stdout previo al suspend.
            silence_mark = len(self._events())
            hold_started = self.monotonic()
            self._hold(25)
            if self._events()[silence_mark:]:
                raise ActiveFaultError('execution_observed_during_os_suspend')
            self._own_pid('while_suspended')
            held = self.monotonic()-hold_started
            resumed_mark = len(self._events())
        finally:
            self._resume()
        self._own_pid('before_activate')
        activated = self._device_command('activate',['process','launch','--activate',self.bundle_id],activation=True)
        if 'processIdentifier' in activated and (type(activated['processIdentifier']) is not int
                or activated['processIdentifier'] != self.pid):
            raise ActiveFaultError('own_pid_changed_activation_response')
        self._own_pid('after_activate')
        self._wait(lambda:foreground_recovered(self._events()[resumed_mark:],self.pid,revision),45)
        result = {'complete':True,'pidUnchanged':True,'backgroundAndEmptyMapObserved':True,
            'osSuspendCommandSucceeded':True,'osResumeCommandSucceeded':self.resume_confirmed,
            'suspendedHoldSeconds':held,'executionEventsDuringSuspendedHold':0,
            'foregroundAndFreshControlBeforeFleetConfirmed':True,
            'scope':'physical_iOS_process_forced_suspension_by_CoreDevice; not proof of automatic iOS background policy'}
        self._log('background_suspension_complete',**result)
        return result

    def _network_cut(self, disconnect, reconnect, status):
        events = self._events()
        if not events or not full_map(next(e for e in reversed(events) if e['event']=='map')):
            raise ActiveFaultError('fleet_not_ten_before_network_cut')
        mark = len(events)
        requested = self.monotonic()
        self._log('broker_cut_requested')
        disconnect()
        self._wait(lambda:any(e['event']=='disconnection' for e in self._events()[mark:]),20)
        disconnected = self.monotonic()-requested
        self._wait(lambda:any(empty_map(e) for e in self._events()[mark:]),max(.01,20-disconnected))
        removed = self.monotonic()-requested
        if removed > 20:
            raise ActiveFaultError('network_removal_exceeded_twenty_seconds')
        remaining_hold = 25-(self.monotonic()-requested)
        if remaining_hold > 0:
            self._hold(remaining_hold)
        def stopped():
            value = status()
            return (value if value.get('requestedEnabled') is False
                and value.get('producer',{}).get('status')=='stopped'
                and value.get('producerProcessExited') is True else None)
        disabled = self._wait(stopped,10)
        revision = disabled['controlRevision']
        recovery_mark = len(self._events())
        recovery_started = self.monotonic()
        reconnect()
        self._wait(lambda:network_recovered_disabled(self._events()[recovery_mark:],revision),45)
        self._hold(5)  # Observar también mensajes en vuelo después del OFF.
        tail = self._events()[mark:]
        lost = False
        for event in tail:
            if empty_map(event):
                lost = True
            elif lost and event['event']=='map' and event['counts'].get('fleet',0)>0:
                raise ActiveFaultError('fleet_resurrected_after_broker_cut')
        if not empty_map(next(e for e in reversed(self._events()) if e['event']=='map')):
            raise ActiveFaultError('final_network_map_not_empty')
        current = status()
        # Un productor terminado deja de renovar su heartbeat. Su estado público
        # pasa legítimamente a unknown; conservar la prueba previa de stopped y
        # confirmar además la salida del Popen propio, sin alterar esa caducidad.
        if (current.get('requestedEnabled') is not False
                or current.get('runId') != disabled.get('runId')
                or current.get('controlRevision',0) < revision
                or current.get('producerProcessExited') is not True
                or current.get('producer',{}).get('status') not in ('stopped','unknown')):
            raise ActiveFaultError('control_or_producer_not_stopped_after_recovery')
        result = {'complete':True,'disconnectObservedUpperBoundSeconds':disconnected,
            'emptyMapObservedUpperBoundSeconds':removed,'requestedOfflineSeconds':25,
            'reconnectObservedUpperBoundSeconds':self.monotonic()-recovery_started,
            'offRevisionAfterCut':revision,'automaticDisableReason':disabled.get('reason'),
            'postReconnectObservationSeconds':5,
            'controlPersistentlyDisabled':True,'producerStopped':True,'fleetResurrected':False,
            'producerProcessExited':True,
            'producerStatusAfterRecovery':current.get('producer',{}).get('status'),
            'scope':'own_local_broker_restart_with_active_fleet; no global Wi-Fi change'}
        self._log('active_network_cut_complete',**result)
        return result

    def check_active_faults(self, disconnect, reconnect, status):
        if self.cpu_end is None:
            raise ActiveFaultError('baseline_cpu_not_frozen')
        baseline_end = self.cpu_end
        try:
            baseline_cpu = summarize_device_cpu(self._events(),self.pid,
                after=self.cpu_start,before=baseline_end)
        except ValueError:
            raise ActiveFaultError('baseline_cpu_not_valid') from None
        state = status()
        if state.get('requestedEnabled') is not True:
            raise ActiveFaultError('control_not_enabled_before_faults')
        result = {'complete':False,'cpuIntervalEndedBeforeFault':True,
            'globalDeadlineSeconds':300,'baselineEndDeviceUptime':baseline_end,
            'baselineCPU':baseline_cpu}
        self.active_faults = result
        (self.output/'iphone-cpu-baseline.json').write_text(json.dumps(baseline_cpu,indent=2)+'\n')
        result['suspension'] = self._background_suspension(state['controlRevision'])
        result['network'] = self._network_cut(disconnect,reconnect,status)
        if self.cpu_end != baseline_end:
            raise ActiveFaultError('baseline_cpu_interval_changed')
        result['complete'] = True
        return result

    def close(self):
        try:
            try:
                self._resume()
            except ActiveFaultError as error:
                self._log('resume_cleanup_failed',reason=error.reason_code,pid=self.pid)
        finally:
            self.activation_environment = None
            # Este observador no arranca Instruments. Nunca esperar sin plazo.
            for child in [self.profiler,self.app]:
                if child is not None and child.poll() is None:
                    child.terminate()
                    remaining = max(.01,(self.hard_deadline or (self.monotonic()+15))-self.monotonic())
                    try:
                        child.wait(timeout=min(15,remaining))
                    except subprocess.TimeoutExpired:
                        child.kill()
                        try: child.wait(timeout=max(.01,min(1,remaining)))
                        except subprocess.TimeoutExpired: pass
            for stream in self.streams:
                stream.close()
