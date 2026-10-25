"""Observador iPhone explícito de S10. Importar no abre/instala ninguna app.

La instalación Release se realiza por separado. La cuenta temporal solo pasa
por el entorno del hijo; no se escribe en argumentos, Keychain o preferencias.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

from .device_resources import summarize_device_cpu


def console_events(path: Path) -> list[dict]:
    events = []
    if not path.exists(): return events
    for line in path.read_text(errors='replace').splitlines():
        if '[S10] ' not in line: continue
        try:
            value = json.loads(line.split('[S10] ',1)[1])
            if isinstance(value,dict) and isinstance(value.get('counts'),dict): events.append(value)
        except ValueError: pass  # Una escritura en curso puede dejar la última línea incompleta.
    return events


def app_process_id(processes: list[dict]) -> int:
    matching = [p['processIdentifier'] for p in processes
        if p.get('executable','').endswith('/RutaUTP.app/RutaUTP')
        and type(p.get('processIdentifier')) is int and p['processIdentifier']>0]
    if len(matching)!=1:raise RuntimeError('no hay un único proceso RutaUTP en el iPhone')
    return matching[0]


def remote_process_id(device: str, output: Path) -> int:
    descriptor,path=tempfile.mkstemp(prefix='s10-device-processes-',suffix='.json')
    os.close(descriptor)
    try:
        result=subprocess.run(['xcrun','devicectl','device','info','processes','--device',device,
            '--timeout','20','--json-output',path],capture_output=True,timeout=30)
        if result.returncode:raise RuntimeError('no se pudo consultar el PID del iPhone')
        data=json.loads(Path(path).read_text())
        pid=app_process_id(data['result']['runningProcesses'])
        (output/'device-process.json').write_text(json.dumps({'processIdentifier':pid,'name':'RutaUTP'})+'\n')
        return pid
    finally:Path(path).unlink(missing_ok=True)


class DeviceObserver:
    def __init__(self, device: str, bundle_id: str, *, instruments: bool = False):
        self.device=device; self.bundle_id=bundle_id
        self.app=None; self.profiler=None; self.streams=[]; self.output=None
        self.before_disable=0
        self.instruments = instruments
        self.pid = None; self.cpu_start = None; self.cpu_end = None

    def _spawn(self, args, filename, env=None):
        path=self.output/filename
        stream=os.fdopen(os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w')
        self.streams.append(stream)
        return subprocess.Popen(args,env=env,stdout=stream,stderr=subprocess.STDOUT)

    def _wait(self, predicate, seconds=60):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            if self.app is not None and self.app.poll() is not None:
                raise RuntimeError('la app/console del iPhone terminó antes de confirmar recepción')
            result=predicate()
            if result: return result
            time.sleep(.1)
        raise RuntimeError('el iPhone no confirmó la condición de S10 dentro del plazo')

    def started(self, host, port, password, output):
        self.output=output
        env={k:v for k,v in os.environ.items() if not k.startswith('DEVICECTL_CHILD_')}
        values={'RUTAUTP_S10_TRIAL':'1','RUTAUTP_S10_RESOURCE_SAMPLING':'1','MQTT_HOST':host,'MQTT_PORT':str(port),
                'MQTT_TLS':'0','MQTT_USERNAME':'reader','MQTT_PASSWORD':password}
        env.update({'DEVICECTL_CHILD_'+k:v for k,v in values.items()})
        self.app=self._spawn(['xcrun','devicectl','device','process','launch','--device',self.device,
            '--terminate-existing','--console',self.bundle_id], 'device-console.log',env)
        print(json.dumps({'phase':'open_map_on_iphone','waitSeconds':600}),flush=True)
        self._wait(lambda:any(e['event']=='control' for e in console_events(output/'device-console.log')),600)

    def capture_started(self, *, require_positions=True):
        self._wait(lambda:any(e['event']=='map' and (not require_positions or e['counts'].get('received',0)>0)
            for e in console_events(self.output/'device-console.log')),30)
        maps=[e for e in console_events(self.output/'device-console.log') if e['event']=='map']
        self.cpu_start = maps[-1]['uptime']
        self.pid=remote_process_id(self.device,self.output)
        # Una única sesión opcional. La CPU no depende de que xctrace guarde
        # una traza, y una salida 0 nunca se interpreta como muestras válidas.
        if self.instruments:
            self.profiler=self._spawn(['xcrun','xctrace','record','--device',self.device,
                '--template','Time Profiler','--all-processes','--time-limit','30s',
                '--output',str(self.output/'iphone-time-profiler.trace')], 'instruments.log')

    def prepare_disable(self):
        events=console_events(self.output/'device-console.log')
        self.before_disable=len(events)
        samples=[e for e in events if e['event']=='processResources']
        self.cpu_end = samples[-1]['uptime'] if samples else self.cpu_start

    def check_reconnection(self, disconnect, reconnect):
        """Solo para el broker propio. No manipula Wi-Fi, ajustes ni otros procesos."""
        path=self.output/'device-console.log'
        mark=len(console_events(path))
        requested=time.monotonic(); disconnect()
        self._wait(lambda:any(e['event']=='disconnection' for e in console_events(path)[mark:]),20)
        lost=time.monotonic()-requested
        recovery_mark=len(console_events(path)); requested=time.monotonic(); reconnect()
        def recovered():
            tail=console_events(path)[recovery_mark:]
            stage=0
            for event in tail:
                counts=event['counts']
                if stage==0 and event['event']=='connection' and counts.get('accepted')==1: stage=1
                elif stage==1 and event['event']=='subscription' and counts.get('control')==1: stage=2
                elif stage==2 and event['event']=='control' and counts.get('enabled')==0: return True
            return False
        self._wait(recovered,45)
        return {'complete':True,'disconnectObservedUpperBoundSeconds':lost,
            'reconnectObservedUpperBoundSeconds':time.monotonic()-requested,
            'scope':'own_local_broker_restart; control_disabled; no_radio_toggle_or_active_fleet',
            'cpuIntervalEndedBeforeFault':True}

    def finished(self, requested_uptime, *, require_positions=True):
        def retired():
            tail=console_events(self.output/'device-console.log')[self.before_disable:]
            return any(e['event']=='control' and e['counts'].get('enabled')==0 for e in tail) and any(
                e['event']=='map' and e['counts'].get('received')==0 and e['counts'].get('fleet')==0 for e in tail)
        if require_positions:
            self._wait(retired,20)
        else:
            events=console_events(self.output/'device-console.log')
            controls=[e for e in events if e['event']=='control']
            maps=[e for e in events if e['event']=='map']
            if (not controls or controls[-1]['counts'].get('enabled') != 0 or not maps
                    or maps[-1]['counts'].get('fleet') != 0 or maps[-1]['counts'].get('received') != 0):
                raise RuntimeError('el diagnóstico requiere control deshabilitado y mapa vacío')
        upper_bound=time.monotonic()-requested_uptime
        events=console_events(self.output/'device-console.log')
        maps=[e for e in events if e['event']=='map']
        code=self.profiler.poll() if self.profiler is not None else None
        try:
            cpu=summarize_device_cpu(events, self.pid, after=self.cpu_start, before=self.cpu_end)
        except ValueError as error:
            cpu={'complete':False,'cpuPctOneCore':None,'failure':str(error)}
        (self.output/'iphone-cpu.json').write_text(json.dumps(cpu,indent=2)+'\n')
        return {'connected':True, 'maxReceived':max(e['counts'].get('received',0) for e in maps),
            'maxFleet':max(e['counts'].get('fleet',0) for e in maps),
            'retiredConfirmed':require_positions,'cleanupUpperBoundSeconds':upper_bound if require_positions else None,
            'cleanupMeaning':'host_monotonic_disable_to_observed_console_map_zero; includes_poll_and_console_delay',
            'traceCaptured':code==0,'traceSavedIsNotCPUValidation':True,'traceExitCode':code,
            'cpu':cpu,'cpuPctOneCore':cpu['cpuPctOneCore'],
            'cpuPendingTraceExport':self.instruments,'renderedMarkerCountMeasured':False}

    def close(self):
        for child in [self.profiler,self.app]:
            if child is not None and child.poll() is None:
                child.send_signal(signal.SIGINT if child is self.profiler else signal.SIGTERM)
                try: child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait(timeout=3)
        for stream in self.streams: stream.close()
