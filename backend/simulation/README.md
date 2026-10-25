# Contratos de simulación de pasajeros — S01

Estado: **S01–S09 preparados: contratos, persistencia, entrada, control, motor, actores, iOS y operación**.
S10 incorpora perfiles de ensayo, medición y validación conectada. Véanse
[PERSISTENCE.md](PERSISTENCE.md), [INGRESS.md](INGRESS.md), [CONTROL.md](CONTROL.md)
y [MOTOR.md](MOTOR.md), [ACTORES.md](ACTORES.md), [RECEPCION-IOS.md](RECEPCION-IOS.md)
y [PRESENTACION-IOS.md](PRESENTACION-IOS.md), [OPERACION.md](OPERACION.md),
[VALIDACION.md](VALIDACION.md). Los resultados y límites están en el informe S10.
Primera entrega: **30 pasajeros sintéticos / 10 micros nominales**. No hay productores
activos. S04 arma el control; solo la CLI explícita de S06 podrá arrancar actores
cuando estén verificadas las ACL/migración e instaladas S07/S08.

La simulación alimentará el mismo circuito de validación, agrupación y persistencia
que usa la app. El mapa habitual recibirá posiciones del backend. El movimiento y
la presentación deberán resultar naturales, sin etiqueta visible de demo ni
interruptor público, conforme a la aclaración del usuario. La procedencia sintética
se conserva internamente en todos los datos y métricas de la ejecución.

## Archivos y versiones

| Archivo | Contrato |
| --- | --- |
| `schemas/scenario-v1.schema.json` | Manifiesto de un escenario conectado. |
| `schemas/passenger-observation-v1.schema.json` | Emisión canónica del generador con las 11 claves Swift actuales. |
| `schemas/vehicle-position-v2.schema.json` | Salida futura del backend, con procedencia. |
| `schemas/simulation-control-v1.schema.json` | Estado administrativo y autorización temporal. |
| `scenarios/pasajeros-30.json` | Perfil inicial S01 sin cambios: 30 actores, 10 rutas. |
| `scenarios/ensayo-2.json`, `scenarios/ensayo-6.json` | Escalones S10 con whitelist y presupuesto propios: 2/1 y 6/2. |
| `examples/synthetic/*.json` | Ejemplos ficticios de documentación, nunca mensajes listos para publicar. |

Los esquemas usan JSON Schema 2020-12 y referencias internas. No introducen una
dependencia de ejecución ni se descargan esquemas desde la red. La versión de cada
mensaje es independiente: observación **1**, posición **2**, control **1** y escenario
**1**. `scenarioVersion` identifica revisiones del contenido de un perfil; todo
cambio de rutas, semilla, parámetros o presupuestos debe incrementarlo.

Los esquemas fijan claves, tipos y rangos de la **emisión canónica nueva**. No se
instalan en el backend actual ni modifican su tolerancia de entrada. El esquema de
observación limita al generador a UUID y números normalizados; el validador actual
acepta más representaciones, conserva su propio contrato y sigue siendo autoridad
para comprobar GTFS, antigüedad, rumbo, límites, duplicados y continuidad.

Todos los números deben ser finitos y excluir booleanos. No emitir NaN/Infinity,
coordenadas privadas, secretos, cuentas de teléfonos ni contenido de búsquedas.
Los límites cruzados y temporales de las secciones siguientes son obligatorios;
no quedan expresados por completo en JSON Schema.

## Canales MQTT y autoridad

| Uso | Tópico | Escritor | QoS / retained |
| --- | --- | --- | --- |
| Observación habitual existente | `rutautp/observaciones/{principal}/{sessionId}/posicion` | Teléfono autorizado | 1 / false |
| Observación sintética nueva | `rutautp/simulacion/{runId}/observaciones/{principal}/{sessionId}/posicion` | Actor autorizado para ese run | 1 / false |
| Posición de vehículo | `rutautp/vehiculos/{vehicleId}/posicion` | Backend | 1 / false |
| Estado de control nuevo | `rutautp/simulacion/estado` | Backend | 1 / true |

