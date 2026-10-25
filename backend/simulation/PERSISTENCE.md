# Histórico con procedencia — S02

S02 añade almacenamiento y migración. La entrada sintética, el controlador y el
generador se integrarán en S03–S06. Estas APIs no habilitan productores ni cambian
los mensajes MQTT. No se ha abierto/migrado una base activa durante la entrega.

## Versiones y migración

La base anterior tenía `PRAGMA user_version = 0`. El nuevo **esquema SQLite 1** se
define en `rutautp_backend/migrations/001_simulation_provenance.sql`. Este número es
independiente de las versiones de observación/posición/control de S01.

Al abrir `ObservationStore`, una base nueva se crea en una transacción. Una base
anterior debe contener las tres tablas y columnas esperadas. Antes de modificarla
se crea un snapshot consistente con `sqlite3.Connection.backup`, incluyendo lo
confirmado en WAL, en `backups/` junto al archivo. El backup usa un nombre exclusivo,
archivo privado y `quick_check`; si no hay margen de disco o falla la copia, no se
migra. El margen requerido incluye el tamaño estimado de la copia y 16 MiB libres.

La migración usa `BEGIN IMMEDIATE`, añade tablas/columnas/índices y registra su
versión antes de confirmar. Un fallo revierte la transacción. El backup permanece
para revisión. Una apertura posterior valida columnas y registro de versión sin
reaplicar ALTER TABLE ni crear otra copia. Versiones futuras, esquemas parciales o
una versión sin registro coherente se rechazan sin adoptar ni borrar sus datos.
El paquete desplegado debe incluir también el archivo SQL, no solo los `.py`.

## Datos guardados

| Tabla | Procedencia y referencia |
| --- | --- |
| `observations` | `data_origin`, `simulation_run_id`, sesión y vehículo estimado existentes. |
| `vehicle_positions` | Los mismos campos de origen/run y todos los datos históricos anteriores. |
| `rejections` | Origen/run conocidos; `unknown` si todavía no hay contexto confiable. |
| `simulation_runs` | Perfil/versión, semilla, hash del manifiesto y hashes del feed, fechas, estado, motivo, contadores e integridad del histórico. |
| `simulation_actors` | Principal, sesión de abordaje, vehículo nominal y ruta de referencia; inicio/fin y motivo de bajada, sin secretos. |
| `store_schema_migrations` | Versión aplicada, fecha y ruta del backup previo cuando correspondía. |

Las filas anteriores adquieren **`legacy_unknown`**, con run null, sin reescribir
sus valores originales ni declararlas observadas retrospectivamente. Las nuevas
llamadas habituales de observación/posición usan `observed` explícito. Un rechazo
sin contexto usa `unknown`; S03 pasará contexto observado/sintético cuando pueda
determinarlo con confianza. Un run desconocido no se presenta como un run válido.

Las claves foráneas se activan en la conexión. Un dato sintético necesita un run
registrado; observados/desconocidos/legados no pueden asociarse a un run. El índice
compuesto por origen, run y fecha permite separar consultas y purgas. Los nombres
de tabla de exportación están limitados a una lista interna.

`SourceContext` es un modelo interno, no una bandera extra del payload de una
baliza. Su identidad deberá obtenerse en S03 de tópico/ACL/registro. El almacén no
autentica MQTT. Los UUID nuevos del backend/generador son canónicos en minúsculas.
Los modelos actuales `Observation`, `EstimatedVehicle` y sus mensajes permanecen
sin cambios.

## API que consumirán las tareas siguientes

- `create_simulation_run(record)` guarda y confirma un run nuevo en `prepared`.
- `set_simulation_run_status` confirma las transiciones y totales; no permite
  reactivar un run terminado ni completar uno heredado de otra apertura. Un run
  interrumpido se debe cerrar como fallido y sustituir por un UUID nuevo en S04.
- `record_simulation_actor` guarda cada abordaje antes de sus observaciones. Una
  repetición idéntica es idempotente; la sesión no cambia de principal, ruta ni
  vehículo nominal. `end_simulation_actor` conserva la primera bajada registrada.
