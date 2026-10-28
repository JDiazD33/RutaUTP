# S10 — Validación reproducible

El informe fechado y sus resultados están en `mds/INFORME-S10-SIMULACION-BALIZAS.md`,
fuera de este repositorio Git. Las ejecuciones de ejemplo requieren una solicitud
de ensayo; importar los módulos o compilar la app no los inicia.

## Perfiles fijados

| Perfil | Principales / micros nominales | Límite del run | Publicaciones run / día |
| --- | --- | --- | --- |
| `ensayo-2` | 2 / 1 | 300 s | 240 / 6000 |
| `ensayo-6` | 6 / 2 | 300 s | 720 / 6000 |
| `pasajeros-30` v2 | 30 / 10 | 900 s | 6000 / 10000 |

Los escalones pequeños tienen manifiesto, whitelist, cuentas y presupuesto
propios. Se mantienen quorum 2, cadencia 5 s, tiempo real 1×, GTFS y ventana de
servicio del perfil. No hay perfil 50/100. Se conservan los 30 actores y 10 vehículos nominales; la revisión v2 solo amplía el tope diario de ese perfil.

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


## Seguimiento posterior a S10

Métricas originales guardadas por petición del usuario en
`/Users/joaquindiaz05/Documents/RU-IOQT/metricas/INFORME-S10-SIMULACION-BALIZAS.md`.
El nuevo ensayo de contención/ocupación registra evidencia separada y no sustituye
el intervalo original de 15 minutos ni sus métricas. Véase el informe posterior
en esa misma carpeta `metricas`.

## Medición propia de CPU y diagnóstico sin actores (23/10/2026)

`TrialProcessResources` lee los contadores acumulados de usuario y sistema del
proceso propio mediante `getrusage(RUSAGE_SELF)`, con resolución de microsegundos.
Se usa solo cuando están presentes **ambos** indicadores de ensayo:
`RUTAUTP_S10_TRIAL=1` y `RUTAUTP_S10_RESOURCE_SAMPLING=1`. El proveedor emite una
muestra por segundo y detiene el timer al detenerse o fallar su arranque. La app
normal no inicia este muestreo. No publica datos MQTT adicionales ni guarda
credenciales, posiciones o RSS en estos eventos.

Fuente primaria: [manual de Apple de getrusage](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html).
Se emplean solamente los tiempos de usuario/sistema documentados; no se deduce
footprint ni energía de los otros campos del sistema.

`simulation.device_resources` valida PID exacto, versión, unidades, contadores
monotónicos, reloj del dispositivo, aplicación activa, al menos 29 s y ausencia
de huecos mayores de 5 s. La media usa delta CPU / delta de tiempo, normalizada
a un núcleo. No promedia porcentajes de intervalos de distinta duración. Un
resultado vacío, breve o inconsistente queda incompleto, no como 0 %.

`DeviceObserver` activa este muestreo y usa exclusivamente el intervalo de
consola del iPhone comprendido en la captura. El guardado de una traza de
Instruments no acredita CPU. El perfilador queda opcional (`--instruments`) y
crea una sola sesión para todos los procesos; se eliminó el acoplamiento por PID
que fallaba y competía con capturas complementarias. La CPU propia no incluye
pilas y su método debe identificarse al comparar con el Time Profiler anterior.

El comando `--control-only` es un diagnóstico explícito del iPhone: inicializa
control OFF, no crea productor, no ejecuta enable y exige cero runs,
observaciones, posiciones y micros visibles. Por eso puede ejecutarse fuera del
horario de servicio sin activar el escenario. Requiere `--device`, interfaz LAN
privada y una Release compatible instalada. `--check-reconnect` solo se permite
en este modo y reinicia el broker propio después de cerrar el intervalo de CPU.
Verifica desconexión, nueva conexión, suscripción y estado OFF recibidos en orden.
No cambia Wi-Fi, datos móviles ni otros brokers. No acredita la retirada de una
flota activa durante un corte de red.

Ejemplo, con un directorio de salida nuevo fuera de Git y el iPhone desbloqueado:

```sh
PYTHONPATH=backend backend/.venv/bin/python -m simulation.local_trial \
  --profile pasajeros-30 --output /ruta/nueva/diagnostico \
  --seconds 35 --listen-host IP-PRIVADA-DE-LA-MAC --device UDID \
  --control-only --check-reconnect run
```

El resultado distingue `functionalComplete` (circuito funcional) y `complete`
(incluye CPU válida si hay iPhone). `iPhoneMeasured` ahora exige muestras válidas
del contador, no la mera salida 0 de Instruments. Un diagnóstico en vacío no
sustituye la medición con 30 balizas.

