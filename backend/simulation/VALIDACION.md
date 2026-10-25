# S10 — Validación reproducible

El informe fechado y sus resultados están en `mds/INFORME-S10-SIMULACION-BALIZAS.md`,
fuera de este repositorio Git. Las ejecuciones de ejemplo requieren una solicitud
de ensayo; importar los módulos o compilar la app no los inicia.

## Perfiles fijados

| Perfil | Principales / micros nominales | Límite del run | Publicaciones run / día |
| --- | --- | --- | --- |
| `ensayo-2` | 2 / 1 | 300 s | 240 / 6000 |
| `ensayo-6` | 6 / 2 | 300 s | 720 / 6000 |
| `pasajeros-30` | 30 / 10 | 900 s | 6000 / 6000 |

Los escalones pequeños tienen manifiesto, whitelist, cuentas y presupuesto
propios. Se mantienen quorum 2, cadencia 5 s, tiempo real 1×, GTFS y ventana de
servicio del perfil. No hay perfil 50/100. El original 30/10 no se modifica.

## Prueba conectada aislada en la Mac

Desde la raíz Git, con el entorno Python preparado y Mosquitto instalado:

```sh
PYTHONPATH=backend backend/.venv/bin/python -m simulation.local_trial \
  --profile ensayo-2 --output /RUTA/EXTERNA/NUEVA/ensayo-2 --seconds 270 run
```

La carpeta padre debe existir; la salida debe ser nueva y estar fuera del
repositorio. El ensayo crea broker, control e histórico propios, sin leer `.env`
ni heredar destino/credenciales/base/APNs del entorno. Usa cuentas aleatorias
distintas y verifica cuatro denegaciones de escritura con PUBACK MQTT 5 real:
sim→observaciones normales, lector→sim y sim→vehículos/control.

`--seconds` mide la fase estable de CPU/RSS, después del arranque de conexiones.
Su máximo es el límite del run menos 30 s de margen. Por tanto 270/870 s de
captura no deben presentarse como 300/900 s íntegros de carga estable. Registrar
también `started_at`/`ended_at` del reporte histórico.

## iPhone físico

Compilar e instalar Release para el iPhone por separado, con su firma habitual.
El teléfono debe estar desbloqueado y poder acceder a la IP privada de la Mac.
Usar la IPv4 concreta de la interfaz; no se admite una dirección pública o
comodín. El broker de este ensayo usa TCP sin TLS en esa red local privada.

```sh
PYTHONPATH=backend backend/.venv/bin/python -m simulation.local_trial \
  --profile pasajeros-30 --output /RUTA/EXTERNA/NUEVA/ensayo-30 \
  --seconds 870 --listen-host IP_PRIVADA_MAC --device UDID_IPHONE run
```

El comando relanza RutaUTP. Con el lector efímero y su configuración completa,
la versión preparada para S10 abre **Mapa** directamente. Permitir la red local
si iOS lo pide; se esperan hasta 600 s de confirmación antes de activar actores.
Mantener el mapa en primer plano. Se usa la recepción MQTT real del mapa.

`RUTAUTP_S10_TRIAL=1` llega solo al proceso lanzado por devicectl. Exige la
configuración MQTT completa, evita Keychain/UserDefaults y bloquea la contribución
pasiva sin borrar su consentimiento guardado. Una configuración incompleta cierra
esa conexión y no recupera otro servidor. No existe interruptor público.

El observador confirma recepción y cuenta flota completa; después captura 30 s
con Time Profiler. La consola registra únicamente cantidades/tiempos de control,
recepción y mapa. Al apagar, espera confirmación de control OFF y flota vacía.
La cota de retirada usa el reloj monotónico de la Mac desde guardar disable
hasta observar la línea de mapa vacío; incluye espera de lectura y consola,
sin depender de sincronizar relojes de ambos dispositivos.

Si la CLI de Instruments no logra adjuntarse, el resultado conserva
`traceCaptured=false` y CPU iPhone desconocida para esa captura automática.
Una captura complementaria debe guardarse y exportarse por separado,
identificando PID, run, UUID Release y duración. Si se grabó el dispositivo
completo, sumar únicamente las muestras Running del PID verificado de RutaUTP;
confirmar también su UUID en las imágenes de las muestras. Registrar el método
complementario en `validation.json` sin reescribir el fallo automático.
`complete` del ensayo y la medición iOS son comprobaciones distintas.

## Evidencia e interpretación

- `result.json`, `history.sqlite`, `reference.jsonl`, `comparison.csv`.
  `health.json` es un heartbeat vivo que el backend retira al cerrar normalmente;
  el ensayo conserva la última copia previa al apagado en `heartbeatBeforeDisable`.
- `resources.jsonl`: CPU acumulada de `ps` y muestras RSS de backend/productor/broker.
  CPU media = diferencia de segundos CPU / segundos monotónicos × 100, un núcleo.
  El pico/p95 es por intervalo, no instantáneo; RSS no es memoria exclusiva.
- `device-console.log`, `instruments.log`, `iphone-time-profiler.trace` con iPhone.
  Exportar y analizar la traza antes de informar CPU del teléfono; capturar la
  traza por sí solo no rellena `cpuPctOneCore` en el resultado.

Identificadores históricos distintos no equivalen a vehículos simultáneos.
Treinta actores no son treinta personas reales ni treinta marcadores; el mapa
recibe toda la flota y su presentación mantiene el límite de ocho. No se mide
red, batería o energía mediante `ps` o Time Profiler.

En un error o interrupción se intenta revocar el run y se detienen únicamente los
procesos propios. Se eliminan las contraseñas temporales y se conserva la
evidencia histórica. Confirmar `ownedProcessesStopped` y control OFF al cerrar.
EMQX, disponibilidad diaria, 50/100 actores y pruebas de jornada requieren otro
ensayo; no quedan desplegados por ejecutar esta herramienta.