La rama sintética tiene **7 niveles**; la habitual tiene 5. S03 debe adaptar el
parser y la suscripción explícitamente. La cuenta autenticada debe estar vinculada
por ACL al principal del tópico; no basta con confiar en el nombre de la rama.
El backend construye un `SourceContext` interno con origen, run y principal después
de comprobar ACL/registro de identidades, pertenencia al run y control vigente.
Ese contexto no se acepta como una afirmación del JSON del actor.

Cada `sim-001`…`sim-030` del manifiesto es un **nombre propuesto de principal**, no
una cuenta creada ni una credencial. Se necesitarán 30 identidades distintas;
rotar sesiones dentro de una sola cuenta no alcanza el quorum de dos principales.
Los secretos se provisionarán fuera del repositorio. S01 no define host, contraseña,
nuevas variables de entorno ni acceso a una consola existente.

Los actores solo publicarán su observación y leerán el estado permitido. No podrán
publicar posiciones, control, ocupación, cambios de ruta ni notificaciones. Las
cuentas sintéticas no tendrán permiso sobre la rama habitual, y viceversa. Las ACL
actuales contienen patrones generales: S03 deberá verificar el aislamiento efectivo
en el broker elegido antes de habilitar tráfico. No se modifican aquí las cuentas
actuales ni sus permisos.

## Observación v1

Las claves coinciden con `PassengerObservationPayload` y `OBSERVATION_FIELDS`:
`schemaVersion`, `sessionId`, `routeId`, `linea`, `lat`, `lon`, `speed`, `heading`,
`accuracy`, `motionActivity`, `timestamp`.

- `sessionId`: UUID exclusivo de un abordaje; coincide con el tópico. Cambia al
  volver a abordar, cambiar de micro o reiniciar tras una interrupción larga.
- `routeId`: ruta del feed fijado; `linea`: nombre público normalizado igual que
  `gtfs.parse_short_name`. Por ejemplo, `C-01 "B"` aporta `linea = "C-01"`.
- Latitud/longitud en grados, velocidad en m/s, precisión horizontal en metros,
  rumbo en `[0,360)` o `-1` desconocido. Velocidad desconocida: `-1`.
- El generador emite velocidad 0 y puede emitir rumbo -1 al detenerse. Puede usar
  actividad `automotive` en movimiento y `stationary` en parada. No se añade un
  requisito de movimiento al validador actual para conservar un micro detenido.
- `timestamp`: segundos UNIX de la lectura actual. El avance y la cadencia usan
  reloj monotónico; el modo conectado trabaja a **1×**. No se acelera el timestamp.
- No se añaden `vehicleId`, `runId`, `dataOrigin` ni campos privados al payload v1;
  el run y el principal pertenecen al tópico/contexto confiable.

## Posición vehicular v2 y compatibilidad

La salida conserva las ocho claves actuales: `vehicleId`, `routeId`, `linea`,
`lat`, `lon`, `speed`, `heading`, `timestamp`. Añade cuatro claves obligatorias:

| Clave | Observado | Sintético |
| --- | --- | --- |
| `schemaVersion` | 2 | 2 |
| `dataOrigin` | `observed` | `simulated` |
| `simulationRunId` | null | UUID del run autorizado |
| `controlRevision` | null | Entero positivo de la autorización vigente |

El backend deriva `vehicleId`; nunca usa el ID nominal del escenario para forzar
el resultado del agrupador. Para sintéticos reserva el espacio `sim:{runId}:…`,
sin colisiones con observados ni otros runs. El timestamp sigue siendo el de la
observación que produjo la estimación, no una fecha renovada artificialmente al
republicarla. Orígenes/runs distintos no comparten agrupación, continuidad ni
deduplicación. Se conserva el límite global de entrada compartido.