Para el tramo sostenido se conserva el perfil de máximo 900 s y la captura de
870 s con margen de apagado. Antes de arrancar, verificar ventana [07:00,22:30)
y presupuesto agregado entre todos los controles aislados de la fecha Lima:
reservar las 6000 llamadas del perfil para el ensayo largo. No resetear ni elevar
los contadores para encajarlo. La captura con 30 balizas, los cortes con flota
activa y la suspensión física de iOS siguen pendientes si el horario o el
presupuesto impiden ejecutarlos. Conservar los estados Vacío/Con espacio/Lleno.


## Ensayo físico del 26 de octubre de 2026

El intento sostenido con 30 actores, 10 vehículos nominales y ocupación terminó
antes del objetivo: captura Mac de 543,098 s frente a 870 s solicitados, apagado
automático `backend_or_puback_expired`. Se conservaron 3108 observaciones
aceptadas, cero rechazos y 1054 posiciones con ocupación válida; esto no acredita
la aceptación sostenida. La CPU global del iPhone quedó inválida por huecos de
5,658 s y 20,258 s. Los segmentos independientes válidos dieron 27,43% durante
403 s y 29,68% durante 116 s, normalizados a un núcleo. No unirlos ni sustituir
por el resultado de mapa vacío anterior. El usuario confirmó Mapa visible.

Se reprodujo y corrigió una carrera de `LocalAuthority`: evaluar el lease desde
la muestra completa del tick, incluyendo su antigüedad previa a las lecturas.
Un ACK realmente futuro o vencido y un retroceso monotónico siguen rechazados.
El harness distingue el OFF automático previo del apagado manual, exige la
revisión manual exacta al medir su entrega y no publica latencias negativas o
una retirada manual cuando ya estaba OFF. Se añadieron únicamente los grants
exactos de escritura backend para los dos status existentes de cambios y
ocupación. El nuevo diagnóstico iOS de instancia/inicio/parada/ciclo de vida
requiere ambos flags explícitos del ensayo y no cambia leases, timers ni
reconexión. Tras estas correcciones pasaron 686 casos Python offline en los
26 archivos de regresión; Debug y Release de simulador compilaron. La nueva
medición física sostenida sigue pendiente.

El informe y las métricas están en la carpeta `metricas` del workspace padre,
con fecha 2026-10-26; la evidencia cerrada está en
`mds/evidencias-ensayo-sostenido-30-2026-10-26`. El intento usó el perfil v1. La revisión v2 del 26 de octubre eleva solo su
techo diario a 10.000 para permitir un reintento completo, conservando 6.000/run,
900 s/run y las 3108 reservas ya consumidas. No se restableció el ledger.


El reintento v2 del mismo día conservó 2915 observaciones aceptadas, cero
rechazos y 988 posiciones con ocupación válida. La CPU parcial del iPhone fue
27,89% de un núcleo durante 488 s, con 489 muestras continuas. La consola de
desarrollo se perdió antes del apagado. Después, pmset confirmó Clamshell Sleep
y suspensión de mantenimiento de la Mac; el productor detectó discontinuidad
civil/monotónica y persistió OFF. La captura Mac de 509,792 s no completó 870 s
y la retirada visual posterior no quedó observada. La pérdida previa de consola
no se atribuye a la suspensión posterior. Control OFF y procesos propios cerrados
fueron comprobados; no se relajó la protección de reloj.

Se reservaron 6023 llamadas agregadas del día entre ambos controles, sin borrar
el consumo. Con horario ya cerrado y menos de 6000 reservas disponibles no se
inició un tercer ensayo. Tras la cuota v2 pasaron 723 casos Python en los 26
archivos y una regresión adicional de cambio de generación (724 distintos),
además de builds genéricos Debug/Release y Release física firmada. El informe de
cierre está en `metricas/INFORME-S10-30-BALIZAS-2026-10-26.md` del workspace padre.
La aceptación sostenida, corte con flota activa y suspensión física iOS siguen
pendientes; no se activaron perfiles 50/100 ni automaciones.

## Fallos con flota activa: modo opt-in

`--check-active-faults` exige iPhone físico, `pasajeros-30`, ocupación y una
captura inicial de 35 s. El intervalo de CPU termina antes de provocar los
fallos. El plazo total desde ON es de 300 s, con margen final de limpieza;
reservar como máximo 1830 publicaciones del presupuesto agregado diario.

```sh
PYTHONPATH=backend backend/.venv/bin/python -m simulation.local_trial \
  --profile pasajeros-30 --seconds 35 --scenario-occupancy \
  --listen-host IP_PRIVADA_MAC --device UDID_IPHONE \
  --check-active-faults --output /ruta/nueva/fallos-activos run
```