- `record_observation`, `record_vehicle` y `record_rejection` admiten un argumento
  opcional `source`. Se conservan los tres argumentos posicionales anteriores.
  Las mediciones sintéticas solo se guardan para un run en ejecución, y cada
  observación debe coincidir con el principal/ruta/intervalo de su abordaje. Los
  rechazos de un run conocido pueden guardarse después de revocarlo.
- `flush()` informa si confirmó correctamente. La política de lotes del flujo
  habitual se conserva; las altas y transiciones de runs se confirman de inmediato.

Guardar el vehículo nominal del escenario no obliga al agrupador a producir ese
ID. La referencia de actores permite analizar posteriormente fusiones/divisiones.
No se reduce el quorum ni se usa esa referencia como atajo de agregación.

## Fallos e integridad

Sin base, tras un error de escritura/commit o sin el margen mínimo de disco, el
camino sintético obtiene `SimulationPersistenceUnavailable`. La señal queda
enclavada en la instancia y `simulation_storage_status()` expone el motivo y los
runs afectados. La disponibilidad de disco se comprueba como máximo una vez por
segundo en ese camino; errores reales de SQLite se detectan en cada escritura y
confirmación. El umbral por defecto es 16 MiB; no es una reserva ni una cuota.

Las llamadas observadas mantienen la política anterior de registrar el fallo sin
lanzarlo al puente. Los contadores existentes conservan sus cuatro claves. S03/S04
deberán consumir la señal para pausar/revocar solo simulación y S09 exponerla en
salud/métricas. S02 todavía no implementa esa parada de extremo a extremo.

Un fallo puede impedir también escribir la marca de fallo en la propia base. Por
ello la señal en memoria no se anuncia como auditoría durable de una avería de
disco: se conserva en logs y se expone al controlador. No se puede completar un
run desde esta instancia tras un fallo ni completar uno interrumpido reabriendo
el archivo. S04 deberá cerrar los runs interrumpidos y crear una generación nueva;
una recuperación no convierte un histórico incompleto en una prueba exitosa.

## Exportación y retención

`iter_export_rows` y `export_jsonl` conservan todas las columnas, incluida
procedencia y ejecución, y filtran opcionalmente por `DataOrigin`/UUID del run.
La lectura se hace por lotes de 256 filas. Primero deben poder confirmarse los
pendientes. La exportación de una tabla no es un snapshot transaccional conjunto
de todas las tablas; para análisis consistente usar un backup o el procedimiento
de lectura coordinado que prepare S09. Los errores de escritura del destino de
exportación se propagan al operador.

La retención existente conserva su configuración y su política anterior para
datos no sintéticos, incluidos legados. El default sigue siendo cero: no borrar.
Los sintéticos quedan fuera de esa purga general. Solo una llamada explícita a
`purge_simulation_detail(run_id, before)` retira detalle de un run terminado y
mantiene observados, legados, otros runs y el resumen del run. Se registra el corte
en `detail_purged_before`; no se elimina una sesión de actor aún abierta.
No se aplican automáticamente las propuestas de retención 7/30 días de Astra.

## Despliegue y reversión preparados

1. Antes de intervenir en un despliegue: obtener autorización para ese entorno,
   detener productores y escritor/es de la base y revisar la copia/restauración.
2. Conservar el archivo anterior y el snapshot SQLite consistente. No copiar solo
   el `.sqlite` mientras haya escrituras en WAL ni sobrescribir una base activa.
3. Arrancar la versión nueva con simulación deshabilitada. Revisar registro de
   migración, `user_version`, conteos/valores por tabla, `quick_check` y backup.
4. Para restaurar, crear otro archivo con la API de backup de SQLite desde la
   copia elegida y verificar integridad/conteos antes de cambiar la ruta del
   servicio. Mantener el archivo migrado para preservar cambios posteriores.
5. No ejecutar un downgrade que elimine columnas/tablas ni arrancar un backend
   antiguo con productores sintéticos activos. El rollback operativo posterior
   necesita el control persistente de S04 y la revocación de identidades prevista.

La apertura de una copia y sus valores originales se cubre con pruebas temporales.
La restauración del despliegue real, las cuotas y el espacio de ese host siguen
pendientes; no se dan por comprobados por compilar ni por probar una base pequeña.
