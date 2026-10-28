#!/usr/bin/env python3
"""Aprovisiona una vez la cuenta lectora, sin contraseñas en argumentos o logs."""
from pathlib import Path
import argparse
import getpass
import json
import os
import subprocess
import sys
import tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from simulation.presentation import DEFAULT_DIRECTORY, private_read


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=DEFAULT_DIRECTORY)
    parser.add_argument('--device',required=True)
    parser.add_argument('--bundle-id',default='apolito.RutaUTP.dev-joaquindiaz.RutaUTP')
    parser.add_argument('--restaurar',action='store_true',help='recuperar la cuenta/destino habitual conservados')
    parser.add_argument('--contribution-user',help='cuenta propia existente del iPhone; pide su contraseña solo en Terminal')
    args=parser.parse_args(argv)
    if args.contribution_user and (args.restaurar or not args.contribution_user.startswith('device-')):
        parser.error('--contribution-user requiere una cuenta device- propia y no se combina con --restaurar')
    descriptor,path=tempfile.mkstemp(prefix='rutautp-provision-',suffix='.json');os.close(descriptor)
    try:
        environment={k:v for k,v in os.environ.items() if not k.startswith('DEVICECTL_CHILD_')}
        if args.restaurar:values={'MQTT_PRESENTATION_MODE':'0'}
        else:
            reader=private_read(args.directory/'reader.json')
            if reader['tls'] is not True:raise ValueError('se exige TLS para aprovisionar el broker remoto')
            values={'MQTT_HOST':reader['host'],'MQTT_PORT':str(reader['port']),'MQTT_TLS':'1',
                'MQTT_USERNAME':reader['username'],'MQTT_PASSWORD':reader['password'],'MQTT_PRESENTATION_MODE':'1'}
            if args.contribution_user:
                password=getpass.getpass('Contraseña MQTT de '+args.contribution_user+' (no se mostrará): ')
                if not password:raise ValueError('contraseña vacía')
                values.update(MQTT_CONTRIBUTION_USERNAME=args.contribution_user,MQTT_CONTRIBUTION_PASSWORD=password)
        environment.update({'DEVICECTL_CHILD_'+k:v for k,v in values.items()})
        command=['xcrun','devicectl','device','process','launch','--device',args.device,'--timeout','30',
            '--json-output',path,'--terminate-existing',args.bundle_id]
        result=subprocess.run(command,env=environment,capture_output=True,timeout=35)
        raw=json.loads(Path(path).read_text())
        if result.returncode or raw.get('info',{}).get('outcome')!='success':
            raise RuntimeError('no se confirmó la apertura en el iPhone')
        pid=raw.get('result',{}).get('processIdentifier')
        print(json.dumps({'launchConfirmed':True,'processIdentifier':pid if type(pid) is int else None,
            'configurationPersistenceRequiresAppVerification':True,'restoring':args.restaurar,
            'next':'cerrar y abrir desde el icono sin Xcode; verificar Mapa y recepción'}))
        return 0
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as error:
        print(json.dumps({'launchConfirmed':False,'error':type(error).__name__}))
        return 2
    finally:Path(path).unlink(missing_ok=True)


if __name__=='__main__':raise SystemExit(main())
