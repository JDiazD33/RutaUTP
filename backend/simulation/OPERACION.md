# S09 — Observación y operación privada

Código preparado, sin despliegue ni productores iniciados. Primera población:
**30 pasajeros / 10 micros nominales**. S10 añade `ensayo-2` (2/1) y `ensayo-6` (6/2);
véase [VALIDACION.md](VALIDACION.md). Ampliar a 50 o
100 requiere revisar otro manifiesto y sus presupuestos.

## Qué significa cada número

| Dato | Fuente / alcance |
| --- | --- |
| Actores previstos | 30 del manifiesto fijado, no personas reales conectadas. |
| Pasajeros activos | Actores a bordo en el último estado fresco del productor; varía con el escenario. |
| Conexiones MQTT | Sockets autenticados del productor; una sesión de abordaje no crea otra persona. |
| Actores listos | Conexión y control vigentes para poder emitir. |
| Vehículos nominales | 10 del escenario; no fuerzan el resultado del agrupador. |
| Vehículos estimados | Estimaciones internas actuales del backend; pueden no tener quorum publicable. |
| IDs estimados históricos | IDs distintos vistos durante un run; no es una cantidad simultánea. |
| Filas de posición | Datos guardados; en sintéticos se guardan antes de llamar al transporte. No prueban PUBACK ni recepción iOS. |
| `enqueuedPositions` / `published` histórico | Publicador aceptó la entrega; no confirma recepción de la app. |
| PUBACK de observaciones | Broker confirmó mensajes del productor; no prueba aceptación del backend. |
| PUBACK de control | Broker confirmó esa revisión; no prueba limpieza de pantalla. |
| Posiciones recibidas por app / marcadores | `null`: sin telemetría de retorno del iPhone. El máximo de marcadores es 8; no se devuelve 8 como medición. |

Las métricas en memoria separan `observed`, `simulated` y `unknown`. Un rechazo
anterior a verificar origen/run se atribuye a `unknown`, aunque el texto del tópico
parezca sintético. Los runs de métricas se limitan a los últimos 32 incorporados;
se cuenta su expulsión y se conservan totales por origen. Se reinician con el
proceso; SQLite permite análisis histórico separado.

El latido añade contadores por origen/run, error de control, estado de persistencia,
fallos de escritura y datos del controlador. La salud sintética se evalúa aparte:
su caída no cambia la política del flujo observado. Una marca temporal booleana,
no finita, futura o de 15 s de edad no se acepta como evidencia fresca.

## Consulta y reporte

Ejemplos **no ejecutados contra un despliegue**. Ejecutar desde `backend` con el
Python del servicio. Las rutas y el UUID son elecciones explícitas del operador;
no cargar credenciales para consultar.

```sh
SIM_CONTROL_DB=/ruta/privada/control.sqlite
SIM_HISTORY_DB=/ruta/privada/history.sqlite
SIM_HEALTH_FILE=/ruta/privada/health.json
SIM_RUN_ID=uuid-canonico-del-run

python -m rutautp_backend.simulation_admin \
  --control-db "$SIM_CONTROL_DB" --health-file "$SIM_HEALTH_FILE" status

python -m rutautp_backend.simulation_admin \
  --history-db "$SIM_HISTORY_DB" report --run-id "$SIM_RUN_ID"

python -m rutautp_backend.simulation_admin \
  --history-db "$SIM_HISTORY_DB" report --run-id "$SIM_RUN_ID" --format comparison-jsonl

python -m rutautp_backend.simulation_admin \
  --history-db "$SIM_HISTORY_DB" report --run-id "$SIM_RUN_ID" --format comparison-csv
```

`status` lee orden y runtime en la misma transacción del control. Distingue orden
guardada, revisión aplicada, revisión encolada, PUBACK y estado del productor.
Un productor antiguo/caducado es `unknown`; tras disable y antes de detenerse es
`revocation_pending`. Sus contadores caducados son `null`, no ceros. Un latido de
otra revisión, propietario o run no aporta estimaciones al status actual.
`clientsApplied` sigue siendo `unknown`.

`report` abre SQLite con `mode=ro` y `query_only`, en una transacción consistente.
No crea bases ausentes ni migra versiones. Incluye perfil, versión, semilla,
hashes, estado, historial incompleto/purgado, filas guardadas y rechazos por motivo.
Una consulta no comprueba que el escritor siga pudiendo guardar: esa evidencia
corresponde al latido del proceso y a `history_complete`.

La comparación JSONL/CSV se procesa por cursor. Une observación y referencia de
abordaje usando run, sesión, ruta y ventana temporal; conserva origen y run en
cada fila. El ID nominal nunca se entrega al algoritmo para fijar un resultado.
La referencia geométrica JSONL opcional de S06 se conserva aparte para el ensayo
de latencia/error de S10; este reporte no afirma haberla medido.

`nominalWithMultipleEstimatedIds` y `estimatedIdsWithMultipleNominals` son
**asociaciones históricas**, candidatas a investigar. Un ID que cambia con el tiempo
no demuestra una división simultánea; se debe contrastar la referencia temporal.
El reporte indica observaciones sin referencia y detalle parcial tras retención.
Los CSV protegen los identificadores que podrían interpretarse como fórmulas al
abrirlos en una hoja de cálculo; JSONL conserva el valor literal.

## Supervisor

```sh
python -m rutautp_backend.simulation_supervisor \
  --control-db "$SIM_CONTROL_DB" --health-file "$SIM_HEALTH_FILE" check

python -m rutautp_backend.simulation_supervisor \
  --control-db "$SIM_CONTROL_DB" --health-file "$SIM_HEALTH_FILE" --interval 5 watch

python -m rutautp_backend.simulation_supervisor \
  --control-db "$SIM_CONTROL_DB" --health-file "$SIM_HEALTH_FILE" guard
```

