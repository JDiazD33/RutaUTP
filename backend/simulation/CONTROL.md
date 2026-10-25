# Control administrativo privado — S04

Implementado sin activar el despliegue. La CLI no abre MQTT ni el histórico;
el controlador del backend no arranca actores. Motor, actores, lector de control
y presentación siguen en S05–S08. Conservar la rama sintética apagada hasta que
esas piezas y las ACL/migración estén verificadas.

## Estado y autoridad

El control usa SQLite independiente del histórico S02. Su carpeta es privada del
usuario de servicio (0700); base, referencia de revisión y locks usan 0600. No hay
endpoint HTTP ni credenciales administrativas en el iPhone.

`init` es explícito y crea una intención deshabilitada. Nunca sobrescribe rutas
existentes. El backend no crea ni repara un estado ausente. Cada orden y cambio de
generación incrementa la revisión de forma transaccional, con auditoría. Solo el
backend que posee el lock de control puede gestionar runs. Una segunda instancia
se rechaza y el reemplazo del archivo de lock invalida al controlador anterior.
La exclusión de actores/conexiones del generador se implementará aparte en S06.

La base guarda intención (`enabled`), perfil fijado con su hash/contenido,
generación, propietario del backend, fecha de servicio, cierre y motivo. La
auditoría conserva las revisiones/órdenes sin duplicar el manifiesto completo.
El estado aplicado, el último envío al transporte y el último PUBACK se registran
por separado. El productor sigue en `unknown`: S04 no puede confirmar que esté
detenido o ejecutándose. Tampoco sabe qué iPhones procesaron una revocación.

## CLI local preparada

Desde `backend`, con el intérprete del entorno Python del proyecto. Los ejemplos
son procedimientos para un despliegue posterior; no se han ejecutado contra
datos activos durante esta tarea:

```sh
export BACKEND_SIMULATION_CONTROL_PATH=/var/lib/rutautp/simulation-control/control.sqlite
python -m rutautp_backend.simulation_admin init
python -m rutautp_backend.simulation_admin status
python -m rutautp_backend.simulation_admin enable --profile pasajeros-30
python -m rutautp_backend.simulation_admin disable --reason operador
```

La carpeta padre final debe ser privada y pertenecer al mismo usuario del backend
y operador. La implementación no cambia permisos de una carpeta compartida ni
crea rutas por defecto. Alternativamente pasar `--control-db /ruta/privada/control.sqlite`
**antes** del subcomando. `--gtfs-dir` permite seleccionar el feed antes de `enable`.

`enable` verifica el perfil preparado de 30, las versiones relevantes de contratos,
quorum/whitelist y los cinco hashes del GTFS; después guarda la intención armada.
Fuera de horario queda esperando. No provisiona usuarios MQTT ni ejecuta un
generador. `disable` revoca persistentemente aunque falle el histórico o el
productor siga enviando. Reiniciar el backend o cambiar de día no anula un disable.

`status` informa JSON y distingue:

| Campo | Significado |
| --- | --- |
| `requestedEnabled`, `controlRevision` | Intención/revisión actualmente guardadas. No prueban ejecución. |
| `backend.appliedRevision`, `seenAt`, `fresh` | Última revisión aplicada y latido del controlador; fresco hasta 15 s, no un ACK de clientes. |
| `mqtt.lastEnqueuedRevision/At` | El cliente MQTT aceptó encolar el estado. |
| `mqtt.lastAckedRevision/At` | Se recibió PUBACK de ese estado en el backend. No equivale a recepción por todas las apps. |
| `producer.status` | `unknown` hasta integrar S06. |
| `clientsApplied` | `unknown`; no se inventa confirmación de retirada en teléfonos. |

Las revisiones de envío/acuse pueden ser anteriores a la orden actual. Compararlas
con `controlRevision` y revisar el latido. No interpretar una marca antigua como
confirmación del último disable. Si la base no puede leerse, la CLI termina con
salida 2 y `controlAvailable=false`, sin sustituirla por otra habilitada.

## Conexión con el backend y MQTT

La plantilla conserva:

```text
BACKEND_SIMULATION_INGRESS_ENABLED=0
BACKEND_VEHICLE_POSITION_SCHEMA_VERSION=1
BACKEND_SIMULATION_CONTROL_PATH=
```

Solo cuando se configure posteriormente entrada habilitada, salida v2 y ruta de
control inicializada, `Bridge` construye el controlador y conecta su proveedor de
admisión. Si falta o falla, los observados continúan y los sintéticos no se aceptan.
`--dry-run` desconecta ese controlador y no publica ni arma generaciones.

El backend crea un UUID de run nuevo al aplicar un enable, reiniciar con intención
armada o comenzar una nueva fecha de servicio. No reutiliza el run interrumpido.
Antes de publicar control habilitado debe confirmar referencia/inicio en el
histórico. Las dos bases no tienen una transacción distribuida: una interrupción
entre ambas deja un run sin autorización, que se cierra/reemplaza al reiniciar.

