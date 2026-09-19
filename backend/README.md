# Backend de RutaUTP — puente `observaciones` → `vehiculos`

Servicio que convierte las observaciones anónimas de los pasajeros a bordo en
**posiciones vehiculares estimadas** que el resto de usuarios ve moverse en el
mapa.

> **Qué significa «estimada», y qué no.** El servicio agrupa observaciones y
> publica la posición resultante. La validación contra el GTFS comprueba que un
> punto sea **plausible** —que caiga sobre el recorrido y que la trayectoria de
> su sesión sea coherente—, pero **no demuestra que exista un vehículo ahí**:
> una posición inventada puede estar exactamente sobre la línea. El
> `vehicleId` lo deriva el servidor para que nadie suplante una unidad, y eso
> evita la suplantación por identificador, no la invención de posiciones.
>
> La consecuencia práctica: **el producto y la documentación no deben prometer
> autenticidad de unidad**, porque el sistema no puede verificarla. Para eso
> haría falta identidad real de la empresa (placa o código de unidad). Las
> credenciales por instalación aíslan abuso, pero no demuestran que el teléfono
> viaje realmente dentro de un bus.

```
App a bordo                  Backend (este servicio)                App de otros
     │                                │                                  │
     │ MQTT publish                   │ valida contra GTFS                │ MQTT subscribe
     ▼                                │ agrupa por unidad                 ▲
rutautp/observaciones/{principal}/{sesión}/posicion
     │                                │ deriva el vehicleId              │
     │                                ▼                                  │
     └──────────► [ Mosquitto ] ──► (consume) ──► (publica) ──► [ Mosquitto ]
                                                          rutautp/vehiculos/{id}/posicion
```

El cliente ya filtra antes de publicar, pero **el servidor no puede confiar en
él**: el broker es un canal compartido y cada instalación autenticada puede
publicar observaciones bajo su propio principal. Este servicio es la frontera
de confianza del contenido.

## Qué resuelve

| Problema | Cómo |
|---|---|
| Un cliente puede mentir | Cada observación se contrasta contra el recorrido real de la ruta que dice usar |
| Un cliente puede suplantar un vehículo | El `vehicleId` **lo deriva el servidor**; se ignora cualquier identificador del mensaje |
| Un cliente puede inundar el canal | La ACL vincula el tópico al usuario autenticado; límite por principal y techo global de emergencia |
| Un cliente intenta publicar bajo otra identidad | La ACL vincula `{principal}` con el usuario MQTT autenticado mediante `%u` |
| Un cliente puede inventar una trayectoria imposible | Continuidad por sesión: un salto que ningún vehículo podría dar se rechaza |
| QoS 1 entrega duplicados | Deduplicación por `(sessionId, timestamp)` |
| Varios pasajeros, un solo bus | Agrupación por ruta, proximidad, ventana temporal, avance y rumbo |
| Dos buses próximos se fusionarían | Vínculo por sesión y rechazo de rumbos opuestos |
| Un bus parado desaparecería | No se exige velocidad mínima ni rumbo conocido (ver más abajo) |

## Requisitos

- Python 3.10 o superior
- Un broker Mosquitto accesible (ver [`../mqtt/README.md`](../mqtt/README.md))
- El feed GTFS del repositorio, en `../gtfs` (se lee desde ahí, no se duplica)

## Instalación

```bash
cd backend

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt        # solo ejecutar
pip install -r requirements-dev.txt    # además, pruebas
```

## Uso

```bash
# Comprueba que el feed se lee y que todas las rutas tienen geometría.
# Devuelve 0 si el feed está sano y 4 si alguna ruta no tiene geometría
# utilizable (sus observaciones se rechazarían todas con UNKNOWN_ROUTE),
# así que sirve como comprobación automática.
python -m rutautp_backend --check

# Se conecta, procesa y registra, pero no publica nada. Útil para observar.
python -m rutautp_backend --dry-run

# ¿Sigue vivo el puente que está en marcha? (para supervisores)
python -m rutautp_backend --health-check

# Puente en marcha.
MQTT_HOST=192.168.1.50 \
MQTT_USERNAME=backend MQTT_PASSWORD=... \
  python -m rutautp_backend
```

