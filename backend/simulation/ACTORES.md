# Actores MQTT — S06, perfil de 30

Implementado **sin activación, cuentas provisionadas ni servicio instalado**.
Importar estos módulos no conecta, crea bases ni ejecuta recorridos. S07/S08 y
la verificación de las ACL/migración siguen pendientes antes del ensayo MQTT.

## Proceso y conexiones

`actors.py` coordina el motor S05 y los 30 canales de `publisher.py` en un proceso.
El ciclo monotónico central, cada 100 ms, atiende control, sesiones y sockets con
la API pública Paho: `socket`, `loop_read`, `loop_misc`, `loop_write`. No utiliza
30 hilos de red ni `loop_start`/`loop_forever` por actor.

Paho establece TCP/TLS de forma bloqueante: un único trabajador auxiliar abre
una conexión a la vez, sin cola pendiente; el ciclo sigue comprobando el apagado.
Timeout TCP: 2 s. Paho 2.1.0 usa el keepalive de 15 s para el handshake TLS; DNS
depende del sistema. No se promete una cota universal para terminar el trabajador:
al apagar se invalidan sus callbacks y su eventual socket se cierra, sin publicar
observaciones. Corte de publicación y salida del proceso son medidas diferentes.

Cada conexión autentica su propia cuenta `sim-001`…`sim-030`, MQTT 3.1.1, sesión
limpia y client ID nuevo por intento, de 19 caracteres ASCII. Solo se suscribe a
`rutautp/simulacion/estado` con QoS 1. Solo construye publicaciones en:

```text
rutautp/simulacion/{runId}/observaciones/{principal}/{sessionId}/posicion
```

Payload v1 de once claves, QoS 1, **no retained**. No publica vehículos, control,
ocupación, cambios viales ni notificaciones. El broker debe hacer cumplir las ACL;
las restricciones del código no sustituyen su comprobación real.

## Autoridad, horario y apagado

El productor comparte el control privado y el histórico del backend en el mismo
host. No añade HTTP ni entrega autoridad administrativa a iOS. Para arrancar exige
run en ejecución, perfil/feed fijados, horario vigente, revisión y propietario
exactos, revisión aplicada y PUBACK reciente del backend. Cada conexión exige
además CONNACK, SUBACK QoS 1 y su propio lease MQTT vigente. Conectar no concede
permiso; un retained vencido tampoco.

`ProducerLock` mantiene flock sobre `control.sqlite.producer-lock` y comprueba su
inode. Excluye otra instancia para toda esa base de control. No borrar/reemplazar
locks durante ejecución. Una reclamación durable por run impide reutilizarlo al
morir el generador: requiere disable/enable y UUID nuevo del backend, con sesiones
nuevas. No vuelve al inicio del recorrido dentro del mismo run.

Comprueba control/horario antes de atender sockets y antes de cada publicación.
Lee control antes de escribir paquetes pendientes. Revocación, caducidad o fallo
invalidan clientes y descartan sockets/colas, sin drenarlos. Callbacks tardíos de
clientes descartados se ignoran. Una revocación concurrente con un envío puede
dejar un paquete en tránsito; S03 vuelve a comprobar la autoridad y lo rechaza.
El PUBACK sigue sin demostrar que un iPhone retiró su marcador.

SIGINT/SIGTERM, suspensión >15 s, salto/retroceso civil relevante, cierre, duración
máxima de 900 s o presupuesto agotado detienen esta instancia y solicitan disable
persistente con CAS de su revisión. No pueden apagar una generación posterior.
Si el control no puede escribirse, corta localmente y los consumidores aplican
caducidad. No procesa atraso, rejuvenece timestamps ni reanuda ese mismo run.

## Cadencia, colas y reconexión

Publicaciones escalonadas en una ventana inicial de 5 s. Cada intento deja un
plazo de **5 s más jitter positivo de hasta 0,25 s**. Un plazo perdido considera
solo la lectura actual y programa el próximo desde el presente. Sin buffer offline.

