# Avisos remotos de cambios de ruta

Implementación del 12 de octubre de 2026. Desactivada por defecto en la app y
el backend. No se ha desplegado ni probado una entrega con Apple. El usuario
cuenta con EMQX y todavía no tiene Apple Developer. Los recordatorios locales
de la app no necesitan esta integración.

## Qué conecta

1. La app obtiene su token con `registerForRemoteNotifications`, después de
   activar «Cambios en mis líneas guardadas» y conceder el permiso de iOS.
2. Publica un registro privado por MQTT/TLS bajo su cuenta aprovisionada.
3. El backend conserva líneas, idioma, zona horaria y política de silencio en
   SQLite, y responde con un recibo privado de la revisión que guardó.
4. Dos cuentas diferentes confirman un cambio conforme a las reglas vigentes
   de `RouteChanges`. Solo los eventos posteriores a la suscripción de cada
   línea se consideran para el envío. No hay anuncios oficiales ni datos ficticios.
5. Un worker del backend envía un aviso visible a Apple por HTTP/2 con JWT ES256.
   El iPhone no necesita mantener MQTT conectado en segundo plano para recibirlo.
6. Tocar el aviso abre la consulta de cambios de esa línea. Se consulta el
   estado actual; el payload no crea reportes ni se usa como prueba de un cierre.
   Un aviso vencido, una línea eliminada o un viaje activo reciben un mensaje.

El permiso nativo, el registro de Apple y el recibo del backend son estados
distintos. «Registro remoto confirmado» acredita un registro y un proveedor
configurado; no acredita que Apple ya entregó un mensaje. Concentración,
Resumen programado y los ajustes de iOS siguen controlando la presentación.

## Requisitos antes de activar

- Equipo Apple Developer con APNs permitido para el identificador real de la app,
  perfil de firma con `aps-environment` y clave privada `.p8` autorizada para ese
  equipo, app y entorno. La clave pertenece al servidor; nunca al paquete iOS.
- Backend Python 3.10 o superior ejecutándose continuamente. EMQX es el broker,
  no el proceso Python ni el proveedor APNs. Mantener app y backend en el mismo GTFS.
- Cuentas MQTT diferentes por instalación, TLS verificado y las reglas privadas
  de registro/recibo de la sección siguiente. No habilitar acceso general a `#`.
- Red saliente del servidor a `api.sandbox.push.apple.com:443` para desarrollo o
  `api.push.apple.com:443` para producción; hora del sistema correcta.

En un mismo proceso el servidor fija un solo equipo, bundle ID y entorno. Para
probar desarrollo y producción simultáneamente, usar proveedores separados con
cuentas/canales y bases independientes; no permitir que los teléfonos elijan
credenciales, topic APNs o un servidor arbitrario en su JSON.

## Preparar el servidor

No se han ejecutado estos comandos en esta tarea. Se usan en el despliegue
cuando estén disponibles la cuenta y la clave reales:

```sh
cd backend
.venv/bin/python -m pip install -r requirements.txt -r requirements-push.txt
```

Completar fuera de Git la sección APNs de `backend/deploy/backend.env.example`:

```dotenv
APNS_ENABLED=1
APNS_ENVIRONMENT=development
APNS_TEAM_ID=TU_TEAM_ID
APNS_KEY_ID=TU_KEY_ID
APNS_TOPIC=EL_BUNDLE_ID_DE_LA_APP
APNS_KEY_PATH=/etc/rutautp/apns/AuthKey.p8
PUSH_DB_PATH=/opt/rutautp/backend/data/push.sqlite
```

`APNS_TEAM_ID` y `APNS_KEY_ID` deben ser los identificadores de 10 caracteres
de Apple. `APNS_TOPIC` debe coincidir exactamente con el perfil firmado de iOS.
No copiar estos valores de un ejemplo como si fueran credenciales válidas.
Dar lectura de la clave solo al usuario del servicio y proteger la carpeta de
datos, SQLite, archivos WAL y copias de seguridad: contienen tokens y preferencias.
La configuración incorrecta falla de forma explícita y no habilita envíos falsos.

La unidad systemd existente puede leer una clave en `/etc/rutautp/apns/` y
escribir el registro en `backend/data`. Para Docker, construir la imagen con
`--build-arg WITH_APNS=1`; después añadir las variables al servicio `backend`
del Compose del operador y montar la clave como archivo de solo lectura. El
Compose existente permanece sin APNs; no monta secretos ni activa envíos.

## Reglas del broker

En Mosquitto están añadidas a `mqtt/config/acl.example`. En EMQX, configurar
manualmente estos permisos **por usuario**; no se han aplicado al broker real:

| Cuenta | Acción | Tópico |
|---|---|---|
| `device-001` | Publish | `rutautp/notificaciones/device-001/registro` |
| `device-001` | Subscribe | `rutautp/notificaciones/device-001/recibo` |
| `device-002` | Publish | `rutautp/notificaciones/device-002/registro` |
| `device-002` | Subscribe | `rutautp/notificaciones/device-002/recibo` |
| `backend` | Subscribe | `rutautp/notificaciones/+/registro` |
| `backend` | Publish | `rutautp/notificaciones/+/recibo` |

Mantener la denegación general y las reglas previas. Ningún teléfono puede leer
registros con tokens, registrar otra cuenta ni falsificar recibos. No conservar
mensajes retained en estos canales. El backend rechaza un registro retained y
no procesa registros si su conexión MQTT no usa TLS. Los logs no muestran tokens
ni payloads privados. La herramienta ACL incorpora los nuevos permisos; no se
ha ejecutado porque la preferencia vigente del proyecto es solo compilar.

## Preparar la app con un equipo autorizado

