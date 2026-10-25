# S08 — Presentación y retirada de posiciones

La app conserva transporte y procedencia por separado. MQTT continúa usando
`VehicleTrackingSource.real` para posiciones observadas y sintéticas. `dataOrigin`,
`simulationRunId` y `controlRevision` llegan hasta `BusAnimado` y `BusPanelItem`;
Seguimiento conserva el `VehiclePosition` completo. No se activa tráfico en S08.

## Presentación acordada

La aclaración del usuario sustituye la etiqueta visible «Demostración» del plano
original: la recepción MQTT usa textos naturales y neutrales, sin interruptor
público. «Posición recibida», «Datos recientes», «Esperando datos» y «Sin ETA» no
afirman observación real ni confirmación de una unidad. Los identificadores
internos `sim:{run}:…` no se muestran como matrículas ni como nombres de unidades.
La procedencia se conserva en memoria y en el circuito de datos para operación
y métricas. La demo local existente sigue identificándose como demo.

El mapa conserva GTFS, filtros por ancla/destino y su condición actual de no
mostrar flota durante el dibujo de un viaje. El máximo de marcadores vehiculares
es ocho; Seguimiento aplica también ese máximo. No se recortan las posiciones
recibidas para conseguirlo: una flota de diez o doce puede seguir completa en el
estado y los paneles. No se interpreta el número de marcadores como pasajeros,
conexiones MQTT o vehículos agrupados.

## Estado actual antes de dibujar

Los consumidores usan el stream como aviso y leen después
`positionsForPresentation()` del proveedor. En MQTT esta lectura revalida
caducidad, autorización y antigüedad con los relojes del lector S07 antes de
devolver el snapshot. Evita que un valor ya entregado por `AsyncStream`, o una
caché al cambiar catálogo/ancla, restaure un sintético que acaba de retirarse.
La entrada de pantalla/foreground también solicita una lectura vigente.

Seguimiento limita el movimiento ordinario a cuatro actualizaciones por segundo
con uptime. Altas, bajas y cambios de ruta, origen, run o revisión evitan ese
límite. En particular, no se pierde el último snapshot vacío al llegar dentro
de los 250 ms de la publicación anterior.

La identidad de presentación incluye ID, ruta, origen, run y revisión. Retirar
esa identidad o sustituirla cierra la selección/ficha anterior. El panel incorpora
los metadatos en su igualdad, incluso cuando las coordenadas no cambian. El
detalle abierto se actualiza con el mismo criterio.

## Limpieza y ocupación

- Disable, caducidad, control inválido, desconexión y background retiran los
  sintéticos en S07. S08 aplica ese snapshot a marcadores, tarjetas y selección.
  Los observados recientes permanecen.
- Las ETA vehiculares desaparecen con su bus/tarjeta. `VehicleETACache` conserva
  solo geometría de ruta/ancla, no una ETA anterior por vehículo. La retirada no
  llama a cancelar el viaje, borrar destinos ni vaciar el catálogo GTFS.
- Cerrar el consumidor limpia flota, selección, velocidades e historial. Reabrir
  espera posiciones del proveedor actual; una retirada no cambia a animación
  local para rellenar el mapa.
- El detalle solo crea `BusOccupancyPanel` para transporte MQTT **y** procedencia
  `observed`, con ID backend fuera del namespace reservado `sim:`. La animación
  local, sintéticos, legado y desconocidos muestran «Ocupación no disponible» y
  no instancian ese lector. Cambiar la identidad recrea el lector observado.
- La ocupación y el consentimiento de contribución del viaje del usuario siguen
  su flujo existente. Los actores no votan ni publican ocupación.

En Seguimiento MQTT, la velocidad proviene del payload: 0 conserva una parada,
-1 se presenta como desconocida y no se estima movimiento por el ruido entre
coordenadas. La demo local conserva su estimación por desplazamiento. El rumbo
desconocido sigue siendo -1 en los modelos; el dibujo 3D puede usar orientación
neutra sin convertirla en un rumbo medido.

## Comprobación y límites

Se preparan 21 casos puros de política y 12 de integración iOS con proveedores,
catálogo y permiso GPS capturados. Los casos puros pueden ejecutarse en un
paquete temporal macOS junto con las 31 regresiones de recepción S07, solo con
autorización expresa. Compilar los casos iOS no acredita su comportamiento.

Debug, Release y `build-for-testing` usan destino genérico iOS Simulator arm64;
no requieren lanzar app ni simulador. Resultados y logs se registran en el
informe S08 de `mds`. El ensayo visual conectado, los objetivos de retirada
≤5 s/caducidad ≤20 s y CPU/RAM/batería con 30 pasajeros corresponden a S10.

La factoría conserva la compatibilidad explícita v1 de S07 mientras simulación
está deshabilitada. Antes de producir tráfico: verificar migración/ACL efectivas,
coordinar salida v2, instalar S07/S08 y aplicar los procedimientos S09/S10.
