# Presentación y validaciones — cierre del 28/10/2026

## Entrega

- Servicio reutilizable de presentación sobre el EMQX existente, con cuentas
  privadas persistentes, control OFF, cuota compartida e histórico conservado.
- Perfil predeterminado: 30 balizas / diez micros, máximo 900 s/run.
- Perfil ampliado: 50 balizas / quince micros, máximo 300 s/run.
  Ambos conservan 6000 llamadas/run y 10000/día; el productor mantiene una
  cadencia mínima de cinco segundos y exige dos identidades activas por micro.
- El iPhone abre Mapa con el lector persistente. Conserva recepción entre
  pestañas y reemplaza la conexión al regresar desde segundo plano.
- Ajustes → Micros en el mapa, debajo de Ayudar con ubicaciones: Todos, 5, 10,
  15 o 20. Todos es el valor inicial. Se conserva la flota completa para rutas
  y fichas; la selección tiene prioridad dentro del límite visible.
- El contador distingue visibles y recibidos; su botón encuadra los visibles.
- Los aportes usan la cuenta propia del iPhone guardada en Keychain, separada
  del lector del mismo endpoint, con consentimiento antes de activarse.
  No se modificaron permisos del lector para convertirlo en publicador.

## Evidencia observada

| Entrega | Resultado y alcance |
|---|---|
| S10 del 27/10 | Ensayo de 30 balizas completado; suspensión forzada del mismo proceso, recuperación y corte/reconexión del broker propio comprobados. La CPU estricta de primer plano continuo del ensayo largo sigue sin aceptación. |
| Presentación sin cable del 27/10 | El usuario confirmó apertura desde el icono, micros conservados entre pestañas, recuperación tras bloqueo sin cerrar la app y retirada al apagar. El primer intento fallido de recuperación se conservó. |
| Ensayo de 50 del 28/10 | Cuatro minutos con quince modelos; el usuario confirmó la flota completa. 2164 observaciones aceptadas, cero rechazos y 662 intentos de posición guardados. El iPhone registró OFF y flota cero al terminar. |
| Ajustes del 28/10 | 142 pruebas iOS correctas, cero fallos y cero omitidas. El diagnóstico confirmó cuenta de envío disponible y contribución apagada antes de la prueba manual. El usuario confirmó ambos controles en la Release instalada. |

El ensayo de 50 pasó además 557 pruebas Python y 91 pruebas iOS antes de los
cambios de Ajustes. Estos recuentos corresponden a ejecuciones distintas y
contienen regresiones repetidas; no deben sumarse como casos únicos.

## CPU

En el ensayo de 50, el iPhone XR recibió quince modelos durante los 65,001 s de
la captura. Las 66 muestras registraron la app activa. Media: **33,76 % de un
núcleo**; p95 por intervalo: 42,39 %; máximo por intervalo: 46,25 %.
Método: deltas de `getrusage(RUSAGE_SELF)` del mismo proceso y reloj monotónico.
Incluye diagnóstico; no mide batería, energía, memoria ni porcentaje total del
teléfono. Corresponde al binario `00EC09FA-8909-3961-89E8-D3B504B97FDA`.

El 25,20 % del S10 anterior incluye intervalos inactivos y otra versión; no es
una comparación equivalente. No se midió de nuevo CPU después de añadir el
selector de cantidad o recuperar la cuenta de aportes. La Release de Ajustes
tiene UUID `BF0539F6-2BEA-3D24-AAB7-F5019FFEE133`.

## Uso y conservación de evidencia

Procedimiento breve: [INICIO-RAPIDO-PRESENTACION.md](../INICIO-RAPIDO-PRESENTACION.md).
Configuración y recuperación: [COMO-USAR-LA-PRESENTACION.md](../COMO-USAR-LA-PRESENTACION.md).
Los productores quedaron apagados tras los ensayos; no se crearon automatizaciones
ni se preparó el perfil de 100.

Los informes completos, JSON, logs de compilación, resultados XCTest y trazas
permanecen en las carpetas `metricas/` y `mds/evidencias-*` del workspace padre,
fuera de este repositorio Git. Este resumen conserva los resultados principales
sin incorporar bases activas, contraseñas, CSV privados ni artefactos pesados.
