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
Si no ves todos los micros, aleja el mapa con dos dedos. En **Ajustes**, justo
debajo de **Ayudar con ubicaciones**, **Micros en el mapa** permite elegir
**Todos, 5, 10, 15, 20 o 25**. Se recuerda al reabrir; comienza en **Todos**.

La ocupación depende de la hora de Lima a la que enciendas la simulación. Hay más
micros llenos de 7 a 9, de 12 a 14 y de 16 a 18. Desde las 19 baja poco a poco y
hacia las 22 predominan los vacíos. El mensaje «Listo» indica si la demanda
simulada de esa hora es alta, media o baja.

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

Espera **«Listo: 15 micros…»** y abre Mapa. Este perfil permite
hasta cinco minutos por sesión. La orden habitual sin `--profile` conserva 30.

**Elegir cuántos micros (10 a 25)** con las mismas 50 cuentas del ensayo de 50:

```sh
backend/.venv/bin/python backend/tools/presentacion.py iniciar --micros 20 --seconds 240
```

Reparte las 50 cuentas entre los micros, con 2 o más por micro, que es el mínimo
para que el backend lo publique. Con 25 micros cada uno tiene 2: si una cuenta
falla, ese micro desaparece. Hasta 15 micros se usan las rutas del ensayo de 50 y
desde 16 se suman 10 rutas más del feed. Dura hasta 5 minutos por sesión y gasta
la misma cuota que el ensayo de 50. No uses `--micros` junto con `--profile`.
