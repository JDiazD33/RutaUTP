# Broker MQTT de RutaUTP

Mosquitto en Docker es el canal de la baliza: los teléfonos de los
pasajeros a bordo publican observaciones anónimas y la app de los
demás usuarios consume las posiciones vehiculares resultantes.

```
Baliza (app a bordo)                    App de otros usuarios
        │ MQTT publish                         ▲ MQTT subscribe
        ▼                                      │
rutautp/observaciones/{session}/posicion       │
        │                                      │
        ▼                                      │
   [ Broker Mosquitto ] ──── vehiculos/{id}/posicion ────► mapa en vivo
        ▲
        │ (futuro: puente que valida, agrupa y republica)
   observaciones → vehiculos
```

## Variables de configuración (Scheme de Xcode, no van en el repo)

| Variable         | Obligatoria | Por defecto | Descripción                              |
|------------------|-------------|-------------|------------------------------------------|
| `MQTT_HOST`      | sí          | —           | Host o dominio del broker                |
| `MQTT_USERNAME`  | sí          | —           | Usuario (ver ACL)                        |
| `MQTT_PASSWORD`  | sí          | —           | Contraseña                               |
| `MQTT_PORT`      | no          | `1883`      | Puerto del broker                        |
| `MQTT_TLS`       | no          | `0`         | `1` habilita TLS (puerto 8883)           |
| `MQTT_FORCE_ONBOARD` | no      | `0`         | Solo DEBUG: fuerza sesión a bordo para probar MQTT sin viaje real |

Sin `MQTT_HOST/USERNAME/PASSWORD` la app funciona con detección local
y simulación, pero no transmite ni recibe por MQTT.

## Contratos de tópicos

- `rutautp/observaciones/{sessionId}/posicion` — baliza del pasajero.
  JSON: `schemaVersion, sessionId, routeId, linea, lat, lon, speed,
  heading, accuracy, motionActivity, timestamp`. QoS 1, no retained.
- `rutautp/vehiculos/{vehicleId}/posicion` — posiciones vehiculares
  que consume el mapa. Hoy las produce la simulación o un backend
  futuro; el consumidor valida cada mensaje con
  `VehiclePositionSanitizer` (coordenadas, timestamps, obsolescencia).

## Endurecimiento del broker

La config de desarrollo (`config/mosquitto.conf`, puerto 1883 plano)
sirve para red local. Antes de exponer el broker por un dominio
público hay que cerrar dos frentes:

### 1. Cifrado TLS (puerto 8883)

```bash
cd mqtt/config && mkdir -p certs && cd certs

# CA propia
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout ca.key -out ca.crt \
  -subj "/CN=RutaUTP CA"

# Llave y CSR del servidor (SUSTITUIR mqtt.tu-dominio.com por tu dominio)
openssl req -newkey rsa:2048 -nodes \
  -keyout server.key -out server.csr \
  -subj "/CN=mqtt.tu-dominio.com"

# Certificado del servidor firmado por la CA, con SAN obligatorio
printf "subjectAltName=DNS:mqtt.tu-dominio.com" > san.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -days 825 -out server.crt -extfile san.ext

chmod 600 server.key
```

Luego: `cp config/mosquitto-hardened.conf.example config/mosquitto.conf`
(ajustando rutas si hace falta), montar `./config/certs` en el
`compose.yaml` igual que los otros volúmenes, y en la app usar
`MQTT_TLS=1` con `MQTT_PORT=8883`.

> Con TLS 1.2+ activo, las credenciales y las ubicaciones viajan
> cifradas; sin TLS, cualquiera en el camino puede leerlas.

### 2. Control de acceso por rol (ACL)

```bash
cp config/acl.example config/acl
mosquitto_passwd -c config/passwords observer      # app
mosquitto_passwd -b config/passwords backend <pwd> # puente futuro
```

Y añadir en `mosquitto.conf`:

```
acl_file /mosquitto/config/acl
```

Con esto un teléfono comprometido no puede publicar en
`vehiculos/#` (no puede suplantar vehículos) ni leer más de lo
necesario.

## Prueba de humo (sin esperar un viaje real)

1. Scheme de Xcode → Environment Variables:
   `MQTT_HOST`, `MQTT_USERNAME`, `MQTT_PASSWORD`, `MQTT_FORCE_ONBOARD=1`.
2. Activar "Ayudar con ubicaciones" en el mapa y caminar cerca de una
   ruta GTFS (el bypass exige consentimiento, permiso y ruta próxima).
3. Observar el broker desde otra máquina:

```bash
mosquitto_sub -h <host> -p 1883 \
  -u observer -P <password> \
  -t 'rutautp/observaciones/#' -v
```

Deben llegar JSON cada ~5 s por sesión. Cortar la señal 45 s simula
baliza muerta: el consumidor la poda sola.

## Archivos sensibles (gitignored)

- `config/passwords` — contraseñas de Mosquitto.
- `config/acl` — ACL activa (la plantilla es `acl.example`).
- `config/certs/` — llaves y certificados.
- `data/` — persistencia del broker.