Vocabulario interno para persistencia/recepción: `observed`, `simulated` y
`legacy_unknown`; una entrada no clasificable podrá usar `unknown` en rechazos.
`legacy_unknown` no se publica como una posición nueva v2. Las filas históricas y
los mensajes legados no adquieren procedencia observada por defecto.

S07 deberá distinguir explícitamente v2 del legado de ocho claves sin versión.
El legado solo será admisible durante una compatibilidad de despliegue controlada
con simulación deshabilitada, marcado internamente `legacy_unknown`. No se mezcla
con producción sintética. Una versión desconocida, v2 incompleta o procedencia
inconsistente se descarta. Las claves adicionales no sustituyen estas comprobaciones.

El lector S07 ya valida v2, control y procedencia, y declara transporte MQTT `.real`.
La factoría conserva compatibilidad explícita con v1 mientras la simulación está
deshabilitada; enable purga el legado. La activación exige S07/S08 instaladas y
salida v2 coordinada.
No cambiar `VehicleTrackingSource` a `.simulated` para una posición MQTT: ese enum
selecciona transporte/movimiento local. El origen de los datos será otro atributo.

## Estado de control v1

Claves obligatorias: `schemaVersion`, `enabled`, `runId`, `controlRevision`,
`issuedAt`, `validUntil`, `serviceEndsAt`, `timeZone`. Los tiempos son segundos UNIX
y `timeZone` es `America/Lima`. Solo el backend escribe este estado retained.

- Estado inicial: deshabilitado, `runId = null`, revisión 0. Una revisión 0 no
  autoriza tráfico. Una revisión positiva deshabilitada puede conservar el UUID
  revocado como registro de apagado.
- Una habilitación requiere un run UUID nuevo, revisión positiva creciente y estado
  vigente. Mientras está habilitado: `issuedAt <= validUntil <= serviceEndsAt`; la
  autorización dura como máximo 15 s desde `issuedAt`. Se renueva cada 5 s sin
  retroceder fecha o revisión. No se rehabilita el UUID de un run revocado.
- Fechas finitas, mensaje de como máximo 4.096 bytes y emisión no más de 10 s en
  el futuro. Las revisiones se limitan a enteros de hasta `2^53-1`; el controlador
  deberá fallar deshabilitado si no puede preservar su crecimiento.
- Para **mostrar** una posición sintética: autorización habilitada, vigente, dentro
  del servicio, con run y revisión exactamente iguales a los de la posición.
  Si la posición llega antes del estado, se descarta y se espera la siguiente.
- Estado ausente, corrupto, vencido o fuera de servicio: retirar sintéticos. Las
  posiciones observadas mantienen su flujo actual.
- Una revisión menor se ignora. A igual revisión, un heartbeat no puede retroceder
  `issuedAt`. Una revisión nueva invalida las posiciones de la revisión previa.
  `disable` revoca el run; no basta con parar el generador.
- Un estado deshabilitado con revisión aceptable retira sintéticos incluso si su
  autorización temporal ya venció; nunca habilita datos. Un retained viejo no
  reabre un run ni reemplaza una revisión posterior. El backend emite ese estado
  con `validUntil = issuedAt`; `serviceEndsAt` puede estar en el pasado para permitir
  una orden de apagado fuera del horario de servicio.
- Revalidar al reconectar y volver a primer plano; retirar al alcanzar
  `serviceEndsAt` mediante reloj local, aunque no llegue otro mensaje.

El objetivo por medir es retirada en ≤5 s con app activa y red sana, o ≤20 s por
caducidad si se pierde control. No son garantías para iOS suspendido ni de entrega
de red. Reiniciar o llegar al día siguiente no revierte un disable persistente.
No se añade control administrativo público en la app.

## Perfil inicial y reglas del manifiesto

