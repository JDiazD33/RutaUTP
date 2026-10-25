# Entrada aislada de observaciones — S03

Implementación preparada y deshabilitada por defecto. No se han creado cuentas,
conectado brokers ni cambiado bases o configuraciones del despliegue.

## Configuración y compatibilidad

| Variable nueva | Por defecto | Efecto |
| --- | --- | --- |
| `BACKEND_VEHICLE_POSITION_SCHEMA_VERSION` | `1` | `1` conserva las ocho claves del lector actual. `2` añade procedencia según el esquema S01. |
| `BACKEND_SIMULATION_INGRESS_ENABLED` | `0` | Permite suscribir la rama sintética; exige salida v2 y quorum mínimo de dos principales. No autoriza un run por sí sola. |

No activar estas opciones en un despliegue hasta instalar S07/S08, verificar ACL,
cuentas, migración y restauración de SQLite. La app actual ignora claves nuevas y
trata el transporte MQTT como `.real`; todavía no interpreta el origen v2.

S04 conecta el controlador cuando se configuran la bandera y una ruta privada
`BACKEND_SIMULATION_CONTROL_PATH`. Sin controlador/proveedor la entrada sigue
cerrada. La CLI y el heartbeat retained están preparados en [CONTROL.md](CONTROL.md);
no hay generador ni control activado en este despliegue.

## De MQTT al contexto interno

`parse_observation_topic` admite exclusivamente las dos formas:

- Habitual: `rutautp/observaciones/{principal}/{sessionId}/posicion`.
- Sintética: `rutautp/simulacion/{runId}/observaciones/{principal}/{sessionId}/posicion`.

La segunda requiere UUID canónicos de run/sesión y principal `sim-NNN`. La familia
`sim-` está reservada y se rechaza en la rama habitual, aunque el principal no
figure en el perfil activo. Una cuenta de teléfono no puede usar la rama sintética.
También se rechazan observaciones retained y sesiones inconsistentes con el JSON.

La identidad autenticada depende de la ACL del broker: paho recibe el tópico,
no las credenciales del emisor. El parser por sí solo no autentica al publicador.
Las pruebas offline no acreditan esa frontera de red.

El backend construye `SourceContext` a partir de la rama y una autorización interna
`SimulationAdmission`. Campos extra como `dataOrigin`, `runId` o `vehicleId` en el
JSON del pasajero no cambian la procedencia ni la identidad del vehículo.

La autorización contiene run, revisión, whitelist inmutable y ventana temporal
de hasta 15 segundos. Solo se conserva un run simultáneo. Se rechazan revisiones
regresivas y el mismo número asociado a otro run o whitelist. El proveedor S04
comprueba estado durable, horario de Lima, manifiesto/feed, reloj y lease con PUBACK.
Las ACL efectivas deben verificarse antes del despliegue; una autorización en
memoria no sustituye esas comprobaciones. Ningún
mensaje de pasajero puede crear o renovar este permiso.

SQLite debe estar disponible y el run debe constar en `running`, con histórico
completo. La sesión debe tener un registro de abordaje del mismo principal/ruta;
la fecha observada debe estar dentro de ese abordaje. El ID nominal del escenario
solo pertenece a la referencia: no fuerza el ID ni el resultado del agrupador.

## Aislamiento y límites

Hay una instancia de agrupación/validación para observados y otra para el único
run autorizado. Cada una mantiene sus sesiones, continuidad, deduplicación,
corroboración y cadencia. Al cambiar run/whitelist, caducar el permiso o fallar el
almacén, se retira la partición sintética. La siguiente instancia usa un espacio
de nombres nuevo y no hereda quorum ni identificadores de la anterior.

Ambas comparten exactamente los mismos contadores globales y por principal.
Cambiar de run o sesión no renueva el cupo de una cuenta. Se mantienen los límites
existentes: 20 mensajes/minuto por principal y 1800/minuto agregados, salvo
configuración explícita. No se ha medido capacidad ni consumo con actores.

