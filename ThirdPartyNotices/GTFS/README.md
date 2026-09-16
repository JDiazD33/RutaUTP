# Feed GTFS estático

Origen de los datos: feed GTFS de transporte público empaquetado en `gtfs/` y cargado por
`GTFSRepository`. Publicado desde el entorno de desarrollo de OMUS / Trufi
(`https://omus-dev.trufi.dev`).

El feed se incluye **sin modificar**. Este documento no altera los datos de origen: registra su
procedencia y las comprobaciones que faltan.

## Qué lee la aplicación

De los 11 archivos del feed, `GTFSRepository` lee 9:

| Archivo | Uso |
| --- | --- |
| `agency.txt` | Nombre de la empresa por ruta |
| `routes.txt` | Línea, variante, color y nombre del recorrido |
| `trips.txt` | Relación ruta → viaje → shape |
| `shapes.txt` | Geometría del recorrido (53 616 puntos) |
| `stops.txt` | Paraderos |
| `stop_times.txt` | Orden de paradas y duración del viaje |
| `frequencies.txt` | Frecuencia (headway) por viaje |
| `fare_attributes.txt` | Tarifa |
| `fare_rules.txt` | Relación ruta → tarifa |

**No se leen:** `feed_info.txt` y `calendar.txt`. Viajan en el bundle pero ninguna parte del
código los consulta. `calendar.txt` declara un único servicio `Mo-Su` con vigencia 2000-2100, y
`feed_info.txt` es el que contiene las discrepancias de abajo.

## Discrepancias de metadatos (pendientes de resolver)

`feed_info.txt` declara:

```
feed_publisher_name  = Arequipa Bus
feed_publisher_url   = https://omus-dev.trufi.dev
feed_contact_email   = email@omus-dev.trufi.dev
feed_start_date      = 20000101
feed_end_date        = 21000101
```

Tres problemas:

1. **El publicador dice «Arequipa Bus» pero la geometría es de Trujillo.** Las coordenadas de
   `shapes.txt`, `stops.txt` y la agencia (`America/Lima`) corresponden al área de Trujillo, no a
   Arequipa. El campo parece arrastrado de otro feed del mismo entorno.
2. **Las fechas son de relleno** (2000-2100), no una vigencia real.
3. **El correo de contacto es un marcador de posición** (`email@...`).

**La aplicación no muestra estos campos**, y por eso la discrepancia es invisible en la interfaz;
sí es visible para quien inspeccione el bundle o use el feed como fuente.

**No se han reescrito los metadatos a propósito.** Corregirlos a mano sería falsificar los datos
de origen y ocultaría la pregunta que de verdad importa: de dónde salió este feed y con qué
autorización se distribuye.

## Pendiente antes de distribuir

- **Confirmar procedencia y licencia del feed con su publicador.** Sin ese dato no consta que la
  redistribución dentro de la aplicación esté autorizada. Este documento no afirma ninguna
  licencia porque no se ha podido verificar.
- Actualizar `feed_info.txt` desde el origen, no a mano, cuando el publicador lo corrija.
- Decidir si `feed_info.txt` y `calendar.txt` deben seguir en el bundle: hoy no se leen, así que
  solo aportan peso y confusión.

## Lo que este feed NO permite afirmar

El feed es estático: describe estructura (rutas, recorridos, paraderos, frecuencias y tarifas).
**No contiene posiciones GPS de vehículos.** Las posiciones «en tiempo real» que muestra la
aplicación son simuladas sobre estas geometrías, y así se identifican en la interfaz. El feed
tampoco acredita que las líneas estén operando hoy.