`pasajeros-30.json` fija semilla **20261021**, 30 principales, 10 micros nominales
y una ruta distinta por micro. Se seleccionaron las primeras diez rutas por
`route_id` lexicográfico con shape y al menos dos filas `stop_times` de su trip
elegido. El trip replica el mínimo lexicográfico de `trip_id` del backend. El
shape resuelve `shape_id`, o `route_id` si falta/no existe la geometría declarada.
No se invierte un shape para fabricar retorno. La ruta resuelta queda explícita.

Los hashes SHA-256 de `routes`, `trips`, `shapes`, `stops` y `stop_times` fijan el
feed; cualquier diferencia debe detener la preparación hasta revisar/versionar
el perfil. S05 debe comprobar coordenadas y geometría útil, secuencias, referencias
de paraderos y su proyección ordenada. Contar filas en S01 no valida el recorrido
dinámico ni acredita que todos los paraderos sean utilizables.

Reglas cruzadas obligatorias para el futuro cargador, además del esquema:

1. IDs nominales y principales únicos en todo el perfil; cantidad de vehículos
   igual a `nominalVehicleCount` y suma de principales igual a `maxConcurrentActors`.
   Cada micro base mantiene al menos dos principales activos.
2. Trip, shape y línea coinciden con el feed y con el selector del backend. El ID
   nominal solo se guarda en la referencia del generador, fuera del algoritmo.
3. En rangos, `min <= max`. Crucero ≤30 m/s, precisión ≤50 m, ruido máximo no mayor
   que la precisión mínima; aceleración, frenado y tiempos de backoff positivos.
4. La fase inicial escalona conexiones/publicaciones. Cada intervalo es al menos
   5 s; el jitter es **positivo**, para no acortar ese mínimo. El backoff crece
   con aleatoriedad entre 1 y 60 s; no se envía el atraso tras reconectar.
5. Fuera de servicio o sin control vigente no se emite/acepta/publica sintético.
   `enabledByDefault = false` nunca se transforma por sí solo en una orden enable.
6. Presupuesto diario ≥ presupuesto por run. Se detiene al agotar cualquiera o
   al alcanzar duración/cierre; no se abre otro run automáticamente para eludirlo.
   El contador diario se conserva por fecha civil de Lima a través de reinicios.
7. En parada, la velocidad es cero; todos los pasajeros comparten la trayectoria
   del vehículo y solo difieren por ruido GPS propio acotado. Al terminar sin un
   retorno GTFS explícito, se finaliza el viaje y se pausa; no se vuelve al inicio.
8. Fallo de persistencia, salto de reloj o suspensión larga: aplicar la política
   definida y registrar el incidente; nunca rejuvenecer muestras antiguas.

El ensayo futuro de este perfil está acotado a **900 s**, hasta **6.000 llamadas
de publicación de observaciones por run y por día**, con una cola y un mensaje
en vuelo por actor. Nominalmente son hasta 5.400 observaciones en 15 minutos,
sin jitter, rampas ni reconexiones. Los contadores incluyen llamadas iniciales y
reintentos de la aplicación; las retransmisiones internas QoS 1 y las entregas a
suscriptores también pueden contar para la cuota del broker, por lo que este
presupuesto no promete un límite de facturación MQTT. No conservar cola caducada.

La ventana **07:00–22:30** es la propuesta inicial del arquitecto, configurable a
22:00 antes de activar. El límite de 15 minutos sigue aplicándose dentro de ella.
La curva horaria diaria, retención 7/30 días y operación sostenida quedan por
concretar con S09 y el ensayo; no están autorizadas ni programadas por este archivo.

Solo existe el perfil 30/10. El esquema admite perfiles posteriores de hasta 100
actores como formato reutilizable; esto no acredita su capacidad ni los activa.
El mapa conserva el límite de ocho marcadores y sus filtros actuales hasta S08.

## Integración y comprobaciones posteriores