## Configuración

Las variables del broker usan **los mismos nombres que el Scheme de Xcode** del
cliente, para poder copiar la configuración de un lado al otro sin traducirla.
Los ajustes propios del servicio llevan el prefijo `BACKEND_`.

### Broker

| Variable | Por defecto | Descripción |
|---|---|---|
| `MQTT_HOST` | `127.0.0.1` | Host o dominio del broker |
| `MQTT_PORT` | `1883`, o `8883` si `MQTT_TLS=1` | Puerto |
| `MQTT_USERNAME` | — | Usuario. Para este servicio debe ser `backend`, no una identidad de la app |
| `MQTT_PASSWORD` | — | Contraseña |
| `MQTT_TLS` | `0` | `1` habilita TLS e implica el puerto 8883 |
| `MQTT_CA_CERT` | — | Ruta a la CA propia (PEM). Obligatoria si el certificado es autofirmado |
| `MQTT_CLIENT_ID` | aleatorio | Identificador del cliente MQTT |
| `GTFS_DIR` | `../gtfs` | Directorio del feed |

### Validación

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_MAX_MESSAGE_BYTES` | `8192` | Tamaño máximo del mensaje entrante. Un mensaje legítimo ronda los 300 bytes |
| `BACKEND_MAX_ACCURACY_M` | `50` | Precisión GPS máxima aceptada |
| `BACKEND_MAX_AGE_S` | `45` | Antigüedad máxima de una observación |
| `BACKEND_MAX_CLOCK_SKEW_S` | `10` | Desfase de reloj tolerado hacia el futuro |
| `BACKEND_MAX_DISTANCE_TO_ROUTE_M` | `50` | Distancia máxima al recorrido |
| `BACKEND_MAX_HEADING_DIFF_DEG` | `60` | Desvío máximo respecto al sentido del recorrido |
| `BACKEND_MAX_SPEED_MS` | `30` | Techo de velocidad (108 km/h) |
| `BACKEND_MAX_MSGS_PER_MINUTE` | `20` | Límite por principal MQTT autenticado. La baliza legítima envía 12 |
| `BACKEND_MAX_MSGS_PER_MINUTE_GLOBAL` | `1800` | Techo de emergencia del servicio entero, aplicado únicamente después de validar la observación. Debe ser ≥ el límite por principal |
| `BACKEND_MAX_DISPLACEMENT_MARGIN_M` | `250` | Margen tolerado al comprobar la continuidad de una sesión, para absorber el ruido del GPS |
| `BACKEND_DEDUPE_WINDOW_S` | `120` | Ventana de deduplicación |

### Agregación

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_MERGE_RADIUS_M` | `300` | Distancia para considerar que dos observaciones son del mismo vehículo |
| `BACKEND_MERGE_WINDOW_S` | `60` | Ventana temporal para fusionar. Debe ser ≤ `BACKEND_VEHICLE_TTL_S` |
| `BACKEND_MERGE_MAX_HEADING_DIFF_DEG` | `90` | Diferencia de rumbo máxima para fusionar. Una misma línea se recorre en los dos sentidos: sin esto, dos unidades que se cruzan se fusionan |
| `BACKEND_VEHICLE_TTL_S` | `60` | Sin observaciones durante este tiempo, el vehículo se retira |
| `BACKEND_PUBLISH_INTERVAL_S` | `5` | Ritmo mínimo de publicación por vehículo |
| `BACKEND_VEHICLE_NAMESPACE` | aleatorio por arranque | Espacio de nombres del `vehicleId`. Fijarlo da identificadores reproducibles; vacío genera uno nuevo en cada arranque, que es lo que evita heredar la identidad visible de un proceso anterior |

