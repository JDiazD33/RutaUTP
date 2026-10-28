# Ver los buses en el iPhone — guía corta

La app ya está instalada y configurada. Las cuentas de EMQX están comprobadas.
Usa estos pasos sin cable ni Xcode; la Mac y el iPhone necesitan Internet.

## 1. Encender en la Mac

Abre **Terminal** y pega estas dos líneas:

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
backend/.venv/bin/python backend/tools/presentacion.py iniciar --seconds 180
```

Inicia una prueba de **3 minutos**. Deja esta terminal abierta y la Mac encendida,
con Internet y sin cerrar la tapa. No abras también el backend antiguo.

## 2. Comprobar y abrir la app

Espera el mensaje **«Listo: 10 micros vigentes con ocupación»** en esa terminal.
Abre **RutaUTP desde su icono** en el iPhone, con Internet.
Entrará a **Mapa**; no uses «Demo de seguimiento».
El teléfono puede estar desconectado del cable. Aparecerán los micros y su
ocupación al recibir los datos frescos. La Mac debe seguir ejecutando el servicio.
Pulsa el botón con la cantidad de micros para encuadrarlos. En **Ajustes**, justo
debajo de **Ayudar con ubicaciones**, **Micros en el mapa** permite elegir
**Todos, 5, 10, 15 o 20**. Se recuerda al reabrir; comienza en **Todos**.
Si limitas la vista, el botón muestra, por ejemplo, **«5 de 15 micros»**.

## 3. Apagar

En la **primera terminal**, pulsa **Control+C** y espera que vuelva el cursor.
También puedes apagar desde otra terminal pegando:

```sh
cd /Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP
backend/.venv/bin/python backend/tools/presentacion.py detener
```

No borres bases ni vuelvas a importar las cuentas para reiniciar. Para encender
otra vez, repite el paso 1.

**Para presentar hasta 15 minutos**, sustituye la segunda línea del paso 1 por:

```sh
backend/.venv/bin/python backend/tools/presentacion.py iniciar
```

Solo arrancará si alcanza la cuota del día; las pruebas de hoy ya consumieron
parte de ella. No borres contadores: el consumo se cuenta por fecha de Lima.
Horario actual: 07:00–22:30, Lima. Para consultar el estado desde otra terminal:
`backend/.venv/bin/python backend/tools/presentacion.py estado` (en la misma carpeta).
La firma del iPhone debe estar vigente: la examinada vence el 30/10 a las 15:35.

**Ensayo de 50 balizas / 15 micros** (cuentas adicionales ya preparadas):

```sh
backend/.venv/bin/python backend/tools/presentacion.py iniciar --profile pasajeros-50 --seconds 240
```

Espera **«Listo: 15 micros…»** y pulsa **«15 micros»** en Mapa. Este perfil permite
hasta cinco minutos por sesión. La orden habitual sin `--profile` conserva 30.