Sin Apple Developer, conservar la configuración actual: `RUTA_PUSH_HABILITADO=NO`
y `RUTA_PUSH_ENTITLEMENTS` vacío. Así las instalaciones actuales siguen usando
sus capacidades existentes y los recordatorios locales.

Con un equipo habilitado, seleccionar ese equipo en Signing & Capabilities y
activar Push Notifications para el App ID. En los Build Settings del target
RutaUTP, fijar para las configuraciones que usarán push:

```text
RUTA_PUSH_HABILITADO = YES
RUTA_PUSH_ENTITLEMENTS = RutaUTP/RutaUTP-Push.entitlements
RUTA_APNS_ENVIRONMENT = development   (perfil de desarrollo)
RUTA_APNS_ENVIRONMENT = production    (TestFlight / App Store)
```

`CODE_SIGN_ENTITLEMENTS` ya toma `$(RUTA_PUSH_ENTITLEMENTS)`. Si Xcode lo sustituye
al añadir la capacidad, comprobar el archivo efectivo y el `aps-environment`
del perfil exportado. Debug usa `development` por defecto y Release
`production`, pero el entorno debe corresponder al **perfil de firma real**,
también si se usa Release con una firma de desarrollo. No cambiar la firma
actual a una cuenta inventada. No se añade ejecución en background ni se
requiere un servicio de notificaciones para recibir estos avisos visibles.

Después de aprovisionar MQTT en el iPhone, guardar una línea y activar el nuevo
control de Notificaciones. El permiso se pide en ese contexto, no al arrancar.
El token se obtiene de Apple y solo permanece en memoria de la app: no se
conserva como sustituto del registro nativo en el próximo arranque.

## Contrato y entrega

Registro: JSON schema 1 con `requestID`, `deviceID` (UUID estable), `revision`
creciente, `timestamp`, `environment`, `token` hexadecimal, `enabled`, `routes`,
`language`, `timeZone`, `pauseUntil`, `mutedDays`, `quietHours`, `quietStart`,
`quietEnd`, `sound`. `routes` solo admite IDs presentes en el GTFS del servidor
(máximo 100); días gregorianos domingo=1 a sábado=7; minutos 0...1439. Una franja
con inicio y fin iguales silencia todo el día. El tamaño está limitado a 32 KiB,
hay un máximo de 8 registros por cuenta y 10 000 registros en total.

Recibo: `requestID`, `revision`, `accepted`, `code`, `providerReady`, `leaseUntil`.
El cliente solo confirma la revisión enviada si recibe ese recibo. Una revisión
vieja no revierte una política nueva. El registro dura 30 días y se renueva al
abrir la app; después caduca y el servidor deja de enviar. Las referencias o
preferencias ilegibles se conservan en el teléfono y desactivan la suscripción.

La política se aplica antes de encolar, a la hora de la confirmación comunitaria
y nuevamente antes de cada intento de envío. Respeta la zona IANA enviada, los
días silenciados, rangos que cruzan medianoche, pausas temporales, desactivación
general/permanente y sonido. El aviso local sigue usando su agenda nativa propia.
No se acumulan reportes omitidos durante silencios ni se envían reportes previos
a la suscripción. Idiomas: español, inglés, francés, portugués de Brasil, alemán
y chino simplificado. Nombres de líneas del GTFS se conservan.

Sin conexión, una pausa puede guardarse localmente pero no llegar al backend.
La pantalla lo indica hasta recibir confirmación; el servidor usa entonces su
última política. Una notificación ya aceptada por Apple no puede retirarse a
distancia. Un cambio de zona horaria o idioma con la app cerrada se sincroniza
en la siguiente apertura. No se promete silencio instantáneo offline ni entrega
ilimitada cuando el registro ya venció.

Deduplicación persistida por instalación y evento. La vigencia del quorum limita
`apns-expiration`; no se envían avisos de reportes vencidos ni sin quorum al
revisar la cola. Apple `200` se registra como aceptado, no como entregado.
Tokens rechazados como `Unregistered`/`BadDeviceToken` se invalidan. Los rechazos
temporales explícitos 429/500/503 tienen hasta tres reintentos con espera, dentro
de la vigencia del evento. Los resultados inciertos de red no se reenvían:
se prefiere omitir un aviso a duplicarlo. Tras reiniciar, el quorum comunitario
es efímero y las tareas pendientes se descartan; no se reutiliza como evidencia.
Una configuración rechazada por Apple detiene al proveedor y requiere revisar
el servidor. Un nuevo recibo refleja que ese proveedor ya no está disponible.

## Verificación pendiente en dispositivo

La compilación no acredita provisión ni entrega. Cuando se solicite probar:

1. Confirmar firma APNs, entorno, ACL y backend activo, y activar una línea real.
2. Enviar el mismo cambio real desde dos cuentas distintas y comprobar un aviso
   por evento, con la app cerrada y el registro confirmado antes del reporte.
3. Comprobar silencios por horas, días, medianoche, pausa y desactivación después
   del recibo; no reproducir reportes omitidos al reactivar.
4. Cambiar líneas/idioma, revocar permiso de iOS y validar sincronización offline.
5. Abrir un aviso vigente/vencido y hacerlo durante un viaje, conservando su modelo.
6. Comprobar rechazo de tokens/entorno, deduplicación tras reinicios y expiración
   del registro en un entorno de prueba separado de los usuarios reales.

Referencias primarias: [registro de la app con APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns),
[autenticación del proveedor](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns),
[peticiones HTTP/2 a APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns),
[HTTPX HTTP/2](https://www.python-httpx.org/http2/),
[PyJWT](https://pyjwt.readthedocs.io/en/stable/usage.html),
[ZoneInfo](https://docs.python.org/3/library/zoneinfo.html).