### Tópicos

Se pueden cambiar para apuntar a otro espacio de nombres, pero **la ACL del
broker tiene que conceder los mismos**. `mqtt/config/acl.example` ya está
acotada a estos dos.

| Variable | Por defecto |
|---|---|
| `BACKEND_OBSERVATIONS_TOPIC` | `rutautp/observaciones/+/+/posicion` |
| `BACKEND_VEHICLES_TOPIC_PREFIX` | `rutautp/vehiculos` |

### Persistencia

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_DB_PATH` | `backend/data/rutautp.sqlite` | Histórico SQLite. **Vacío desactiva la persistencia** |
| `BACKEND_DB_RETENTION_DAYS` | `0` | Días conservados. `0` significa no borrar nunca |

### Salud

Un supervisor necesita saber si el servicio está vivo, y sobre todo **por qué**
no lo está. El puente escribe un latido en cada ciclo de mantenimiento (una vez
por segundo) y `--health-check` lo interpreta.

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_HEALTH_FILE` | `backend/data/health.json` | Ruta del latido. Vacío desactiva la comprobación |
| `BACKEND_HEALTH_MAX_AGE_S` | `30` | Antigüedad máxima tolerada del latido |

```bash
python -m rutautp_backend --health-check
# salud OK: sano: latido de hace 0.8 s, conectado al broker      -> 0
# salud FALLA: el backend está vivo pero desconectado del broker -> 1
# salud FALLA: no hay latido legible en ...                      -> 1
```

El latido se retira al cerrar el puente, así que un servicio detenido se
delata de inmediato en lugar de parecer vivo hasta que venza el margen.

### Registro

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `BACKEND_LOG_JSON` | `1` | Una línea JSON por evento, apta para volcar a un archivo |

## Contrato

Ambos extremos están copiados de los tipos Swift que ya existen, y hay pruebas
que lo verifican leyendo el código del proyecto de Xcode (ver `tests/test_contract.py`).

**Entrada** — `rutautp/observaciones/{principal}/{sessionId}/posicion`, QoS 1,
sin retención. En producción, `mqtt/config/acl.example` obliga a que
`principal` coincida con el usuario MQTT autenticado.
Corresponde a `PassengerObservationPayload`:

```
schemaVersion, sessionId, routeId, linea, lat, lon, speed, heading,
accuracy, motionActivity, timestamp
```

**Salida** — `rutautp/vehiculos/{vehicleId}/posicion`, QoS 1, sin retención.
Corresponde a `VehiclePositionMessage`:

```
vehicleId, routeId, linea, lat, lon, speed, heading, timestamp
```

`routeId` viaja explícito para que el mapa resuelva la ruta por su
identificador y no por el nombre de línea: dos ramales de la misma línea
comparten `linea`, y cualquier línea fuera del catálogo precargado se quedaba
sin empresa ni color.

**Qué verifica la prueba de contrato, y qué no.** Compara los **nombres de los
campos** y algunos tipos esperados entre el `struct` de Swift y lo que publica
el backend. No ejecuta un intercambio real Swift↔Python: no codifica con el
`JSONEncoder` del teléfono ni decodifica con el del backend. Eso significa que
detecta el error más silencioso —un campo mal nombrado, que el `JSONDecoder`
descartaría sin ruido— pero no sustituye a una prueba entre dos apps reales.

Sobre «sin un solo error»: el consumidor **sí** registra el problema, pero solo
en compilaciones `DEBUG` (`[MQTT] JSON inválido en <tópico>`). En `Release` un
desajuste de contrato no produce ningún diagnóstico visible, y el mapa se
quedaría vacío sin explicación. Por eso la comprobación es automática y no
depende de que alguien mire los registros.

## Decisiones de diseño que conviene conocer