- `check`: una consulta, salida 0 si no requiere acción y 2 si detecta problemas.
- `watch`: repite consultas de solo lectura cada 1–5 s; Ctrl+C termina ese lector.
- `guard`: una comprobación con posibilidad explícita de **guardar disable** ante
  fallo de latido/conexión/histórico/control, generación/revisión incoherente,
  PUBACK ausente, productor detenido/caducado, duración, horario o presupuesto.
  Usa compare-and-swap de la revisión inspeccionada. Si cambió, no toca la nueva.

El productor tiene 15 s desde el inicio del run para presentar su estado; esa
gracia no convierte en sano un fallo del histórico o del backend. Conexiones
parciales y variaciones de rampa se muestran, sin exigir 30 pasajeros constantes.

El supervisor no habilita ni reinicia productores, no abre MQTT y no mata PIDs.
`guard` no es un daemon: una política periódica requeriría instalación posterior
expresa en el host elegido. No se creó cron, launchd, systemd ni una automatización.
Si el control no se puede guardar, informa el fallo y depende de la caducidad de
leases; no anuncia un apagado aplicado. Un disable guardado tampoco demuestra
que el backend lo publicó ni que los iPhones lo aplicaron.

## Presupuestos y retención

Se conservan **900 s por run, 6.000 reservas/run y 6.000 reservas/día** del perfil
inicial, con fecha America/Lima. S06 reserva antes de intentar publicar; fallar
después no devuelve la reserva. Cambiar run o reiniciar el productor no reinicia
el total diario. No borrar/restaurar el ledger de control para recuperar cuota.
Estos límites no son una cuota garantizada del broker ni una medición de capacidad.

No se activa retención automática. La propuesta de **7 días de detalle / 30 de
resúmenes** sigue pendiente de elección del propietario. Los siguientes parámetros
son explícitos y `retention-plan` solo consulta:

```sh
python -m rutautp_backend.simulation_admin --history-db "$SIM_HISTORY_DB" \
  retention-plan --run-id "$SIM_RUN_ID" --detail-days 7 --summary-days 30
```

Después de exportar y comprobar un backup consistente/restaurable, una orden
deliberada puede purgar detalle de **un run sintético terminado** y suficientemente
antiguo. No se ejecutó esta orden en un despliegue durante S09:

```sh
python -m rutautp_backend.simulation_admin \
  --control-db "$SIM_CONTROL_DB" --history-db "$SIM_HISTORY_DB" \
  purge-detail --run-id "$SIM_RUN_ID" --detail-days 7 --summary-days 30 --apply
```

La operación exige histórico ya migrado, run terminal fuera del control activo y
horizontes positivos/acotados. Conserva un resumen previo a la primera purga y
marca `detail_purged_before`; una purga posterior no reemplaza los conteos
originales por los ya reducidos. No borra observados, legado, otros runs, control,
presupuestos ni resúmenes. Cumplir 30 días se informa, **sin implementar borrado
de resúmenes** antes de esa decisión del propietario. La retención general previa
del backend conserva su configuración y excluye detalle sintético.

## Despliegue gradual y parada

1. Elegir host, ventana corta, almacenamiento, límites efectivos de EMQX y
   dispositivos receptores. Guardar versión, semilla y hashes. Ninguno se deduce
   de que exista una configuración local.
2. Instalar primero el cliente con S07/S08. Sus builds están comprobadas, pero no
   se instaló esa versión en el iPhone en S09. Excluir lectores antiguos del ensayo.
3. Con productores y control apagados, backup SQLite por API y prueba de
   restauración; verificar esquema aditivo y ACL efectivas en ambas direcciones.
4. Coordinar `BACKEND_VEHICLE_POSITION_SCHEMA_VERSION=2` en la configuración del
   despliegue. La plantilla del repositorio permanece en v1 y simulación OFF.
   Preparar la rama/control con `BACKEND_SIMULATION_INGRESS_ENABLED=1` y la ruta
   privada del control únicamente al preparar ese despliegue, todavía deshabilitado.
5. Ejecutar las verificaciones y ensayos autorizados de S10. Los ensayos reducidos
   2 actores/1 vehículo y 6/2 tienen perfiles específicos preparados en S10.
   No cambiar quorum ni pasar un
   contador arbitrario a `pasajeros-30` para fingirlos.
6. Tras esos ensayos, enable manual dentro de horario, verificar revisión aplicada
   y PUBACK, y arrancar un productor S06 explícito. No programar una jornada
   completa. `check` del productor valida archivos; no prueba ACL ni guardado real.
7. Comparar referencia, aceptaciones, rechazos, conexiones y estimaciones antes
   de ampliar a 30 completos. Registrar CPU/RAM/red/disco/latencia y limpieza de
   iOS con condiciones reproducibles; esas medidas siguen pendientes de S10.

Parada: guardar `disable --reason ...`, comprobar la nueva revisión y publicación,
esperar estado fresco `stopped` del productor y verificar limpieza de la app.
S06 corta sockets y colas ante revocación; si hace falta intervención manual,
detener la terminal del productor correcto, no buscar/matar un PID sin identidad.
Mantener el backend observado activo. Deshabilitar/revocar únicamente las cuentas
sintéticas si se retira el ensayo y conservar referencia, histórico y reportes.

No restaurar una base vieja de control ni arrancar un backend que ignore el
apagado mientras existan productores/cuentas habilitados. La copia de SQLite y
el rollback conservan la procedencia y el historial, sin downgrade destructivo.
