# Abrir los micros en el iPhone sin cable

Preparación del 27/10/2026. Usa tu despliegue **rutautp-broker** de EMQX:
`ce14c140.ala.us-east-1.emqxsl.com`, puerto **8883**, con TLS.
La Mac ejecuta backend y 30 balizas; EMQX transporta; el iPhone recibe diez modelos
con Vacío / Con espacio / Lleno. La nueva vista dibuja la flota vigente completa;
el botón con su cantidad permite encuadrarla. El panel de líneas mantiene su filtro.
En Ajustes → Micros en el mapa se puede limitar la cantidad visible; la opción
predeterminada es Todos. El límite no elimina posiciones del receptor ni recorta
la información disponible para rutas y fichas. El micro seleccionado se mantiene
entre los visibles sin superar la cantidad elegida.
La Mac y el iPhone necesitan Internet; pueden compartir Wi-Fi como has previsto.

## Preparación inicial, una sola vez

**Estado del 27/10:** el usuario ya importó las cuentas y permisos, `comprobar`
verificó las 31 cuentas y la nueva Release quedó instalada y aprovisionada.
Para el uso diario basta la [guía corta](INICIO-RAPIDO-PRESENTACION.md).
Los pasos de preparación siguientes quedan como referencia; no hay que repetirlos.

La carpeta privada ya preparada es:

`/Users/joaquindiaz05/Library/Application Support/RutaUTP/Presentacion`

Contiene secretos: no la compartas ni la subas a Git. No ejecutes `preparar` de
nuevo sobre ella: conserva cuentas, histórico y cuota. El comando rechaza
sobrescribirla. Tu `backend/deploy/backend.env` habitual permanece intacto.

### Dar de alta las cuentas nuevas en EMQX

Se prepararon 30 usuarios `sim-001`…`sim-030` y el lector `presentation-reader`.
En Safari, abre **rutautp-broker → Access Control → Authentication → Import**.
Selecciona este archivo mediante el selector de archivos (puedes usar ⌘⇧G):

`/Users/joaquindiaz05/Library/Application Support/RutaUTP/Presentacion/EMQX-CUENTAS-IMPORTAR.csv`

Completa la importación tú mismo. No pegues sus contraseñas en el chat. Este
archivo solo crea las 31 cuentas nuevas; no contiene `backend`, `device-001`,
`device-002` ni `observer`.

En **Authorization → Username → Import**, importa los permisos de esos usuarios:

`/Users/joaquindiaz05/Library/Application Support/RutaUTP/Presentacion/EMQX-PERMISOS-IMPORTAR.csv`