**No se exige velocidad mínima ni actividad vehicular.** El cliente sigue
publicando mientras está a bordo aunque el vehículo esté parado en un semáforo,
y entonces la velocidad es ~0 y el rumbo puede llegar como `-1`. Si el servidor
exigiera "velocidad de vehículo" como hace el detector del teléfono, **haría
desaparecer del mapa a todos los buses parados**. Esa comprobación pertenece a
la detección, no aquí.

**Un rumbo `-1` se omite, no se rechaza.** Es un valor legítimo del contrato,
no una señal de manipulación. Solo se valida el rumbo cuando viene informado.

**La `linea` declarada debe coincidir con la de la ruta.** El mapa de los demás
usa `linea` para el nombre y el color, así que una discrepancia mostraría un
vehículo con la identidad equivocada.

**`timestamp` es el de la observación, no el de publicación.** Si se refrescara
al publicar, un vehículo que dejó de transmitir seguiría pareciendo vivo y nunca
se podaría del mapa.

**Sin retención.** Una posición vehicular es un dato perecedero y el cliente ya
descarta lo que supera 45 s. Un mensaje retenido haría que quien se conecta tarde
viera un vehículo fantasma.

**Un solo hilo.** Se usa `client.loop()` en el hilo principal en vez de
`loop_start()`, así los mensajes y el mantenimiento periódico no comparten estado
entre hilos.

**Los ordinales de vehículo no se reutilizan, ni dentro de un arranque ni entre
arranques.** Si un vehículo expira y aparece otro en la misma ruta, recibe un
identificador nuevo: reutilizarlo haría saltar el marcador en el mapa. Y como
los ordinales se pierden al reiniciar el proceso, el identificador incluye un
**espacio de nombres por arranque** (`17350695-6647-01`). Sin él, un `{ruta}-01`
de un proceso nuevo heredaría la identidad visible del anterior, que puede
seguir dibujada en el mapa de los usuarios hasta que caduque. El espacio de
nombres evita la colisión; **no** afirma continuidad física entre arranques,
porque el sistema no puede verificarla.

## Despliegue

El perfil de despliegue vive en [`../mqtt/compose.prod.yaml`](../mqtt/compose.prod.yaml):
levanta Mosquitto con TLS y ACL en el 8883 y el backend supervisado, con
`restart: unless-stopped` y una comprobación de salud que llama a
`--health-check`. El 1883 no se publica.

```bash
# Requisitos previos (los crea el operador, no viven en el repositorio):
#   mqtt/config/passwords, mqtt/config/acl, mqtt/config/certs/
export MQTT_BACKEND_PASSWORD='...'
docker compose -f mqtt/compose.prod.yaml up -d
```

Fuera de Docker, la unidad equivalente es `deploy/rutautp-backend.service`
(systemd), que usa la misma comprobación de salud mediante un temporizador.

## Verificación

```bash
# Pruebas unitarias: geometría, GTFS, validación, agregación, contrato,
# robustez de entrada, configuración, persistencia, salud, tópicos,
# identidad de vehículo, límites y coherencia entre README y código.
python -m pytest

# Prueba de humo con un broker real: levanta Mosquitto en un puerto de prueba,
# arranca el backend, publica una observación sintética y comprueba que sale la
# posición vehicular. Es lo único que cubre el cableado con paho.
./tools/smoke_test.sh

# Arranque sin broker, corte y restauración: el servicio debe recuperarse solo.
./tools/reconnect_test.sh
```

`smoke_test.sh` y `reconnect_test.sh` **necesitan los ejecutables locales de
Mosquitto** (`mosquitto`, `mosquitto_pub`, `mosquitto_sub`). Levantan su propio
broker en un puerto de prueba y lo borran al terminar: **arrancar el Compose no
los instala ni los sustituye**. En macOS, `brew install mosquitto`.

Resultado de la última ejecución de esta revisión (19 de septiembre de 2026,
Python 3.13, Xcode 27):