Después de confirmar diez modelos y su ocupación, el observador solicita volver
a Inicio sin forzar el cierre. Comprueba background y mapa vacío, suspende el
PID propio con CoreDevice durante 25 s, lo reanuda y activa la misma instancia.
Exige control vigente antes de recuperar la flota. Esto acredita una suspensión
forzada del proceso en iOS físico; la política automática de suspensión del
sistema requiere una observación independiente.

Después detiene únicamente el broker local propio durante 25 s. Comprueba la
retirada de buses y ocupación en un máximo de 20 s, OFF automático por caducidad,
reconexión con control deshabilitado y ausencia de reaparición de buses. No
modifica Wi-Fi ni servicios externos. `device-faults.jsonl` conserva las fases y
los resultados sanitizados; no contiene credenciales. El resultado separa CPU
inicial, suspensión, corte y limpieza. Un fallo parcial no acredita todo el modo.

El estado administrativo de un productor terminado pasa a `unknown` al caducar
su último latido. El ensayo exige primero un `stopped` reciente y la salida de
su proceso propio; después conserva esa prueba, confirma que el proceso sigue
terminado y que el mismo run permanece OFF. No convierte un latido viejo en
actividad vigente ni cambia la política de frescura del backend.

## Cierre físico del 27 de octubre de 2026

El ensayo largo completó 870,024 s con 30 principales y diez vehículos nominales,
4957 observaciones guardadas, cero rechazos y 1681 posiciones. Los estados de
ocupación fueron Vacío (585), Con espacio (921) y Lleno (175). El apagado manual
retiró modelos y ocupación en un máximo observado de 1,157 s desde la Mac;
el intervalo OFF→mapa vacío del reloj del iPhone fue 24,30 ms.

La media CPU del iPhone fue 25,20% de un núcleo durante 874 s de contadores
continuos. Incluye tres intervalos breves de inactividad de UIKit (7,25 s entre
notificaciones); el usuario no observó interrupciones. Se conserva inválido el
artefacto que exige primer plano continuo durante todo el tramo. La media que
incluye ambos estados y los segmentos separados no sustituyen esa aceptación.

El último ensayo de fallos completó 117,571 s: suspensión forzada de 25,404 s
con el mismo PID, recuperación con control vigente, corte del broker propio de
25 s, retirada de modelos/ocupación en ≤0,114 s y reconexión a OFF sin reaparición.
El observador tardó ≤12,182 s desde reiniciar el broker hasta terminar de
comprobar la reconexión, incluidos cinco segundos adicionales de observación.
La CPU inicial, separada de los fallos, fue 17,29% durante 35 s. Guardó 399
observaciones sin rechazos y 135 posiciones con los tres estados de ocupación.
La revisión offline independiente aceptó todos los checks de este último ensayo.

Se conservan los dos intentos parciales: uno agotó la espera del paso a segundo
plano; otro completó suspensión y reconexión, pero su verificador exigía un
latido `stopped` todavía reciente al final. Tras corregir esa comprobación
pasaron 306 pruebas offline en nueve archivos. Debug y Release genéricos arm64
de simulador compilaron sin diagnósticos de advertencia/error en esos logs.
Las mediciones físicas corresponden a Release del commit `31482f0`; los builds
finales incluyen los refactors posteriores registrados en su manifiesto.

Los cuatro controles aislados consumieron 6884 de las 10000 reservas del día
Lima, sin restablecerlas. Todos quedaron OFF, los procesos propios terminaron y
se retiraron las credenciales temporales. El informe y los JSON están en
`metricas/INFORME-S10-30-BALIZAS-2026-10-27.md` del workspace padre; la evidencia
original está en `mds/evidencias-s10-validacion-30-2026-10-27`.

Permanece pendiente la aceptación de CPU con primer plano estrictamente continuo
durante el ensayo largo. La suspensión automática elegida por iOS, FPS, energía,
batería y el número de marcadores efectivamente dibujados no fueron medidos. El
límite de render sigue siendo ocho aunque se reciban diez modelos. Los perfiles
50/100 y la operación continua son fases posteriores; no se activaron aquí.

## Actualización de presentación del 28 de octubre

El cierre anterior describe la versión medida en S10. Después se validó la
presentación sin cable, el perfil de 50 balizas / quince micros y el selector
de cantidad visible en Ajustes. El límite fijo de ocho corresponde a la versión
anterior, no a la configuración actual. Resultados y límites de cada medición:
[RESULTADOS-PRESENTACION-2026-10-28.md](RESULTADOS-PRESENTACION-2026-10-28.md).
