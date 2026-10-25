# Motor de recorridos y pasajeros — S05

Preparado para **30 pasajeros y 10 micros nominales**, sin productor MQTT ni
ejecución automática. Importar el paquete no inicia procesos, temporizadores ni
conexiones y no abre bases. El motor aún no está conectado al arranque del backend
ni a la app. Mantener los productores apagados hasta S07/S08 y ACL verificadas.

## Geometría exacta y paraderos

`load_trip_geometries` adapta el perfil fijado por S04. Comprueba firmas de archivos
antes/después, ruta/trip/shape/línea y elección lexicográfica del trip. La geometría
debe coincidir con la que usa el validador del backend; no elige otra variante para
hacer pasar una lectura.

Las longitudes acumuladas se calculan una vez en metros. Se omiten vértices
consecutivos de longitud cero; un shape completamente degenerado se rechaza.
`RoutePath.at` interpola por distancia con búsqueda binaria y calcula rumbo en el
sentido del segmento. Acota el final del recorrido; no vuelve al inicio ni avanza
un vértice por tick.

Solo se usan `stop_times` del trip elegido y sus coordenadas de `stops`. La
secuencia determina el orden; los horarios GTFS de llegada/salida no se presentan
como tiempos reales de circulación. La velocidad y las pausas son sintéticas.

Se omiten y registran paraderos con secuencia inválida/duplicada, coordenadas
ausentes/inválidas, distancia mayor de 50 m, orden incompatible o proyección
ambigua. Una proyección casi igual de próxima a partes separadas del recorrido
no se asigna arbitrariamente: se consideran candidatas dentro de 0.75 m del mejor
ajuste y ambiguas si sus distancias recorridas difieren en más de 25 m después
de aplicar el orden. Son tolerancias de esta implementación, no una norma GTFS.
No se añaden todos los paraderos de la ciudad ni paradas inventadas de respaldo.

## Un movimiento físico por micro

`VehicleJourney` calcula fases analíticas de aceleración, crucero, frenado y
detención entre los paraderos aceptados que quedan por delante. La posición se
evalúa por tiempo monotónico transcurrido. Consultar más o menos veces no cambia
la trayectoria ni consume pasos de un generador aleatorio global.

El perfil conserva sus parámetros:

| Parámetro | Valor inicial |
| --- | --- |
| Crucero objetivo | 5–12 m/s, elegido por viaje con semilla. |
| Aceleración / frenado | 1 / 1.5 m/s². |
| Detención en parada | 15–40 s. |
| Pausa de terminal | 60–120 s. |
| Precisión declarada | 5–15 m por actor. |
| Ruido de posición | Hasta 3 m, interpolado suavemente entre objetivos cada 5 s. |

En tramos cortos el micro frena antes de alcanzar el crucero objetivo. No se
sobrescribe la posición con una parada lejana ni se mantiene velocidad positiva
durante la detención. La velocidad observada es la del movimiento compartido;
en reposo se emiten 0 m/s, rumbo -1 y actividad `stationary`.

El feed contiene tramos superpuestos en sentidos opuestos. Si el ajuste canónico
del GTFS no puede compatibilizar el rumbo físico con esa lectura, el pasajero
reporta rumbo desconocido (`-1`, ya permitido por v1) y guarda
`heading_unknown_reason` en la referencia. No se publica un rumbo contrario para
forzar aceptación. La verdad física conserva el rumbo del segmento recorrido y
los umbrales del backend no cambian. Un índice espacial local mantiene el orden
original del shape y evita escanearlo entero por pasajero. Se verificó esta
ambigüedad mediante la prueba de integración del generador con el validador.

`initialProgress` se interpreta como fracción de **distancia acumulada**, no del
número de vértices. La semilla controla crucero, detenciones, precisión y ruido;
se fija en el manifiesto. Guardar también versión del motor/Python, manifiesto y
hashes para reconstruir una ejecución. La red y su latencia no serán deterministas.

## Pasajeros y sesiones

Cada `PassengerActor` representa una identidad sintética propuesta del perfil.
Comparte posición física, velocidad y recorrido con su micro, y añade un ruido
GPS propio, acotado y persistente. La precisión declarada nunca es menor que el
ruido máximo configurado. No se cuentan contribuyentes como ocupación real.

El inicio crea 30 sesiones de abordaje canónicas. En una parada puede bajar una
cuenta durante dos segundos y volver a abordar con una sesión nueva; otras dos
permanecen a bordo. Los cambios se aplican por eventos ordenados, aunque un frame
abarque varias transiciones. No se emiten lecturas de un actor fuera del micro.