| Comprobación | Resultado |
|---|---|
| `python -m pytest` | 262 pruebas, 0 fallos |
| `./tools/smoke_test.sh` | OK — publica la posición vehicular |
| `./tools/reconnect_test.sh` | OK — se recupera de arranque sin broker y de cortes |
| `python -m rutautp_backend --check` | 102 rutas, todas con geometría, 53 616 vértices |
| `../mqtt/tools/acl_test.sh` | OK — 7 permisos verificados contra un broker real |

Los números envejecen: si hace falta una cifra, conviene volver a ejecutar los
comandos en lugar de citar esta tabla.

## Relación con `puente-demo.sh`

[`../mqtt/puente-demo.sh`](../mqtt/puente-demo.sh) fue el puente de
demostración: republica todo lo que entra sin validar nada. Este servicio lo
reemplaza. El script se conserva porque es una prueba de humo de 60 líneas que
no necesita dependencias de Python.

## Estado y siguientes pasos

**Funciona**: validación, agrupación, publicación, caducidad, métricas,
persistencia del histórico y comprobación de salud.

**Siguiente**:

1. **Estimación de ETA.** Con la posición y el `progress` sobre el shape ya
   calculado, se puede estimar el tiempo hasta un paradero. Exponerlo a la app
   requiere una decisión sobre el contrato MQTT, porque hoy
   `VehiclePositionMessage` no tiene ese campo.
2. **Identidad real de unidad** cuando las empresas la faciliten, en lugar del
   ordinal derivado.
3. **Continuidad sesión–vehículo** (D01 del informe de correcciones): hoy la
   agrupación usa ruta, proximidad y ventana temporal, pero no el avance sobre
   el recorrido ni el rumbo. Dos buses próximos de la misma línea siguen siendo
   indistinguibles con esos tres criterios.

### La persistencia, hecha

El histórico vive en SQLite (`persistence.py`) y se escribe con **una
transacción por segundo, no por mensaje**: cada `commit` fuerza un `fsync` y
hacerlo por mensaje limitaría el caudal. El precio es que un corte abrupto
pierde hasta un segundo de datos. Si el disco falla, el puente **sigue
publicando**: un disco lleno no debe tumbar el mapa.

El `sessionId` se guarda tal cual. Es un UUID anónimo que se genera en cada
abordaje y muere al bajar del vehículo, y es lo que permite analizar cuántos
viajes distintos aportaron a un mismo vehículo. Con `BACKEND_DB_RETENTION_DAYS`
se acota cuánto se conserva; el valor por defecto (`0`) no borra nunca, así que
conviene fijarlo antes de recoger datos de campo.

### Descartado con datos: el suavizado de posición

Promediar las últimas observaciones parecía una mejora evidente, así que se midió
antes de implementarlo con `tools/smoothing_tradeoff.py`, que simula varios
teléfonos publicando desde un mismo bus sobre el recorrido real de la línea C-01
(3 teléfonos, 8 m/s, sigma de GPS 8 m, publicando cada 5 s):

| Estrategia | Error medio | Salto medio |
|---|---|---|
| **más reciente (actual)** | **11.6 m** | 11.3 m |
| ventana de 2 s | 13.8 m | 8.8 m |
| ventana de 5 s | 19.5 m | 8.3 m |

**Suavizar empeora la precisión**: una ventana de 5 s cuesta un 68% más de error
para ganar un 26% de estabilidad visual. La causa es que las balizas publican cada
5 s y sin sincronizar, así que promediar "la ventana" es promediar posiciones de
hasta 5 segundos atrás — a 8 m/s, hasta 40 m de retraso — a cambio de cancelar
parte del ruido de ~10 m.

La observación más reciente es el mejor estimador con esta cadencia de publicación.
Si algún día las balizas publican más seguido, conviene repetir la medición antes
de reconsiderarlo.
