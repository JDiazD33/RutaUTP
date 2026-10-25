# Recepción iOS — S07

Implementada sin activar productores, instalar en el iPhone ni abrir conexiones
durante esta entrega. La presentación/limpieza de selección, detalle y ETA queda
en S08; el backend continúa apagado para el ensayo conectado.

## Datos y compatibilidad

`VehiclePosition` incorpora `VehicleDataOrigin` (`observed`, `simulated`,
`legacy_unknown`, `unknown`), run y revisión. `VehicleTrackingSource` describe
el transporte: MQTT sigue siendo `.real`, incluso para una posición sintética.
Los modelos locales sin procedencia explícita empiezan como `unknown`; un objeto
Codable anterior se lee como `legacy_unknown`, nunca como observado por defecto.

El lector de red exige v2 completo o exactamente las ocho claves del legado.
Versiones desconocidas, v2 incompleto, tipos/rangos/origen inconsistentes, namespace
reservado incorrecto, tópico distinto del vehicleId, posición retained o payload
mayor de 4096 bytes se rechazan. En v2 observado run/revisión deben ser null;
en sintético son obligatorios y el ID debe pertenecer a `sim:{run}:…`. El JSON de
red usa su decoder específico; no se descodifica directamente el Codable interno.
Se conserva el saneamiento/edad de posiciones: 45 s y tolerancia futura de 10 s.

El proveedor es estricto por defecto. La factoría activa explícitamente
`.whileSimulationDisabled` para mantener la transición del backend v1 actual,
con productores apagados. Ese modo acepta legado marcado desconocido antes del
primer enable y cuando el control válido declara disable; enable purga el legado.
Mientras el último estado conocido esté habilitado, un lease vencido, desconexión
o background no rehabilitan el legado. Después de coordinar salida v2 y S08 debe
retirarse esa compatibilidad de la factoría. No hay interruptor público.

## Control y revocación

El proveedor se suscribe a control y posiciones con QoS 1. Antes de aceptar
control exige CONNACK y SUBACK QoS 1 del tópico de estado. Sin estado válido no
acepta posiciones sintéticas; las que llegan antes del control se descartan,
sin buffer para mostrarlas después. Los observados v2 continúan independientemente
de la disponibilidad del control o del checkpoint.

Control v1: ocho campos exactos, números finitos, tipos estrictos, UUID, zona Lima,
revisión hasta `2^53-1`, lease máximo 15 s y nunca posterior al fin de servicio.
Una emisión a más de 10 s en el futuro no se acepta; un estado futuro tolerado
todavía no permite mostrar datos hasta alcanzar issuedAt. La posición necesita
run y revisión exactamente iguales. El plazo también está acotado por uptime;
un duplicado no renueva el plazo monotónico.

Una revisión anterior o heartbeat anterior no reemplazan al estado nuevo. La misma
revisión no puede cambiar run/política ni contradecir un heartbeat de igual fecha.
Disable con revisión válida retira sintéticos incluso si el tombstone/servicio
son antiguos. Un run revocado no puede reutilizarse con una revisión posterior.
Los errores de formato, caducidad, desconexión, fallo de suscripción y background
invalidan el permiso y purgan los sintéticos del diccionario y snapshot, conservando
observados recientes. Al volver a foreground o reconectar se espera otro control
recibido; no se restaura la autorización desde memoria/disco.

Hay un temporizador independiente de caducidad de control/fin de servicio, en
RunLoop.common, además del barrido de 10 s para posiciones. No depende de recibir
otra baliza ni del barrido 45+10 s. Se vuelve a comprobar el reloj antes de procesar
mensajes. Un salto/retroceso relevante retira permiso y exige emisión posterior;
un disable seguro sí se aplica durante ese salto. iOS suspendido no ejecuta timers:
se revalida al volver a primer plano. Los objetivos ≤5/20 s siguen pendientes de
medición con app y red reales.

Las callbacks MQTT se procesan sin Tasks intermedias en delegateQueue.main, usando
MainActor, identidad del cliente y token del start. Se conserva el orden de
control/posición/desconexión y se ignoran clientes de un start anterior. El timer
tiene su propio token para que una fecha vieja no borre un permiso nuevo. Stop
invalida callbacks/timers/observadores, vacía snapshot y finaliza el stream; el
buffer sigue siendo newest(1).

## Checkpoint

Se guarda evidencia de última revisión/estado y UUID revocados en Application
Support, `RutaUTP/TrackingControl/{SHA256(endpoint)}.json`; el endpoint incluye
host/puerto/TLS, sin contraseña ni cuenta. Escritura atómica, directorio 0700 y
archivo 0600. Solo se escribe al cambiar el control; nunca se guarda un permiso
que se restaure como activo. La lectura está limitada a 32 KiB.
Si dos proveedores comparten el endpoint, la escritura une las revocaciones y
rechaza retroceder la revisión que ya guardó el otro. Conserva el heartbeat más
reciente; no permite que una conexión retrasada sobrescriba un disable conocido.

Estado corrupto o fallo de escritura cierran sintéticos y compatibilidad; los
observados v2 siguen disponibles. Las revocaciones se conservan al crear otro
proveedor o reiniciar. Se acotan a 256 UUID: agotar esa memoria falla cerrado,
sin borrar tombstones para aceptar un run viejo. Operación/retención y reparación
controlada se revisarán en S09 antes de una operación sostenida. Restaurar todo
el contenedor a una copia antigua no se detecta con esos mismos archivos: no se
presenta este checkpoint como contador externo ni protección contra un operador
que lo borre/restaure. La revisión del backend y el control retained siguen siendo
necesarios.

## Validación y límite de alcance

`SimulationControlReceptionTests.swift` puede compilarse/ejecutarse como núcleo
macOS con Foundation/CoreLocation/CryptoKit, sin UIKit, MQTT o datos del usuario.
El paquete temporal utiliza copias comprobables de las fuentes de la app y no
depende de paquetes externos. Sus resultados no prueban la ejecución de UIKit.

`MQTTSimulationReceptionTests.swift` prepara diez casos iOS con conexión sustituida:
orden de mensajes, disable selectivo, callbacks antiguos, reconexión, control
malformado, fallo de guardado, foreground, compatibilidad y caducidad. Se compilan
con el target de pruebas; ejecutarlos y verificar timers reales requiere una
autorización/ensayo posterior. No se modificaron broker, cuentas, base activa,
manifiesto, backend Python ni límite de ocho marcadores.
