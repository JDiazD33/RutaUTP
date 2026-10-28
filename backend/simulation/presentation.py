"""Presentación con EMQX existente, estado privado persistente y cierre acotado.

preparar/estado son offline. comprobar solo verifica cuentas/ACL; iniciar es la
única orden que habilita actores. Nunca cambia cuentas/permisos del broker.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import csv
import fcntl
import hashlib
import io
import json
import math
import os
from pathlib import Path
import secrets
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid

from rutautp_backend.health import read_heartbeat, fresh_timestamp
from rutautp_backend.simulation_admin import status
from rutautp_backend.simulation_control_store import ControlStore, ControlUnavailable
from rutautp_backend.simulation_profile import SimulationProfile, lima_zone
from .publisher import load_credentials, parse_control

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIRECTORY = Path.home()/'Library/Application Support/RutaUTP/Presentacion'
READER = 'presentation-reader'
CONTROL_TOPIC = 'rutautp/simulacion/estado'
PRESENTATION_PROFILES = ('pasajeros-30', 'pasajeros-50')


def profile_files(directory, name):
    if name not in PRESENTATION_PROFILES:raise ValueError('perfil de presentación no preparado')
    suffix = '' if name == 'pasajeros-30' else '-'+name
    return Path(directory)/('actors-credentials'+suffix+'.json'), Path(directory)/('acl-verified'+suffix+'.json')


def private_json(path, body):
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix='.'+path.name, dir=path.parent)
    try:
        with os.fdopen(descriptor,'w') as stream:
            json.dump(body,stream,ensure_ascii=False,allow_nan=False,indent=2);stream.write('\n')
        os.replace(temporary,path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def private_read(path):
    path=Path(path)
    if path.is_symlink():raise ValueError('configuración enlazada no admitida')
    info=path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o077 or info.st_size>131072:
        raise ValueError('la configuración debe ser privada del usuario')
    return json.loads(path.read_text())


def environment_file(path):
    values={}
    for line in Path(path).read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):continue
        key,separator,value=line.partition('=');key=key.strip()
        if not separator or not key.startswith(('MQTT_','BACKEND_','GTFS_')):
            raise ValueError('formato de entorno inválido')
        values[key]=value
    if not all(values.get(k) for k in ['MQTT_HOST','MQTT_USERNAME','MQTT_PASSWORD']):
        raise ValueError('faltan credenciales del backend')
    if values.get('MQTT_TLS','').lower() not in ('1','true','yes'):
        raise ValueError('la presentación con broker remoto exige TLS')
    return values


def prepare(directory, backend_config):
    directory=Path(directory).expanduser().absolute()
    if directory.resolve().is_relative_to(ROOT):raise ValueError('usar directorio privado fuera de Git')
    if directory.exists():raise ValueError('el directorio ya existe; se conserva sin sobrescribir')
    original=environment_file(backend_config)
    profile=SimulationProfile.load('pasajeros-30',ROOT/'gtfs')
    directory.mkdir(parents=True,mode=0o700)
    (directory/'control').mkdir(mode=0o700);(directory/'runs').mkdir(mode=0o700)
    accounts={p:{'username':p,'password':secrets.token_urlsafe(32)} for p in sorted(profile.principals)}
    reader={'username':READER,'password':secrets.token_urlsafe(32)}
    endpoint={'schemaVersion':1,'host':original['MQTT_HOST'],'port':int(original.get('MQTT_PORT','8883')),
        'tls':True,'caFile':original.get('MQTT_CA_CERT') or None}
    private_json(directory/'actors-credentials.json',{**endpoint,'accounts':accounts})
    private_json(directory/'reader.json',{**endpoint,**reader})
    environment={k:v for k,v in original.items() if k.startswith('MQTT_')}
    environment.update({'GTFS_DIR':str(ROOT/'gtfs'),'BACKEND_DB_PATH':str(directory/'history.sqlite'),
        'BACKEND_DB_RETENTION_DAYS':'0','BACKEND_HEALTH_FILE':str(directory/'health.json'),
        'BACKEND_SIMULATION_CONTROL_PATH':str(directory/'control/control.sqlite'),
        'BACKEND_SIMULATION_INGRESS_ENABLED':'1','BACKEND_SIMULATION_OCCUPANCY_ENABLED':'1',
        'BACKEND_VEHICLE_POSITION_SCHEMA_VERSION':'2','BACKEND_MIN_PUBLISH_PRINCIPALS':'2'})
    private_json(directory/'backend-environment.json',environment)
    health=Path(original.get('BACKEND_HEALTH_FILE','data/health.json'))
    if not health.is_absolute():health=ROOT/'backend'/health
    private_json(directory/'setup.json',{'normalBackendHealthFile':str(health),
        'brokerHost':endpoint['host'],'brokerPort':endpoint['port']})
    imports=directory/'EMQX-CUENTAS-IMPORTAR.csv'
    with os.fdopen(os.open(imports,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['username','password'])
        for account in [*accounts.values(),reader]:writer.writerow([account['username'],account['password']])
    rules=[]
    for principal in sorted(profile.principals):
        rules.append({'username':principal,'rules':[
            {'permission':'allow','action':'publish','topic':f'rutautp/simulacion/+/observaciones/{principal}/+/posicion'},
            {'permission':'allow','action':'subscribe','topic':CONTROL_TOPIC},
            {'permission':'deny','action':'all','topic':'#'}]})
    rules.append({'username':READER,'rules':[
        {'permission':'allow','action':'subscribe','topic':CONTROL_TOPIC},
        {'permission':'allow','action':'subscribe','topic':'rutautp/vehiculos/+/posicion'},
        {'permission':'deny','action':'all','topic':'#'}]})
    rules.append({'username':original['MQTT_USERNAME'],'addRulesPreservingExisting':[
        {'permission':'allow','action':'subscribe','topic':'rutautp/simulacion/+/observaciones/+/+/posicion'},
        {'permission':'allow','action':'publish','topic':CONTROL_TOPIC}]})
    private_json(directory/'EMQX-PERMISOS-REVISAR.json',rules)
    with os.fdopen(os.open(directory/'EMQX-PERMISOS-IMPORTAR.csv',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['username','topic','action','access'])
        for item in rules:
            # El import solo contiene usuarios nuevos. Las dos ampliaciones del
            # backend se añaden aparte, preservando su lista y orden existentes.
            for rule in item.get('rules',[]):
                writer.writerow([item['username'],rule['topic'],
                    {'publish':'pub','subscribe':'sub','all':'pubsub'}[rule['action']],rule['permission']])
    ControlStore.initialize(directory/'control/control.sqlite',time.time())
    return {'prepared':True,'directory':str(directory),'host':endpoint['host'],'port':endpoint['port'],
        'accountsToImport':31,'networkStarted':False,'next':'importar cuentas y permisos, después comprobar'}


def prepare_profile(directory, name):
    """Amplía con cuentas nuevas; conserva secretos, histórico y control originales."""
    directory=Path(directory)
    if name != 'pasajeros-50':raise ValueError('la ampliación preparada es pasajeros-50')
    target,_=profile_files(directory,name)
    accounts_csv=directory/'EMQX-CUENTAS-ADICIONALES-50.csv'
    permissions_csv=directory/'EMQX-PERMISOS-ADICIONALES-50.csv'
    with service_lock(directory):
        if any(p.exists() for p in (target,accounts_csv,permissions_csv)):
            raise ValueError('la ampliación ya tiene archivos; conservarlos sin sobrescribir')
        if ControlStore(directory/'control/control.sqlite').read()['enabled']:
            raise ValueError('detener la presentación antes de preparar otro perfil')
        base,_,_,_=configuration(directory)
        profile=SimulationProfile.load(name,ROOT/'gtfs')
        body=private_read(directory/'actors-credentials.json')
        additional=sorted(profile.principals-base.principals)
        if len(additional)!=20 or not base.principals<profile.principals:
            raise ValueError('ampliación de identidades inesperada')
        for principal in additional:
            body['accounts'][principal]={'username':principal,'password':secrets.token_urlsafe(32)}
        private_json(target,body)
        load_credentials(target,profile.principals)
        with os.fdopen(os.open(accounts_csv,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w',newline='') as stream:
            writer=csv.writer(stream);writer.writerow(['username','password'])
            for principal in additional:writer.writerow([principal,body['accounts'][principal]['password']])
        with os.fdopen(os.open(permissions_csv,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w',newline='') as stream:
            writer=csv.writer(stream);writer.writerow(['username','topic','action','access'])
            for principal in additional:
                writer.writerow([principal,f'rutautp/simulacion/+/observaciones/{principal}/+/posicion','pub','allow'])
                writer.writerow([principal,CONTROL_TOPIC,'sub','allow'])
                writer.writerow([principal,'#','pubsub','deny'])
    return {'prepared':True,'profile':name,'accountsToImport':len(additional),
        'permissionRowsToImport':len(additional)*3,'networkStarted':False,'actorsStarted':False,
        'existingAccountsPreserved':True,'accountsCSV':str(accounts_csv),'permissionsCSV':str(permissions_csv)}


@contextmanager
def service_lock(directory, *, nonblocking=True):
    descriptor=os.open(Path(directory)/'service.lock',os.O_CREAT|os.O_RDWR,0o600)
    try:
        fcntl.flock(descriptor,fcntl.LOCK_EX|(fcntl.LOCK_NB if nonblocking else 0))
        yield
    finally:os.close(descriptor)


def aggregate_budget(workspace, current, day):
    paths=set((Path(workspace)/'mds').glob('evidencias-*/**/control/control.sqlite'))
    paths.add(Path(current));groups={};physical=set();rows=[]
    for source in sorted(paths):
        source=source.resolve(strict=True);info=source.stat();identity=(info.st_dev,info.st_ino)
        if identity in physical:continue
        physical.add(identity)
        with tempfile.TemporaryDirectory(prefix='rutautp-budget-') as temporary:
            target=Path(temporary)/'control.sqlite'
            before={suffix:hashlib.sha256(Path(str(source)+suffix).read_bytes()).hexdigest()
                for suffix in ('','-wal','-shm') if Path(str(source)+suffix).exists()}
            for suffix in ('','-wal','-shm'):
                candidate=Path(str(source)+suffix)
                if candidate.exists():shutil.copy2(candidate,Path(str(target)+suffix))
            after={suffix:hashlib.sha256(Path(str(source)+suffix).read_bytes()).hexdigest()
                for suffix in ('','-wal','-shm') if Path(str(source)+suffix).exists()}
            if before!=after:raise ValueError('el ledger cambió durante la lectura; reintentar sin otros ensayos activos')
            with sqlite3.connect(target.as_uri()+'?mode=ro',uri=True) as db:
                database_id,raw=db.execute('SELECT database_id,snapshot FROM control WHERE id=1').fetchone()
                runtime=json.loads(db.execute('SELECT snapshot FROM runtime WHERE id=1').fetchone()[0])
        state=json.loads(raw);budget=runtime.get('publishBudget',{'days':{},'runs':{}})
        if (set(budget)!={'days','runs'} or any(not isinstance(v,dict) for v in budget.values())
                or any(type(n) is not int or n<0 for section in budget.values() for n in section.values())):
            raise ValueError('ledger de cuota inválido')
        fingerprint=json.dumps(budget,sort_keys=True)
        if database_id in groups and groups[database_id]!=fingerprint:
            raise ValueError('copias divergentes de un mismo ledger; revisar antes de iniciar')
        duplicate=database_id in groups;groups[database_id]=fingerprint
        rows.append({'path':str(source),'used':budget['days'].get(day,0),'counted':not duplicate,
            'enabled':state['enabled'],'current':source==Path(current).resolve()})
    return {'used':sum(row['used'] for row in rows if row['counted']),
        'otherControlEnabled':any(row['enabled'] and not row['current'] for row in rows),'controls':rows}


def required_calls(seconds, actor_count=30, max_seconds=900):
    if type(seconds) is not int or not 60<=seconds<=max_seconds:
        raise ValueError(f'duración entre 60 y {max_seconds} segundos')
    if type(actor_count) is not int or actor_count not in (30,50):raise ValueError('cantidad de actores no preparada')
    return actor_count*(seconds//5+1)


def received_current_off(snapshot,disabled):
    body=snapshot.get('control') or {}
    return (body.get('enabled') is False and type(body.get('controlRevision')) is int
        and body['controlRevision']>=disabled['revision'] and body.get('runId')==disabled.get('runId'))


def remote_control_conflicts(remote,local):
    if not remote:return False
    if remote['controlRevision']>local['revision']:return True
    if remote['enabled']:
        # Puede quedar ON retained tras perder Internet al guardar nuestro OFF.
        # Solo reconciliar el run propio con una revocación local más nueva.
        return not (local['enabled'] is False and remote.get('runId')==local.get('runId')
            and remote['controlRevision']<local['revision'])
    return False


def configuration(directory, profile_name='pasajeros-30'):
    directory=Path(directory);credentials,_=profile_files(directory,profile_name)
    profile=SimulationProfile.load(profile_name,ROOT/'gtfs')
    actors=load_credentials(credentials,profile.principals)
    reader=private_read(directory/'reader.json');environment=private_read(directory/'backend-environment.json')
    expected=(actors.host,actors.port,actors.tls)
    if (not actors.tls or expected!=(reader['host'],reader['port'],reader['tls'])
            or expected!=(environment['MQTT_HOST'],int(environment['MQTT_PORT']),True)
            or environment.get('MQTT_TLS','').lower() not in ('1','true','yes')
            or reader['username']!=READER or not reader['password']):
        raise ValueError('los tres roles deben usar el mismo broker TLS')
    return profile,actors,reader,environment


class Reader:
    """Sonda del servicio; no representa confirmación del iPhone."""
    def __init__(self,settings):
        import paho.mqtt.client as mqtt
        self.mqtt=mqtt;self.lock=threading.Lock();self.connected=False;self.control=None
        self.positions={};self.invalid=0
        self.client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,protocol=mqtt.MQTTv5,
            client_id='rutautp-presentation-reader-'+uuid.uuid4().hex)
        self.client.username_pw_set(settings['username'],settings['password'])
        self.client.tls_set(ca_certs=settings.get('caFile'))
        self.client.on_connect=self._connected;self.client.on_message=self._message
        self.client.on_disconnect=lambda *_:self._disconnected()
        self.client.connect_async(settings['host'],settings['port'],keepalive=15)
        self.client.loop_start()
    def _connected(self,client,userdata,flags,reason,properties):
        with self.lock:self.connected=reason==0
        if self.connected:client.subscribe([(CONTROL_TOPIC,1),('rutautp/vehiculos/+/posicion',1)])
    def _disconnected(self):
        with self.lock:self.connected=False;self.control=None;self.positions.clear()
    def _message(self,client,userdata,message):
        try:
            now=time.time()
            with self.lock:
                if message.topic==CONTROL_TOPIC:
                    self.control=parse_control(message.payload,now)
                    if not self.control['enabled']:self.positions.clear()
                else:
                    value=json.loads(message.payload)
                    if (message.retain or value.get('schemaVersion')!=3
                            or value.get('dataOrigin')!='simulated'
                            or value.get('scenarioOccupancy') not in ('empty','space','full')
                            or value.get('occupancyScriptVersion')!=1
                            or not isinstance(value.get('vehicleId'),str)):
                        self.invalid+=1;return
                    self.positions[value['vehicleId']]=value
        except (ValueError,TypeError,KeyError):
            with self.lock:self.invalid+=1
    def snapshot(self):
        now=time.time()
        with self.lock:
            control=self.control;positions=[]
            if self.connected and control and control['enabled'] and control['issuedAt']<=now<control['validUntil']:
                positions=[p for p in self.positions.values() if p.get('simulationRunId')==control['runId']
                    and p.get('controlRevision')==control['controlRevision']
                    and type(p.get('timestamp')) in (int,float) and math.isfinite(p['timestamp'])
                    and 0<=now-p['timestamp']<15]
            return {'connected':self.connected,'control':control,'currentVehicles':len(positions),
                'occupancy':{key:sum(p['scenarioOccupancy']==key for p in positions) for key in ('empty','space','full')},
                'invalidPositions':self.invalid,'meaning':'sonda Python, no recepción confirmada del iPhone'}
    def close(self):self.client.disconnect();self.client.loop_stop()


def wait_for(predicate,seconds=30,stopping=None):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        if stopping is not None and stopping.is_set():raise RuntimeError('interrumpido por el operador')
        value=predicate()
        if value:return value
        time.sleep(.1)
    raise RuntimeError('no se confirmó el prerrequisito dentro del plazo')


def check_accounts(directory, profile_name='pasajeros-30'):
    """Valida autenticación/SUBACK y denegaciones, sin enable ni posiciones GPS."""
    import paho.mqtt.client as mqtt
    directory=Path(directory);profile,actors,reader,environment=configuration(directory,profile_name)
    credentials,proof_file=profile_files(directory,profile_name)
    probe=Reader(reader)
    try:
        wait_for(lambda:probe.snapshot()['connected'],15)
        time.sleep(.5)
        if (probe.snapshot()['control'] or {}).get('enabled'):raise ValueError('ya hay un run habilitado en ese broker')
    finally:probe.close()
    checks=[]
    accounts=[(p,a.password) for p,a in actors.accounts.items()]+[(reader['username'],reader['password'])]
    for username,password in accounts:
        connected=threading.Event();subscribed=threading.Event();result={}
        client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,protocol=mqtt.MQTTv5,
            client_id='rutautp-presentation-acl-'+uuid.uuid4().hex)
        client.username_pw_set(username,password);client.tls_set(ca_certs=reader.get('caFile'))
        def on_connect(c,u,f,reason,props):result['connected']=reason==0;connected.set()
        def on_subscribe(c,u,mid,codes,props):result['subscribe']=bool(codes) and all(not code.is_failure for code in codes);subscribed.set()
        client.on_connect=on_connect;client.on_subscribe=on_subscribe
        try:
            client.connect_async(reader['host'],reader['port'],keepalive=15);client.loop_start()
            if not connected.wait(10) or not result.get('connected'):raise RuntimeError('autenticación de cuenta no confirmada')
            client.subscribe(CONTROL_TOPIC,qos=1)
            if not subscribed.wait(10) or not result.get('subscribe'):raise RuntimeError('lectura del control denegada')
            checks.append({'username':username,'connected':True,'controlSubscription':True})
            if username in (sorted(profile.principals)[0],sorted(profile.principals)[-1],reader['username']):
                forbidden_principal=next(p for p in sorted(profile.principals) if p!=username)
                for topic in ['rutautp/vehiculos/presentation-denied/posicion',CONTROL_TOPIC,
                        'rutautp/observaciones/presentation-denied/invalid/posicion',
                        'rutautp/simulacion/'+str(uuid.uuid4())+'/observaciones/'+forbidden_principal+'/invalid/posicion']:
                    ack=threading.Event();codes=[]
                    def published(c,u,mid,reason,props):codes.append(reason.value);ack.set()
                    client.on_publish=published;client.publish(topic,b'{}',qos=1,retain=False)
                    if not ack.wait(10) or codes!=[135]:raise RuntimeError('una cuenta permite publicación fuera de sus permisos')
                checks[-1]['negativePublishChecks']=4
        finally:client.disconnect();client.loop_stop()
    proof={'checkedAt':time.time(),'host':reader['host'],'port':reader['port'],'checks':checks,
        'credentialsSHA256':hashlib.sha256(credentials.read_bytes()).hexdigest(),
        'readerSHA256':hashlib.sha256((directory/'reader.json').read_bytes()).hexdigest(),
        'scope':'autenticación/control y denegaciones; el run confirma publicación backend y quorum'}
    private_json(proof_file,proof)
    return {'accountsVerified':len(checks),'networkStarted':True,'actorsStarted':False}


def service_state(directory):
    directory=Path(directory)
    if not directory.exists():return {'state':'sin_preparar'}
    record=private_read(directory/'status.json') if (directory/'status.json').exists() else {'state':'preparado'}
    try:
        with service_lock(directory):record={**record,'serviceRunning':False}
    except BlockingIOError:record={**record,'serviceRunning':True}
    record['control']=status(ControlStore(directory/'control/control.sqlite'),time.time())
    return record


def stop_service(directory):
    directory=Path(directory);state=service_state(directory)
    if not state['serviceRunning']:
        control=ControlStore(directory/'control/control.sqlite')
        if control.read()['enabled']:control.disable(time.time(),'presentation_operator_stop')
        return {'stopped':True,'wasRunning':False}
    private_json(directory/'stop-request.json',{'owner':state['owner']})
    wait_for(lambda:not service_state(directory)['serviceRunning'],20)
    return {'stopped':True,'wasRunning':True}


class ServiceStop:
    def __init__(self,directory,owner):
        self.directory=Path(directory);self.owner=owner;self.event=threading.Event()
    def set(self):self.event.set()
    def is_set(self):
        if self.event.is_set():return True
        path=self.directory/'stop-request.json'
        if path.exists():
            try:return private_read(path).get('owner')==self.owner
            except (OSError,ValueError):return False
        return False
    def wait(self,seconds):
        self.event.wait(seconds)
        return self.is_set()


def run_service(directory,seconds,profile_name='pasajeros-30'):
    directory=Path(directory);profile_files(directory,profile_name)
    profile=SimulationProfile.load(profile_name,ROOT/'gtfs')
    seconds=profile.max_run_seconds if seconds is None else seconds
    required=required_calls(seconds,len(profile.principals),profile.max_run_seconds)
    with service_lock(directory):
        owner=str(uuid.uuid4())
        private_json(directory/'status.json',{'owner':owner,'state':'comprobando','seenAt':time.time()})
        try:return _run_owned(directory,seconds,required,owner,profile_name)
        except (OSError,ValueError,RuntimeError,ControlUnavailable,sqlite3.Error,KeyError):
            private_json(directory/'status.json',{'owner':owner,'state':'fallo','seenAt':time.time(),
                'reason':'no se inició la sesión; consultar el resultado de la terminal'})
            raise


def _run_owned(directory,seconds,required,owner,profile_name='pasajeros-30'):
    profile=SimulationProfile.load(profile_name,ROOT/'gtfs');now=time.time();inside,day,end=profile.window(now)
    if not inside or now+seconds+20>=end:raise ValueError('la sesión no cabe en 07:00–22:30 Lima')
    control=ControlStore(directory/'control/control.sqlite')
    if control.read()['enabled']:raise ValueError('control habilitado previo; detener y revisar')
    budget=aggregate_budget(ROOT.parent,control.path,day)
    if budget['otherControlEnabled']:raise ValueError('otro control está habilitado; no iniciar otra copia')
    if budget['used']+required>10000:raise ValueError(f"cuota insuficiente: quedan {10000-budget['used']}, se reservan {required}")
    _,_,reader,environment=configuration(directory,profile_name)
    credentials,proof_file=profile_files(directory,profile_name)
    original_health=private_read(directory/'setup.json')['normalBackendHealthFile']
    heartbeat=read_heartbeat(original_health) or {}
    if heartbeat.get('connected') and fresh_timestamp(heartbeat.get('at'),time.time()):
        raise ValueError('el backend habitual está activo; detenerlo antes de iniciar la presentación')
    proof=private_read(proof_file)
    if (proof['host']!=reader['host'] or proof['port']!=reader['port']
            or proof['credentialsSHA256']!=hashlib.sha256(credentials.read_bytes()).hexdigest()
            or proof['readerSHA256']!=hashlib.sha256((directory/'reader.json').read_bytes()).hexdigest()):
        raise ValueError('volver a comprobar las cuentas después del cambio de configuración')
    load_credentials(credentials,profile.principals)
    run_dir=directory/'runs'/owner;run_dir.mkdir(mode=0o700)
    env={'PATH':os.environ.get('PATH','/usr/bin:/bin'),'LANG':'C','PYTHONPATH':str(ROOT/'backend'),**environment}
    nominal_count=json.loads(profile.raw)['limits']['nominalVehicleCount']
    actor_count=len(profile.principals)
    children=[];streams=[];stopping=ServiceStop(directory,owner);previous={};probe=None;result={'owner':owner,'state':'preparando','profile':profile_name,'expectedVehicles':nominal_count,'expectedActors':actor_count,'seconds':seconds,'reservedUpperBoundCalls':required,'dayUsedBefore':budget['used']}
    last_state=None
    def save(**fields):
        nonlocal last_state
        result.update(fields);result['seenAt']=time.time();private_json(directory/'status.json',result)
        if result['state']!=last_state:
            print({'preparando':'Preparando backend y conexión…','conectando':f'Iniciando {actor_count} balizas…',
                'listo':f'Listo: {nominal_count} micros vigentes con ocupación. Ya puedes abrir Mapa.',
                'detenido':'Presentación detenida.','fallo':'El servicio terminó con un fallo; revisar el resultado.'}.get(result['state'],result['state']),flush=True)
            last_state=result['state']
    def spawn(args,name):
        stream=(run_dir/name).open('x');streams.append(stream)
        child=subprocess.Popen(args,cwd=ROOT/'backend',env=env,stdout=stream,stderr=subprocess.STDOUT)
        children.append(child);return child
    actor=backend=None
    try:
        for signum in (signal.SIGINT,signal.SIGTERM):previous[signum]=signal.signal(signum,lambda *_:stopping.set())
        save()
        probe=Reader(reader);wait_for(lambda:probe.snapshot()['connected'],15,stopping)
        # El endpoint tiene un solo canal global de control. No sobrescribir
        # otra ejecución ni retroceder una revisión que no pertenece al ledger.
        time.sleep(.5);remote=probe.snapshot()['control'];local=control.read()
        if remote_control_conflicts(remote,local):
            raise RuntimeError('control remoto ajeno o más nuevo; revisar antes de habilitar')
        prior=read_heartbeat(str(directory/'health.json')) or {}
        if fresh_timestamp(prior.get('at'),time.time()):
            raise RuntimeError('hay un latido privado reciente; revisar antes de abrir otro backend')
        backend=spawn([sys.executable,'-u','-m','rutautp_backend'],'backend.log')
        spawn(['/usr/bin/caffeinate','-i','-w',str(os.getpid())], 'power.log')
        wait_for(lambda:(read_heartbeat(str(directory/'health.json')) or {}).get('connected') is True,30,stopping)
        if time.time()+seconds+20>=end:raise RuntimeError('ya no cabe la sesión antes del cierre de horario')
        control.enable(profile.pinned(),time.time());started=time.monotonic();deadline=started+seconds
        wait_for(lambda:(lambda s:s['backend']['fresh'] and s['runOwner'] is not None
            and s['mqtt']['lastAckedRevision']==s['controlRevision'])(status(control,time.time())),20,stopping)
        run_id=status(control,time.time()).get('runId')
        if run_id is None:raise RuntimeError('el backend no confirmó la identidad del run aplicado')
        actor=spawn([sys.executable,'-u','-m','simulation','--control-db',str(control.path),
            '--history-db',str(directory/'history.sqlite'),'--credentials-file',str(credentials),
            '--profile',profile_name,'--gtfs-dir',str(ROOT/'gtfs'),'--reference-jsonl',str(run_dir/'reference.jsonl'),'run'],'producer.log')
        save(runId=run_id,deadlineHostUptime=deadline,state='conectando',readyObserved=False)
        while not stopping.wait(.25):
            snapshot=probe.snapshot();current=status(control,time.time())
            remaining=deadline-time.monotonic()
            if remaining<=0:result['reason']='presentation_duration_finished';break
            if backend.poll() is not None:raise RuntimeError('el backend propio terminó')
            if actor.poll() is not None:raise RuntimeError('el productor terminó antes de tiempo: '+current['reason'])
            if not current['requestedEnabled']:raise RuntimeError('apagado previo al final: '+current['reason'])
            ready=(snapshot['currentVehicles']==nominal_count and current['producer'].get('status')=='running')
            if ready:result['readyObserved']=True
            if not result['readyObserved'] and time.monotonic()-started>max(45,actor_count*1.5):
                raise RuntimeError(f'no se confirmaron {nominal_count} micros vigentes; revisar cuentas y ACL')
            save(state='listo' if ready else 'conectando',probe=snapshot,remainingSeconds=max(0,remaining))
        result.setdefault('reason','presentation_operator_stop')
    except (OSError,ValueError,RuntimeError,ControlUnavailable,sqlite3.Error,subprocess.SubprocessError) as error:
        result.update(state='fallo',error=type(error).__name__)
        # Mensaje local sin excepciones Paho ni credenciales.
        if type(error) in (ValueError,RuntimeError):result['reason']=str(error)
        else:result['reason']='fallo del servicio; revisar el registro privado'
    finally:
        disabled=None
        try:disabled=control.disable(time.time(),result.get('reason','presentation_cleanup'))
        except (ControlUnavailable,OSError,sqlite3.Error):
            result.update(state='fallo',controlDisableConfirmed=False)
        if actor is not None and actor.poll() is None:
            actor.terminate()
            try:actor.wait(timeout=7)
            except subprocess.TimeoutExpired:actor.kill();actor.wait(timeout=3)
        if probe is not None:
            result['offDeliveryConfirmed']=None
            if backend is not None and disabled is not None:
                try:wait_for(lambda:received_current_off(probe.snapshot(),disabled),10)
                except RuntimeError:result['offDeliveryConfirmed']=False
                else:result['offDeliveryConfirmed']=True
            result['probe']=probe.snapshot()
            try:probe.close()
            except (OSError,ValueError,RuntimeError):result['probeCloseConfirmed']=False
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:child.wait(timeout=7)
                except subprocess.TimeoutExpired:child.kill();child.wait(timeout=3)
        for stream in streams:stream.close()
        for signum,handler in previous.items():signal.signal(signum,handler)
        result['ownedProcessesStopped']=all(c.poll() is not None for c in children)
        result['remainingSeconds']=0
        if result.get('state')!='fallo':result['state']='detenido'
        save();private_json(run_dir/'result.json',result)
    return result


def main(argv=None):
    parser=argparse.ArgumentParser(description='Presentación 30/50 balizas con tu broker MQTT existente')
    parser.add_argument('--directory',type=Path,default=DEFAULT_DIRECTORY)
    commands=parser.add_subparsers(dest='command',required=True)
    setup=commands.add_parser('preparar');setup.add_argument('--backend-config',type=Path,default=ROOT/'backend/deploy/backend.env')
    extend=commands.add_parser('preparar-perfil');extend.add_argument('--profile',choices=['pasajeros-50'],required=True)
    check=commands.add_parser('comprobar');check.add_argument('--profile',choices=PRESENTATION_PROFILES,default='pasajeros-30')
    start=commands.add_parser('iniciar');start.add_argument('--seconds',type=int)
    start.add_argument('--profile',choices=PRESENTATION_PROFILES,default='pasajeros-30')
    commands.add_parser('estado');commands.add_parser('detener')
    args=parser.parse_args(argv)
    try:
        if args.command=='preparar':result=prepare(args.directory,args.backend_config)
        elif args.command=='preparar-perfil':result=prepare_profile(args.directory,args.profile)
        elif args.command=='comprobar':
            with service_lock(args.directory):result=check_accounts(args.directory,args.profile)
        elif args.command=='iniciar':result=run_service(args.directory,args.seconds,args.profile)
        elif args.command=='estado':result=service_state(args.directory)
        else:result=stop_service(args.directory)
        print(json.dumps(result,ensure_ascii=False,allow_nan=False,indent=2))
        return 2 if result.get('state')=='fallo' else 0
    except (OSError,ValueError,RuntimeError,ControlUnavailable,KeyError,sqlite3.Error,subprocess.SubprocessError) as error:
        # No mostrar mensajes de librerías que podrían incorporar secretos.
        print(json.dumps({'started':False,'error':type(error).__name__,
            'reason':str(error) if type(error) in (ValueError,RuntimeError) else 'configuración o proceso no disponible'},ensure_ascii=False))
        return 2