Los UUID de sesión incorporan run, instancia del motor, viaje, principal y número
de abordaje. Una instancia nueva obtiene otro espacio UUID de forma predeterminada.
La inyección de un espacio fijo sirve para pruebas/reconstrucción offline, no para
reanudar sesiones de un run revocado. No hace falta cambiar la semilla física para
crear sesiones nuevas.

Al llegar al final se cierran las sesiones y empieza la pausa de terminal. No hay
retorno automático ni inversión del shape. `continue_trip` requiere elegir
explícitamente otro trip del catálogo verificado, completar la pausa y que su
primer punto conecte a ≤1 m con el final anterior. Si no existe esa conexión, se
rechaza la continuación. La geometría siguiente debe provenir del GTFS, con sus
propios metadatos, y se crean viaje/sesiones nuevos. Al compartir ruta con otra
unidad activa se exige separación inicial por distancia recorrida y física mayor
de 300 m. El perfil base sigue usando diez rutas diferentes.

## Reloj, parada y autoridad

`RealtimeClock` lee UNIX y monotónico del sistema a 1×. `ClockSample` permite
inyectar ambos en pruebas. El motor no convierte un reloj acelerado en timestamps
para la red. Una lectura usa el UNIX actual del frame.

Un retroceso civil/monotónico, una divergencia civil frente al monotónico mayor de
2 s o un intervalo monotónico mayor de 15 s pausa el motor, cierra las sesiones y
descarta eventos pendientes. No reanuda ni reproduce observaciones atrasadas.
También corta fuera del horario del perfil o al agotar los 900 s del run. Los
eventos de referencia guardan el instante monotónico del modelo y la fecha de
procesamiento del frame; no se convierten en publicaciones de posiciones antiguas.

S05 produce un modelo y lecturas candidatas; **no concede autorización de red**.
S06 debe consultar el control S04 vigente del mismo run/revisión, detenerse al
revocarlo, aplicar cadencia/jitter/colas y presupuestos, y registrar abordajes/cierres
con S02 antes de enviar lecturas. La autorización del backend S03 se conserva.

## API y referencia para integrar S06

| API | Responsabilidad |
| --- | --- |
| `ScenarioEngine.from_profile(profile, gtfs_dir, run_id, ...)` | Construir el modelo verificando el catálogo GTFS; usar esta entrada en la integración real. |
| `advance()` / `advance(ClockSample)` | Crear un frame actual; no abrir un bucle ni transmitir. |
| `ScenarioFrame.vehicles` | Referencia física por micro nominal, viaje/trip/shape y contribuyentes. |
| `ScenarioFrame.observations` | Lecturas candidatas de actores a bordo, con ruido/precisión registrados aparte. |
| `ActorObservation.payload()` | Las 11 claves canónicas v1; sin ID nominal, run u origen declarados en el cuerpo. |
| `ScenarioFrame.events` | Abordajes y cierres, con principal, sesión, run contextual y motivo. |
| `ActorEvent.boarding_record(run_id)` | Referencia tipada compatible con el registro de actores S02; no escribe en SQLite. |
| `stop(sample, reason)` | Cerrar sesiones y vaciar pendientes del modelo. |
| `write_reference(stream, frame, include_header=...)` | JSONL a un stream proporcionado por el llamador; no abre rutas por defecto. |

La referencia separa verdad física, lecturas ruidosas y estimaciones futuras del
backend. La cabecera guarda semilla, versión/hash del perfil, hashes GTFS, espacio
de sesiones y diagnósticos de paraderos. Los frames conservan origen sintético y
run; estos metadatos no se agregan al payload v1 del pasajero.

El constructor directo permite ensamblar geometrías en pruebas aisladas; S06 debe
usar `from_profile` para pasar por la verificación del catálogo. No se escribe el
histórico ni se exporta automáticamente un archivo en S05. La gestión durable del
stream/reporte y su retención siguen en S06/S09.

Treinta candidatos por frame no significan treinta publicaciones por segundo.
La cadencia de red mínima de cinco segundos, fases, jitter y límites se aplican en
S06. Diez micros nominales tampoco garantizan diez estimaciones del agrupador ni
diez marcadores: sus resultados deben compararse con esta referencia.

## Validación y límites

Las pruebas preparadas cubren geometría irregular/repetida, proyecciones ambiguas,
trip exacto, aceleración y frenado, paradas, terminal sin teletransporte, ruido,
sesiones, quorum base, reloj, horario, duración y contrato. La prueba contra el
validador actual no modifica umbrales para acomodar al generador.

No se han conectado actores, probado ACL reales ni instalado el lector iOS.
El rendimiento con 30 actores y las metas de apagado visible se medirán con el
circuito completo en S10; no se deducen de la compilación o de pruebas unitarias.