El backend emite `rutautp/simulacion/estado` con **QoS 1, retained=true**. Es la única
excepción nueva de retención; observaciones y posiciones siguen sin retener.
`publish()` no demuestra un acuse del broker: el controlador espera su callback
PUBACK antes de conceder el permiso S03. Comprueba además el estado durable antes
de cada admisión y antes de cada publicación de posición sintética.

Con red sana intenta renovar cada 5 s una autorización de 15 s, sin superar el
cierre ni el presupuesto temporal del run. Solo hay una renovación pendiente por
revisión; una revisión nueva permite encolar inmediatamente su revocación. El
publicador de control no encola estando desconectado. Tras reconectar debe obtener
un acuse nuevo; un PUBACK de otra revisión/run no lo revive.

Si falta el primer acuse durante 15 s o caduca la última autorización confirmada,
se desarma persistentemente con motivo y hace falta un enable explícito. Esto es
deliberado en la primera entrega; no se reinicia una simulación a ciegas tras una
interrupción larga. Los clientes deberán validar timestamps/revisión en S07 ante
retransmisiones QoS tardías. No se promete retirar mensajes ya en vuelo.

## Horario, reloj y límites iniciales

- Ventana del manifiesto: `[07:00, 22:30)` en `America/Lima`, independiente de la
  zona del servidor. El horario procede del perfil fijado, no del teléfono.
- Para cerrar a las 22:00 se revisa/versiona el manifiesto y se vuelve a habilitar
  ese perfil; no se modifica un booleano ni una tabla en uso manualmente.
- El permiso se corta en el límite exacto del servicio. Al salir de horario queda
  intención armada para otro día si no hubo disable/fallo/presupuesto agotado.
- El perfil inicial limita cada run a **900 s**. Al agotarlos se desarma y no crea
  otro automáticamente. No es todavía una operación de micros durante todo el
  día; presupuestos diarios, actores y supervisor se completan en S06/S09.
- Reloj civil para horario y timestamps; monotónico para cadencia y detección de
  interrupción. Divergencia mayor de 2 s o más de 15 s sin ciclo provoca pausa
  persistente. No se renuevan timestamps viejos para ocultar un salto o suspensión.
- Se verifican hashes al cargar el perfil y se vigilan inode/tamaño/mtime/ctime
  después, sin releer shapes por cada baliza. Cambiar perfil/feed obliga a otro
  enable y a verificar de nuevo. La zona IANA se consulta solo al usar el control;
  su ausencia no bloquea el circuito observado con simulación apagada.

`disable` conserva las tablas y retira la partición sintética en memoria al volver
a consultar la autoridad. El histórico queda con motivo de cierre; si el disco del
histórico falla puede quedar pendiente ese registro, pero la revocación permanece
en la base independiente. Un cierre normal del backend revoca su generación sin
borrar la intención armada; el próximo proceso crea otra. El estado de salida al
cerrar es un intento de envío: su acuse depende del transporte.

## Restauración y revisión creciente

`control.sqlite.revision` conserva UUID de base y última revisión fuera de SQLite.
La igualdad es obligatoria: restaurar solo una base vieja se detecta, y una caída
entre el commit de la base y el guardado de la referencia también queda cerrada.
No se resuelve subiendo automáticamente una referencia para aceptar un enable.

Tras revisar una discrepancia de revisiones con base/auditoría legibles y la misma
identidad, el operador puede ejecutar:

```sh
python -m rutautp_backend.simulation_admin recover-disabled --reason restauracion_revisada
```

La recuperación crea una revisión superior a ambas y **siempre deshabilitada**.
Después hay que reiniciar el controlador fallido; no se reactiva en memoria.
Una referencia ausente/corrupta o una base ilegible no se reparan con ese comando:
preservar evidencia y restaurar bajo revisión una copia coherente deshabilitada.

Conservar la referencia de revisión más reciente al restaurar la base; no copiar
encima todo el directorio antiguo, incluidos locks y referencia. Restaurar ambos a
un punto anterior con el backend detenido no puede detectarse solo con esos mismos
archivos: necesita una referencia independiente más reciente o revisión del operador.
El lock del backend se mantiene fuera del contenido SQLite y no debe reemplazarse
durante ejecución. Este mecanismo detecta restauraciones accidentales de la base;
no es un contador externo resistente a restaurar todo el equipo.

No hay migración del histórico en S04: su esquema S02 sigue en versión 1. El
esquema de control es otro, también versión 1; no son la misma base ni contrato.

## Pendiente antes de una demostración conectada

Pruebas efectivas de ACL/entrega en el broker elegido, motor S05, actores S06,
lector S07 y presentación S08. La meta de retirada visible ≤5 s con red sana y
caducidad ≤20 s sigue pendiente de medición. Tampoco se ha medido CPU con 30
actores: las pruebas de esta tarea usan reloj y mensajes capturados.