Son 93 reglas de los usuarios nuevos. Los actores solo leen control y publican
su propio canal sintético. El lector solo lee control y posiciones. El deny `#`
debe quedar después de sus permisos específicos. No reemplaces reglas globales
ni las de los usuarios existentes. La importación por CSV está documentada por
[EMQX para Authentication](https://docs.emqx.com/en/cloud/latest/deployments/default_auth.html)
y [Authorization](https://docs.emqx.com/en/cloud/latest/deployments/default_authz.html).

A la cuenta `backend` hay que **añadir**, conservando sus reglas y dejando
cualquier denegación general al final:

| Permiso | Acción | Tópico |
|---|---|---|
| Allow | Subscribe | `rutautp/simulacion/+/observaciones/+/+/posicion` |
| Allow | Publish | `rutautp/simulacion/estado` |

El archivo privado `EMQX-PERMISOS-REVISAR.json` describe todo el alcance. No se
necesita otra instancia MQTT, una API key ni cambiar el límite de gasto del broker.
La importación y los dos permisos deben comprobarse antes del primer encendido.

### Comprobar cuentas y permisos

Desde Terminal:

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
backend/.venv/bin/python backend/tools/presentacion.py comprobar
```

Este comando **no inicia pasajeros ni habilita el run**. Conecta las cuentas,
comprueba lectura de control y denegaciones de escritura mediante mensajes de
validación sin coordenadas. Termina con `accountsVerified: 31` solo si las
comprobaciones pasan. Si falla, no cambies permisos a `rutautp/#`: revisaremos
el permiso exacto. El primer run comprobará además publicación del backend y
quorum real de los diez modelos.

### Instalar y configurar el iPhone

Después de compilar e instalar la nueva Release, el ingeniero ejecuta una vez:

```sh
backend/.venv/bin/python backend/tools/provisionar_presentacion_iphone.py \
  --device 00008020-000A7100227A002E
```

La contraseña pasa solo por el entorno del proceso. La app guarda la cuenta
lectora en otra entrada de Keychain y conserva la habitual; el destino y la
selección de Mapa son persistentes. No activa S10 ni su muestreo CPU.
Un resultado de apertura del comando no demuestra por sí solo conexión aceptada:
comprobarlo abriendo luego desde el icono sin Xcode. No necesitas aprovisionar
cada vez que enciendas el backend.

## Encender para presentar

No abras también el backend habitual con `run_configured.py`: este comando ya
inicia su propia copia, con control e histórico separados. Si el habitual está
activo, detenlo desde la terminal donde lo abriste antes de seguir.

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
backend/.venv/bin/python backend/tools/presentacion.py iniciar
```

Deja esa terminal abierta y la Mac encendida, con Internet. La orden mantiene
la Mac despierta mientras su servicio funciona. **No cierres la tapa.**

Abre otra terminal para consultar:

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
backend/.venv/bin/python backend/tools/presentacion.py estado
```

Espera `state: listo` y `probe.currentVehicles: 10`. La sonda confirma la recepción
en la Mac; no es una confirmación del iPhone. Después abre la app desde su icono,
sin cable. Entrará en Mapa y recibirá las siguientes posiciones frescas; no hay
que iniciar «Demo de seguimiento». Puede tardar unos segundos en conectar y
cargar. La versión corregida conserva la recepción entre pestañas y aplica el
estado vigente al volver a Mapa. Al pasar a segundo plano retira la conexión;
al regresar abre otra y espera control y posiciones vigentes, sin exigir cerrar
la app. Las pruebas manuales y su resultado se registran en `metricas`.

La sesión normal tiene un máximo de **15 minutos**, incluidos los preparativos
después de habilitar el run. Para un ensayo breve explícito:

```sh
backend/.venv/bin/python backend/tools/presentacion.py iniciar --seconds 180
```

El servicio comprueba horario y cuota agregada antes de habilitar. Una sesión
de 180 s reserva como máximo 1110. La cuota efectiva se vuelve a leer al iniciar,
incluyendo S10 y estos ensayos; el saldo de cierre queda en `metricas`.
Una sesión de 900 s reserva 5430
bajo este límite temporal; no inicia si no caben. No se borran contadores para
permitir otro ensayo. El perfil conserva los topes 6000/run y 10000/día.
Si no alcanza hoy, el consumo diario corresponde a la nueva fecha de Lima desde
medianoche, y el horario permite iniciar de nuevo desde las 07:00. El histórico
de días anteriores permanece guardado.

## Apagar

En la terminal del servicio, pulsa **Control+C**. O desde otra terminal:

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
backend/.venv/bin/python backend/tools/presentacion.py detener
```

Espera a que termine y consulta `estado`. Se guarda OFF, se detienen sus procesos
y se conserva el histórico. Las cuentas permanecen para la próxima sesión; no
hay que importarlas otra vez. No borres la base ni cambies el reloj del equipo.
El servicio no se inicia automáticamente al encender la Mac.

## Perfil adicional: 50 balizas / 15 micros

Las veinte cuentas `sim-031`…`sim-050` se preparan por separado, conservando las
treinta originales y el lector. Se guardan en `actors-credentials-pasajeros-50.json`.
Los CSV adicionales contienen solo esas veinte cuentas y sus sesenta reglas.
La importación de permisos corresponde a **Authorization → Username**;
Client ID corresponde a otro tipo de identidad. No repetir la importación de
las cuentas existentes. La comprobación del perfil es explícita:

```sh
backend/.venv/bin/python backend/tools/presentacion.py comprobar --profile pasajeros-50
```

Debe confirmar 51 cuentas sin activar productores. Para el ensayo:

```sh
backend/.venv/bin/python backend/tools/presentacion.py iniciar --profile pasajeros-50 --seconds 240
```

El perfil de 50 usa quince rutas, diez grupos de tres y cinco de cuatro. Mantiene
el mínimo de dos participantes activos, la cadencia de cinco segundos y los
topes de 6000 por run / 10000 por día. Su duración máxima inicial es 300 segundos;
una sesión de 240 reserva hasta 2450 llamadas de observaciones. Los dos perfiles
comparten el mismo ledger para conservar la cuota diaria y no pueden ejecutarse
simultáneamente. `detener` apaga el servicio propio cualquiera que sea el perfil.
La configuración del iPhone es la misma; no necesita nuevas credenciales.

## Recuperar la configuración habitual del iPhone

### Ayudar con ubicaciones conservando la recepción de micros

La cuenta `presentation-reader` solo recibe. Los aportes del iPhone usan su
cuenta propia, guardada en la entrada habitual del Keychain del mismo endpoint.
La app puede conservar ambos roles sin convertir al lector en publicador.
El interruptor sigue pidiendo consentimiento y los permisos del sistema antes
de iniciar la contribución; configurar una cuenta no equivale a activarlo.

Si no hay una cuenta propia guardada, el ingeniero puede aprovisionar una
**cuenta device- ya existente** desde Terminal, con el iPhone conectado:

```sh
backend/.venv/bin/python backend/tools/provisionar_presentacion_iphone.py \
  --device 00008020-000A7100227A002E --contribution-user device-001
```

El comando pide la contraseña MQTT localmente sin mostrarla. No escribirla en
el chat. No crea ni cambia cuentas de EMQX ni sus permisos, y no activa la
contribución; después se comprueba el interruptor en Ajustes. No usar contraseñas
de `backend`, del lector ni de actores `sim-` como cuenta del teléfono.

### Salir de la configuración de presentación

Con el cable conectado y la misma identidad de app:

```sh
backend/.venv/bin/python backend/tools/provisionar_presentacion_iphone.py \
  --device 00008020-000A7100227A002E --restaurar
```

Recupera el destino y la cuenta habitual si ya existían; no borra esa entrada de
Keychain. Si nunca se había aprovisionado una cuenta habitual, debe configurarse
como se indica en `deploy/EMQX-PUESTA-EN-MARCHA.md`.

## Límites que recordar

- Ventana actual: 07:00–22:30, hora de Lima. Todavía no es una jornada continua.
- La firma instalada examinada vence el 30/10/2026 a las 15:35; renovar e instalar
  cerca de la presentación cuando sepamos la fecha.
- Sin backend, Internet, control vigente o quorum, el mapa retira los micros
  sintéticos. No mantiene coordenadas antiguas para aparentar conexión.
- Los resultados de cada ensayo quedan en `metricas`; compilar no acredita esa
  prueba. El perfil de 100 continúa sin preparar ni activar.