Orden: S02 persistencia → S03 entrada/agrupación/ACL → S04 control → S05 geometría
→ S06 actores → S07 recepción iOS → S08 presentación → S09 operación → S10 validación.
Preparar lectores y permisos antes de encender productores. No usar el puente
demo que publica vehículos directamente: no verifica este circuito.

Casos de contrato que deberán cubrirse cuando existan sus implementaciones:

- Claves/tipos de observación iguales a Swift; sin campos de identidad vehicular.
- v2 observado con run/revisión null; v2 sintético con ambos obligatorios.
- Versión desconocida, campos ausentes, números no finitos o tipos incorrectos.
- Una cuenta con varias sesiones no cumple quorum de dos cuentas.
- Observado y sintético coincidentes no se corroboran; dos runs no se fusionan.
- Posición antes del estado, estado vencido, misma revisión antigua y revisión
  revocada; ningún mensaje tardío repone un vehículo retirado.
- `disable`, cierre de horario, reconexión/reapertura y caída del backend.
- Hash de feed distinto, actor duplicado, referencia GTFS incoherente y límites
  de mensajes/duración; fallo al guardar debe pausar la simulación.

S01 no ejecuta esos casos ni añade dependencias de pruebas. Las comprobaciones de
ejecución requieren el escenario preparado y autorización del usuario. La primera
activación futura se preparará con 2 actores/1 micro, después 6/2 y finalmente 30/10;
estos perfiles pequeños todavía no se crean. La app actual sigue funcionando con
sus contratos existentes hasta las tareas de integración.

Los JSON de `examples/synthetic/` usan identidades ficticias, un punto público del
GTFS y timestamps fijos del **21/10/2026 a las 09:00 America/Lima**. Son documentación
de wire format, no un replay, y su posición no representa necesariamente el inicio
del manifiesto. Un backend conectado debe rechazarlos al quedar antiguos.


## Ocupación del escenario (23/10/2026)

Por petición del usuario, el backend puede añadir un guion de ocupación a cada
micro sintético: `empty` (Vacío), `space` (Con espacio), `full` (Lleno).
No se deduce de la cantidad de balizas ni de votos. La política v1 es determinista
por identificador de vehículo y timestamp de la posición, con ciclos de cinco
minutos y mezcla por franja horaria de Lima. Un cambio puede saltar entre estados;
no representa un conteo de pasajeros ni capacidad física medida.

`BACKEND_SIMULATION_OCCUPANCY_ENABLED=1` requiere ingreso sintético habilitado.
Por defecto está apagado. Con el flag, solamente las posiciones sintéticas usan
schemaVersion 3, con las doce claves v2 más `scenarioOccupancy` y
`occupancyScriptVersion=1`, ambas obligatorias y no nulas. El timestamp conserva
la edad de la observación. Origen, run, revisión, quorum y lease siguen vigentes.
Los observados conservan su contrato anterior. Instalar el lector iOS v3 antes de
habilitar esta salida: los lectores v2 rechazan versiones desconocidas.

La app muestra el estado en la tarjeta y el detalle, también por accesibilidad.
El detalle sintético es de lectura; no abre el servicio comunitario ni permite
que los actores publiquen votos. Al caducar o deshabilitar el run se retiran tanto
la posición como su ocupación. No hay un control público nuevo en la app.

El histórico pasa de esquema 1 a 2 mediante migración aditiva, con backup SQLite
consistente de bases existentes y dos columnas nulas para posiciones antiguas.
Cada intento de posición v3 guarda exactamente estado y versión antes de publicar;
una fila no prueba entrega MQTT/iOS. Los informes de esquema 1 siguen siendo de
solo lectura y no disparan migraciones. Se añade el conteo de estados almacenados.
El ensayo aislado admite `--scenario-occupancy`; conserva las cuentas, ACL,
presupuestos y apagado de S10. No se modificó una base activa para desplegar esto.
