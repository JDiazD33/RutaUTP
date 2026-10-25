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
    def __init__(self, device: str, bundle_id: str):
        self.device=device; self.bundle_id=bundle_id
        self.app=None; self.profiler=None; self.streams=[]; self.output=None
        self.before_disable=0

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
        values={'RUTAUTP_S10_TRIAL':'1','MQTT_HOST':host,'MQTT_PORT':str(port),
                'MQTT_TLS':'0','MQTT_USERNAME':'reader','MQTT_PASSWORD':password}
        env.update({'DEVICECTL_CHILD_'+k:v for k,v in values.items()})
        self.app=self._spawn(['xcrun','devicectl','device','process','launch','--device',self.device,
            '--terminate-existing','--console',self.bundle_id], 'device-console.log',env)
        print(json.dumps({'phase':'open_map_on_iphone','waitSeconds':600}),flush=True)
        self._wait(lambda:any(e['event']=='control' for e in console_events(output/'device-console.log')),600)

    def capture_started(self):
        self._wait(lambda:any(e['event']=='map' and e['counts'].get('received',0)>0
            for e in console_events(self.output/'device-console.log')),30)
        pid=remote_process_id(self.device,self.output)
        self.profiler=self._spawn(['xcrun','xctrace','record','--device',self.device,
            '--template','Time Profiler','--attach',str(pid),'--time-limit','30s',
            '--output',str(self.output/'iphone-time-profiler.trace')], 'instruments.log')

    def prepare_disable(self):
        self.before_disable=len(console_events(self.output/'device-console.log'))

    def finished(self, requested_uptime):
        def retired():
            tail=console_events(self.output/'device-console.log')[self.before_disable:]
            return any(e['event']=='control' and e['counts'].get('enabled')==0 for e in tail) and any(
                e['event']=='map' and e['counts'].get('received')==0 and e['counts'].get('fleet')==0 for e in tail)
        self._wait(retired,20)
        upper_bound=time.monotonic()-requested_uptime
        events=console_events(self.output/'device-console.log')
        maps=[e for e in events if e['event']=='map']
        code=self.profiler.poll() if self.profiler is not None else None
        return {'connected':True, 'maxReceived':max(e['counts'].get('received',0) for e in maps),
            'maxFleet':max(e['counts'].get('fleet',0) for e in maps),
            'retiredConfirmed':True,'cleanupUpperBoundSeconds':upper_bound,
            'cleanupMeaning':'host_monotonic_disable_to_observed_console_map_zero; includes_poll_and_console_delay',
            'traceCaptured':code==0,'traceExitCode':code,'cpuPctOneCore':None,
            'cpuPendingTraceExport':True,'renderedMarkerCountMeasured':False}

    def close(self):
        for child in [self.profiler,self.app]:
            if child is not None and child.poll() is None:
                child.send_signal(signal.SIGINT if child is self.profiler else signal.SIGTERM)
                try: child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait(timeout=3)
        for stream in self.streams: stream.close()
