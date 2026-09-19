# Backend de RutaUTP — puente `observaciones` → `vehiculos`

Servicio que convierte las observaciones anónimas de los pasajeros a bordo en
posiciones de vehículos que el resto de usuarios ve moverse en el mapa.

```
App a bordo                  Backend (este servicio)                App de otros
     │                                │                                  │
     │ MQTT publish                   │ valida contra GTFS                │ MQTT subscribe
     ▼                                │ agrupa por unidad                 ▲
rutautp/observaciones/{sesión}/posicion│ deriva el vehicleId              │
     │                                ▼                                  │
     └──────────► [ Mosquitto ] ──► (consume) ──► (publica) ──► [ Mosquitto ]
                                                          rutautp/vehiculos/{id}/posicion
```

El cliente ya filtra antes de publicar, pero **el servidor no puede confiar en
él**: el broker es un canal compartido y cualquiera con credenciales válidas
puede publicar en `rutautp/observaciones/#`. Este servicio es la frontera de
confianza.

## Qué resuelve

| Problema | Cómo |
|---|---|
| Un cliente puede mentir | Cada observación se contrasta contra el recorrido real de la ruta que dice usar |
| Un cliente puede suplantar un vehículo | El `vehicleId` **lo deriva el servidor**; se ignora cualquier identificador del mensaje |
| Un cliente puede inundar el canal | Límite de mensajes por sesión en ventana deslizante |
| QoS 1 entrega duplicados | Deduplicación por `(sessionId, timestamp)` |
| Varios pasajeros, un solo bus | Agrupación por ruta, proximidad y ventana temporal |
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
python -m rutautp_backend --check

# Se conecta, procesa y registra, pero no publica nada. Útil para observar.
python -m rutautp_backend --dry-run

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
| `MQTT_USERNAME` | — | Usuario. Debe ser el `backend` de la ACL, no el `observer` |
| `MQTT_PASSWORD` | — | Contraseña |
| `MQTT_TLS` | `0` | `1` habilita TLS e implica el puerto 8883 |
| `MQTT_CA_CERT` | — | Ruta a la CA propia (PEM). Obligatoria si el certificado es autofirmado |
| `MQTT_CLIENT_ID` | aleatorio | Identificador del cliente MQTT |
| `GTFS_DIR` | `../gtfs` | Directorio del feed |

### Validación

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_MAX_ACCURACY_M` | `50` | Precisión GPS máxima aceptada |
| `BACKEND_MAX_AGE_S` | `45` | Antigüedad máxima de una observación |
| `BACKEND_MAX_CLOCK_SKEW_S` | `10` | Desfase de reloj tolerado hacia el futuro |
| `BACKEND_MAX_DISTANCE_TO_ROUTE_M` | `50` | Distancia máxima al recorrido |
| `BACKEND_MAX_HEADING_DIFF_DEG` | `60` | Desvío máximo respecto al sentido del recorrido |
| `BACKEND_MAX_SPEED_MS` | `30` | Techo de velocidad (108 km/h) |
| `BACKEND_MAX_MSGS_PER_MINUTE` | `20` | Límite por sesión. La baliza legítima envía 12 |
| `BACKEND_DEDUPE_WINDOW_S` | `120` | Ventana de deduplicación |

### Agregación

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_MERGE_RADIUS_M` | `300` | Distancia para considerar que dos observaciones son del mismo vehículo |
| `BACKEND_MERGE_WINDOW_S` | `90` | Ventana temporal para fusionar |
| `BACKEND_VEHICLE_TTL_S` | `60` | Sin observaciones durante este tiempo, el vehículo se retira |
| `BACKEND_PUBLISH_INTERVAL_S` | `5` | Ritmo mínimo de publicación por vehículo |

### Registro

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKEND_LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `BACKEND_LOG_JSON` | `1` | Una línea JSON por evento, apta para volcar a un archivo |

## Contrato

Ambos extremos están copiados de los tipos Swift que ya existen, y hay pruebas
que lo verifican leyendo el código del proyecto de Xcode (ver `tests/test_contract.py`).

**Entrada** — `rutautp/observaciones/{sessionId}/posicion`, QoS 1, sin retención.
Corresponde a `PassengerObservationPayload`:

```
schemaVersion, sessionId, routeId, linea, lat, lon, speed, heading,
accuracy, motionActivity, timestamp
```

**Salida** — `rutautp/vehiculos/{vehicleId}/posicion`, QoS 1, sin retención.
Corresponde a `VehiclePositionMessage`:

```
vehicleId, linea, lat, lon, speed, heading, timestamp
```

Un nombre de campo equivocado no rompería nada de forma visible: el
`JSONDecoder` del teléfono descartaría el mensaje en silencio y el mapa se
quedaría vacío sin un solo error. Por eso esa prueba existe.

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

**Los ordinales de vehículo no se reutilizan.** Si un vehículo expira y aparece
otro en la misma ruta, recibe un identificador nuevo: reutilizarlo haría saltar
el marcador en el mapa.

## Verificación

```bash
# 128 pruebas: geometría, GTFS, validación, agregación, puente y contrato.
python -m pytest

# Prueba de humo con un broker real: levanta Mosquitto en un puerto de prueba,
# arranca el backend, publica una observación sintética y comprueba que sale la
# posición vehicular. Es lo único que cubre el cableado con paho.
./tools/smoke_test.sh
```

## Relación con `puente-demo.sh`

[`../mqtt/puente-demo.sh`](../mqtt/puente-demo.sh) fue el puente de
demostración: republica todo lo que entra sin validar nada. Este servicio lo
reemplaza. El script se conserva porque es una prueba de humo de 60 líneas que
no necesita dependencias de Python.

## Estado y siguientes pasos

**Funciona**: validación, agrupación, publicación, caducidad y métricas.

**Siguiente**:

1. **Persistencia.** Hoy todo vive en memoria. Guardar el histórico permitiría
   analizar precisión y falsos positivos después, que es lo que hace falta si el
   proyecto lleva artículo.
2. **Suavizado de posición.** Hoy se toma la observación más reciente. Promediar
   las de la ventana reduciría el salto entre lecturas de distintos teléfonos.
3. **Estimación de ETA.** Con la posición y el `progress` sobre el shape ya
   calculado, se puede estimar el tiempo hasta un paradero.
4. **Sustituir el `vehicleId` derivado por una identidad real** cuando exista
   información de las empresas (placa o código de unidad).