Dos principales sintéticos distintos pueden corroborar entre sí. Un sintético y
un observado, o actores de runs distintos, nunca corroboran una misma estimación.
No se reduce el quorum mínimo de dos para habilitar la rama nueva.

## Publicación y fallos

La salida v2 observada tiene `dataOrigin=observed`, run/revisión nulos. La sintética
tiene `dataOrigin=simulated`, el UUID del run y la revisión vigente; su ID empieza
por `sim:{runId}:`. Conserva el timestamp de la observación, sin rejuvenecerlo al
publicar. La salida v1 solo se permite mientras la rama sintética está apagada.

Antes de entregar una posición sintética al publicador se guardan observaciones
y estimación, y se confirma SQLite. Después se vuelve a consultar la autorización.
Si falla escritura/commit o ya no hay permiso, no se entrega la posición. La fila
`vehicle_positions` sintética es por ello un **intento durable de entrega**, no
prueba de recepción MQTT: puede quedar guardada si el transporte rechaza la
publicación o vence el permiso durante el commit. No equivale a un PUBACK ni a un
marcador mostrado. S09 distinguirá estas métricas en el reporte operativo.

Los fallos del histórico sintético cierran esa rama; los observados conservan su
política previa de continuidad ante fallos del almacén. Rechazos con rama/origen
confiable se guardan con ese contexto; un run no autorizado o una entrada que no
puede clasificarse se registra como `unknown`, sin inventar una FK a un run.

`tick` elimina estado sintético caduco y S04 prepara revocaciones retained. La
retirada visible con disable/lease y la protección ante mensajes QoS pendientes
requieren instalar el lector S07. No se afirma ese comportamiento completo
con esta entrega. Ocupación sigue consultando el agrupador observado; los actores
no tienen permiso para reportar ocupación, cambios ni avisos.

El latido/resumen suma vehículos de ambas particiones y añade `observedVehicles`
y `simulationVehicles`. `routes` conserva el contador diagnóstico de rutas vistas,
sumado por partición; una ruta presente en ambos orígenes cuenta dos veces. No
equivale a micros publicados ni a marcadores visibles. El reporte por run y la
auditoría operativa completa siguen en S09.

## ACL y despliegue posterior

`mqtt/config/acl.example` conserva los patrones de instalaciones y añade:

- Lectura del control para consumidores y actores.
- Lectura de la rama sintética y escritura del control para `backend`.
- Treinta secciones `sim-001`…`sim-030`: solo escribir su observación sintética,
  leer estado, y denegaciones explícitas sobre las ramas habituales/vehículos/
  ocupación/cambios/notificaciones para neutralizar los permisos generales.

No añadir un patrón global de escritura sintética con `%u`: también autorizaría
a teléfonos. Los permisos permiten varios UUID en el segmento run; el backend
aplica el único run activo y su whitelist. Una cuenta ajena al perfil no debe
recibir permisos genéricos de instalación.

La comprobación opcional `mqtt/tools/acl_test.sh` se amplió en el mismo cambio.
Arranca un Mosquitto temporal y prueba ambos sentidos de aislamiento y permisos
de control. **No se ejecuta automáticamente**; su resultado y la autorización real
en EMQX siguen pendientes. EMQX no importa este formato: ver el apéndice de
`backend/deploy/EMQX-PUESTA-EN-MARCHA.md` y aplicar reglas equivalentes según la
versión/configuración real, sin modificar las cuentas existentes para acomodar
actores. No se ha verificado la versión ni la cuota del broker desplegado.

Las pruebas de `test_simulation_ingress.py` pasan por `Bridge.handle_message`,
usan SQLite temporal y capturan publicaciones. No abren sockets, no prueban ACL
efectivas, no arrancan la app y no aportan medidas de CPU ni de carga.