Paho limita cola y mensajes en vuelo a 1; la aplicación no añade otra cola ni
llama publish mientras espera PUBACK. Si el paquete cumple 10 s, pierde permiso
o cambia la sesión, destruye ese cliente/socket. Cada reconexión crea otro Paho;
nunca llama `reconnect` del que conserva QoS 1. No reproduce su cola anterior.
Backoff exponencial 1, 2, 4, 8, 16, 32, 60 s, más jitter hasta 0,25 s, acotado a
1–60 s. Las conexiones se abren de una en una con equidad.

## Persistencia y presupuesto

`ObservationStore(existing_only=True)` abre solo el histórico existente con S02
ya migrado: no crea carpeta/base ni ejecuta migraciones. Reutiliza los registros
de abordaje/cierre y los confirma antes de publicar una sesión nueva. El backend
conserva validación, agrupación y escritura de observaciones/estimaciones: el
generador no las inserta como si el backend las hubiera aceptado.

Fallo de guardado para y señala historial incompleto; S04 marca fallido ese run al
aplicar la revocación. Los datos conservados no se borran. El control guarda
`producerClaims` y `publishBudget` en runtime sin cambiar versión/revisión de
orden. Cada reserva compara run/revisión/propietario/productor y confirma
atómicamente contadores por run y fecha de Lima con SQLite FULL antes de llamar
Paho: máximo **6.000 por run y por día**. Incluye reservas cuyo envío falla o se
cancela después; es un límite conservador de intentos de aplicación, no de
paquetes/cuota del broker. Reiniciar o cambiar de run no reinicia el total diario.
S09 añade [status, reportes y supervisor](OPERACION.md); preserva los registros
de `producerClaims` y `publishBudget`, sin reiniciar cuotas por una purga de
detalle ni compactarlos automáticamente. Restaurar todo el control/runtime
a una copia antigua exige revisar contadores: no son una cuota externa resistente
a restaurar el host completo.

`simulation_admin status` distingue running/stopped/unknown, frescura, run/revisión,
conexiones, pasajeros a bordo, actores listos, paquetes en vuelo, reservas y PUBACK
de observaciones. Muestra `revocation_pending` mientras el productor aún reporta
actividad de la revisión revocada; un latido ausente no demuestra parada. El
backend no sobrescribe el estado del productor. `clientsApplied` sigue desconocido.
Diez micros nominales no garantizan diez estimaciones ni diez marcadores; el mapa
conserva máximo ocho, también en Seguimiento desde S08.

## Credenciales y CLI del ensayo posterior

Fichero regular **fuera del repositorio**, propiedad del usuario de servicio,
permisos 0600 y máximo 64 KiB. No se crea un ejemplo utilizable ni se reutilizan
credenciales del backend/teléfonos. Estructura, sin valores concretos:

```text
schemaVersion: 1
host: nombre del broker elegido
port: puerto verificado
tls: booleano explícito
caFile: null para CA del sistema, o ruta a CA privada
accounts: objeto con exactamente las 30 claves sim-001…sim-030
  cada entrada: username igual a su clave, password exclusivo y no vacío
```

Con TLS habilitado comprueba CA y hostname. Los secretos no aparecen en repr,
status, referencia ni errores de la CLI. Desde `backend/`, con rutas reales
preparadas por el operador:

```sh
python -m simulation --control-db /RUTA/PRIVADA/control.sqlite \
  --history-db /RUTA/DEL/HISTORICO.sqlite \
  --credentials-file /RUTA/PRIVADA/actors.json check
```

`check` lee configuración/perfil/control, sin abrir histórico, instanciar motor,
obtener lock ni conectar. No acredita cuentas, ACL o red. Solo el subcomando
explícito `run` abre conexiones después de completar los requisitos; no se ha
ejecutado aquí. `--reference-jsonl /RUTA/NUEVA/referencia.jsonl`, opcional para run,
crea un archivo nuevo 0600 sin sobrescribir, con verdad nominal, lecturas y eventos
separados de las estimaciones. Sin esa opción no abre referencia automáticamente.

S10 añade perfiles/whitelists fijados `ensayo-2` y `ensayo-6`; el productor y sus
credenciales validan exactamente las cuentas de cada escalón. Véase [VALIDACION.md](VALIDACION.md).
Las pruebas usan clientes capturados, futuros manuales, reloj inyectado y SQLite
temporal. La evidencia conectada y sus métricas se distinguen de esas pruebas en
el informe S10; no extrapolar sus resultados a batería o a otro despliegue.
