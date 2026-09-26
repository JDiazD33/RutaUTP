# Conectar RutaUTP al EMQX existente

Broker: `ce14c140.ala.us-east-1.emqxsl.com`, puerto `8883`, TLS activado.
Usuarios ya creados según la configuración previa: `device-001`, `device-002`, `backend`.
EMQX transporta los mensajes; el proceso Python de RutaUTP se ejecuta aparte.
No hay que instalar otro Mosquitto. El backend puede ejecutarse en el Mac durante
las pruebas; los teléfonos solo necesitan internet, no la misma Wi-Fi.

## 1. Completar la configuración local del backend

En `backend/deploy/backend.env`, completar `MQTT_PASSWORD=` con la contraseña
existente del usuario `backend`, sin añadir comillas. El archivo está excluido
de Git y tiene permisos de lectura/escritura solo para su propietario. No usar
la contraseña de EMQX Cloud ni la de un teléfono.

Desde la raíz de RutaUTP:

```sh
backend/.venv/bin/python backend/tools/run_configured.py
```

Mantener esa terminal y el Mac activos durante las pruebas. Para detenerlo,
Ctrl+C. Para comprobarlo desde otra terminal:

```sh
backend/.venv/bin/python backend/tools/run_configured.py --health-check
```

## 2. Ampliar Authorization en EMQX

Conservar las reglas de observaciones y vehículos ya creadas, y la denegación
general para lo no autorizado. Añadir estas reglas por usuario con permiso
Allow para los puntos 4 y 5. No sustituirlas por permisos generales sobre `#`.
La plantilla `mqtt/config/acl.example` es de Mosquitto: EMQX Cloud no la carga
automáticamente. Los permisos siguientes aún requieren aplicarse en EMQX.

| Usuario | Acción | Tópico |
|---|---|---|
| `device-001` | Publish | `rutautp/cambios/device-001/reporte` |
| `device-001` | Subscribe | `rutautp/cambios/device-001/recibo` |
| `device-001` | Subscribe | `rutautp/cambios/estado` |
| `device-001` | Publish | `rutautp/ocupacion/device-001/reporte` |
| `device-001` | Subscribe | `rutautp/ocupacion/device-001/recibo` |
| `device-001` | Subscribe | `rutautp/ocupacion/estado` |
| `device-002` | Publish | `rutautp/cambios/device-002/reporte` |
| `device-002` | Subscribe | `rutautp/cambios/device-002/recibo` |
| `device-002` | Subscribe | `rutautp/cambios/estado` |
| `device-002` | Publish | `rutautp/ocupacion/device-002/reporte` |
| `device-002` | Subscribe | `rutautp/ocupacion/device-002/recibo` |
| `device-002` | Subscribe | `rutautp/ocupacion/estado` |
| `backend` | Subscribe | `rutautp/cambios/+/reporte` |
| `backend` | Publish | `rutautp/cambios/+/recibo` |
| `backend` | Publish | `rutautp/cambios/estado` |
| `backend` | Subscribe | `rutautp/ocupacion/+/reporte` |
| `backend` | Publish | `rutautp/ocupacion/+/recibo` |
| `backend` | Publish | `rutautp/ocupacion/estado` |

## 3. Configurar cada iPhone

En el esquema **local y no compartido** de Xcode usado para instalar en cada
telefono, declarar estas variables en Run → Arguments → Environment Variables:

- `MQTT_HOST`: `ce14c140.ala.us-east-1.emqxsl.com`
- `MQTT_PORT`: `8883`
- `MQTT_TLS`: `1`
- `MQTT_USERNAME`: `device-001` en el primero y `device-002` en el segundo.
- `MQTT_PASSWORD`: la contraseña correspondiente a cada cuenta.

No guardar contraseñas en el esquema compartido ni usar la misma cuenta en
ambos teléfonos. Ejecutar desde Xcode con esas variables durante esta prueba;
el registro automático para instalaciones distribuidas todavía está pendiente.
La app admite las credenciales guardadas en Keychain, pero también necesita
resolver host, puerto y TLS al abrirse fuera de Xcode.

Activar «Ayudar con ubicaciones» y conceder ubicación/actividad física cuando
la app lo solicite. Para verificar detección real, ambos teléfonos deben viajar
en la misma unidad y mantener la app en primer plano. El simulador no demuestra
por sí solo la detección de pasajeros. El backend exige dos cuentas distintas.

## Criterios de finalización

1. Backend conectado a EMQX y health-check correcto.
2. Ambas cuentas pueden enviar sus observaciones y recibir posiciones, pero
   no suplantar otra cuenta ni publicar posiciones directamente.
3. Los dos teléfonos a bordo producen una unidad visible en el mapa.
4. Reportes de cambio de ruta y ocupación reciben respuesta del backend y
   necesitan corroboración; repetir desde una cuenta no suma otro voto.
5. Para disponibilidad continua, trasladar el mismo proceso Python a un
   servidor siempre encendido. EMQX por sí solo no ejecuta este programa.
