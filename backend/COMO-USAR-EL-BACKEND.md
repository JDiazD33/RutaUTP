# Cómo prender y apagar el backend de RutaUTP

## Qué debe estar encendido

EMQX recibe y distribuye los mensajes por internet. El backend de la carpeta
`backend` los procesa: identifica buses y valida los reportes de cambios de ruta
y ocupación. Son dos piezas distintas. Tener EMQX activo no inicia el backend.

Durante las pruebas, el backend funciona en tu Mac. Mantén el Mac encendido,
con internet y sin suspenderse. Los iPhone pueden utilizar otra red o datos
móviles. Este procedimiento no configura un inicio automático al reiniciar el Mac.

## Antes de empezar

Abre Terminal y entra al proyecto:

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
```

Los comandos siguientes se ejecutan desde esa carpeta. Ya existe el entorno
Python en `backend/.venv`. La conexión está en `backend/deploy/backend.env`:
host de EMQX, puerto 8883, TLS y credenciales del usuario `backend`.
No compartas ese archivo ni lo subas a Git. No uses las cuentas de los teléfonos
para arrancar el backend.

Primero comprueba si ya está funcionando, para evitar iniciar dos copias:

```sh
backend/.venv/bin/python backend/tools/run_configured.py --health-check
pgrep -fl 'rutautp_backend|run_configured.py'
```

Si aparece `salud OK`, ya está activo. Si hay un proceso pero la comprobación
falla, revisa sus mensajes y detenlo antes de iniciar otra copia. Un archivo de
salud antiguo puede permanecer tras un cierre abrupto: por sí solo no prueba
que el proceso siga vivo.

## Prenderlo y ver sus mensajes

```sh
backend/.venv/bin/python backend/tools/run_configured.py
```

Deja esa terminal abierta. Debe aparecer la conexión con EMQX. Para apagarlo,
presiona **Control + C** en esa misma terminal. Espera a que regrese el cursor.

## Prenderlo en segundo plano

Usa esta opción si quieres cerrar la terminal y mantenerlo funcionando.
No la ejecutes si ya hay una copia activa.

```sh
mkdir -p backend/data
nohup backend/.venv/bin/python backend/tools/run_configured.py >> backend/data/backend-runtime.log 2>&1 < /dev/null &
```

Espera unos segundos y comprueba:

```sh
backend/.venv/bin/python backend/tools/run_configured.py --health-check
```

`salud OK` indica que el proceso tiene un latido reciente y está conectado al
broker. No demuestra por sí solo los permisos de todos los canales ni que los
iPhone estén enviando ubicaciones.

## Ver qué está pasando

Si lo iniciaste en segundo plano:

```sh
tail -n 50 backend/data/backend-runtime.log
```

Para ver los mensajes nuevos en directo:

```sh
tail -f backend/data/backend-runtime.log
```

En este caso, **Control + C solo cierra la vista del registro**, no apaga el
backend. El registro se acumula; este procedimiento no configura su rotación.

## Apagarlo cuando está en segundo plano

Busca el proceso:

```sh
pgrep -fl 'rutautp_backend|run_configured.py'
```

La primera columna muestra su número de proceso (PID). Identifica la línea de
Python con `-m rutautp_backend`. Detén ese número, por ejemplo:

```sh
kill -TERM 12345
```

**Reemplaza `12345` por el número que acabas de comprobar**. No es un número fijo.
Espera unos segundos y vuelve a ejecutar la búsqueda. La línea del backend debe
desaparecer. La comprobación de salud dejará de dar `salud OK`.
No borres la base de datos para detener el servicio.

## Reiniciarlo

1. Detén la copia activa siguiendo el apartado anterior o con Control + C.
2. Comprueba que su proceso desapareció.
3. Inícialo una sola vez, en primer plano o en segundo plano.
4. Comprueba que aparece `salud OK`.

Después de modificar `backend.env`, reinicia para aplicar la configuración.
Después de cambiar permisos en EMQX, reinicia para renovar las suscripciones.
Los votos de ocupación y cambios de ruta están en memoria: al reiniciar,
se necesitan nuevas confirmaciones. El histórico SQLite se conserva en
`backend/data/rutautp.sqlite` y está sujeto a la retención configurada.

## Problemas frecuentes

- **Contraseña rechazada:** revisa la contraseña MQTT del usuario `backend` en
  `backend.env`, sin agregar comillas. No es la contraseña de EMQX Cloud.
- **Conectado, pero sin reportes:** comprueba los permisos de publicación y
  suscripción de los tres usuarios y la configuración de cada iPhone.
- **Sin buses reales:** el servicio necesita observaciones válidas y corroboradas;
  encenderlo no crea buses de prueba en el mapa.
- **«Ayudar con ubicaciones» gris:** revisa la configuración MQTT de la app.
  Encender el backend no configura automáticamente el teléfono.
- **Dejó de funcionar al apagar o suspender el Mac:** vuelve a encenderlo e inicia
  el backend. Para disponibilidad continua, el proceso debe ejecutarse en un
  servidor que permanezca encendido.

Las reglas de EMQX y la configuración de los teléfonos están en
[la guía de puesta en marcha](deploy/EMQX-PUESTA-EN-MARCHA.md).
