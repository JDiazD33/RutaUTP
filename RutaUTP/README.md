# Ruta UTP Trujillo

Aplicación nativa para iOS orientada a estudiantes de la UTP en Trujillo. Permite consultar recorridos de transporte público, buscar destinos, guardar lugares y seguir el avance de un viaje.

El proyecto combina mapas y ubicación del dispositivo con un feed GTFS local y funciones de demostración. No hay un backend conectado para posiciones de vehículos, publicaciones comunitarias o pagos.

## Requisitos y ejecución

- macOS con Xcode y un SDK de iOS compatible con el destino mínimo **iOS 17.5**.
- SwiftUI, MapKit, CoreLocation, Combine, PhotosUI y AVFoundation; sin paquetes de terceros.
- El proyecto usa el modo de lenguaje Swift 5 (`SWIFT_VERSION = 5.0`).

Abrir `RutaUTP.xcodeproj`, seleccionar el esquema **RutaUTP** y ejecutar en un simulador o iPhone. Para un dispositivo físico, configurar el equipo de firma en **Signing & Capabilities**. La cámara necesita un dispositivo con cámara disponible; en el simulador se puede utilizar la biblioteca de fotos.

Desde la raíz del repositorio, compilar para simulador sin firma:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project RutaUTP.xcodeproj -scheme RutaUTP \
  -configuration Debug -sdk iphonesimulator \
  -derivedDataPath /tmp/rutautp-build CODE_SIGNING_ALLOWED=NO build
```

El prefijo `DEVELOPER_DIR` permite usar Xcode aunque `xcode-select` apunte a Command Line Tools. Ajustar la ruta si Xcode está instalado en otra ubicación.

## Funcionalidades y estado

| Área | Implementación actual |
| --- | --- |
| Bienvenida | Entrada a la aplicación. |
| Mapa | MapKit, GPS del usuario, búsqueda de direcciones y lugares, destinos guardados y líneas cercanas. Los buses animados y sus llegadas son simulados. |
| Rutas | Catálogo GTFS, búsqueda por línea/empresa/recorrido, filtro de paraderos cercanos, detalle y exploración del recorrido. |
| Navegación de una línea | Seguimiento del usuario sobre el recorrido GTFS, progreso, próximo paradero y modo de simulación. |
| Tracking | Planificación de una línea directa con tramos a pie, seguimiento GPS, detección de desvíos, recálculo y resumen de sesión. Acceso desde el menú lateral. |
| Guardado | Lugares con coordenadas y referencias a líneas GTFS persistidos localmente. Se comparten con Mapa y Seguridad. |
| Seguridad | Lugares configurables, referencias de paraderos iluminados, llamada al 105 y comunidad de demostración. |
| Añadir a Comunidad | Formulario con descripción, foto opcional desde cámara o biblioteca de fotos y ubicación seleccionada en el mapa. La confirmación de publicación es demo: no envía ni guarda una publicación en un servidor. |
| Perfil | Foto, datos personales, preferencias, carné, interfaz de método de pago y cupones. Parte del estado es temporal; carné y pagos no tienen verificación ni procesamiento real. |
| Negocios | Catálogo local de 100 comercios ficticios para probar el mapa; cupones guardados localmente. |
| Accesibilidad | Ayuda de VoiceOver y modo de señas con clips locales. El catálogo de clips todavía está incompleto. |
| Idioma y apariencia | Español/inglés y tema claro/oscuro con preferencias persistidas. |
| Modo offline | Los datos GTFS, negocios y clips existentes vienen en el bundle. El perfil comprueba las rutas locales y explica los límites sin conexión; no implementa descarga de mapas base. |

### Añadir una foto en Seguridad

1. Entrar a **Seguridad → Comunidad → Añadir**.
2. Pulsar **Añadir foto**.
3. Elegir **Tomar foto** (si hay cámara disponible) o **Elegir de la galería / biblioteca de fotos**.
4. Seleccionar una imagen para verla en el formulario. El botón de quitar permite eliminarla y seleccionar otra.

La biblioteca usa `PHPickerViewController`, limitado a una imagen, sin solicitar acceso completo a Fotos. La cámara utiliza `UIImagePickerController` y el permiso de cámara de iOS. El adjunto permanece en el formulario durante esa presentación.

Para cambiar la foto de perfil, abrir **Datos personales** desde el menú hamburguesa o **Perfil → Editar perfil** y pulsar el botón de cámara sobre el avatar. Ambos accesos ofrecen cámara y galería / biblioteca de fotos. La imagen elegida se guarda localmente y se comparte entre el menú y Perfil.

## Arquitectura y estructura

```text
RutaUTP.xcodeproj/               Proyecto, target y recursos de Xcode
RutaUTP/
  RutaUTPApp.swift               Punto de entrada y cambio de idioma
  Navigation/                   AppRouter y RootView
  Screens/
    Bienvenida/                 Presentación
    Mapa/                       Mapa, búsqueda, menú lateral y las hojas del menú
    Rutas/                      Catálogo y detalle de líneas
    DetalleRuta/                Explorador y navegación sobre GTFS
    Tracking/                   Planificación y seguimiento de viajes
    Guardado/                   Lugares y líneas favoritas
    Seguridad/                  Comunidad y paraderos iluminados
    Perfil/                     Preferencias, carné y formularios
  Services/
    GTFS/                       Parser CSV, modelos y repositorio con caché
    Location/                   CoreLocation y protocolo de ubicación
    Routing/                    Cálculo con MKDirections
    Tracking/                   Modelos y proveedores real/simulado
    Negocios/                   Catálogo JSON y cupones
    Persistencia/               Versión de esquema y migraciones locales
    Imagenes/                   Persistencia de la foto de perfil
    SeniasService.swift         Resolución y presentación de señas
  Models/                       Modelos de dominio y almacenamiento de lugares
  Design/                       Colores, tipografía, espaciados, hápticos y componentes
  Utils/                        Idioma y proyección sobre recorridos
  Assets.xcassets/               Iconos y recursos visuales
  Info.plist                    Configuración adicional del bundle
  README.md
 gtfs/                          Feed estático empaquetado con la aplicación
 senias/                        Manifiesto y clips por idioma
 ThirdPartyNotices/             Procedencia y licencias de datos y recursos de terceros
 RutaUTPTests/                  Pruebas unitarias del núcleo puro
```

La navegación principal usa `AppRouter`, un `ObservableObject` con un enum de pantallas. `RootView` selecciona la pantalla y las vistas presentan detalles mediante sheets y full-screen covers; algunos formularios usan `NavigationStack`. La barra inferior es un componente propio.

Los módulos de mapa, rutas y seguimiento tienen ViewModels. Parte de la lógica y modelos auxiliares sigue dentro de archivos de vistas grandes. `GTFSRepository` es un actor compartido que carga el feed una vez y conserva el resultado. La ubicación y las posiciones de vehículos se consumen mediante `AsyncStream`.

### Datos y cálculo de rutas

El feed incluido contiene **102 rutas, 102 viajes, 4067 paraderos y 53 616 puntos de recorrido**. El repositorio relaciona agencias, rutas, viajes, shapes, paraderos, horarios, frecuencias y tarifas. El parser actual selecciona un viaje por ruta, de acuerdo con este feed.

- La geometría se encuentra en el área de Trujillo. Los metadatos de `feed_info.txt` aún identifican al publicador como «Arequipa Bus» y requieren revisión de procedencia y actualización; estos datos no acreditan operación en vivo. Procedencia, archivos que la aplicación lee realmente y comprobaciones pendientes están en `ThirdPartyNotices/GTFS/`.
- `MapaViewModel` calcula desde el GPS del usuario un itinerario de transporte GTFS con paraderos hasta 800 m de ambos extremos. Muestra caminatas punteadas, recorrido del bus continuo y marcadores de subida/bajada; si falta ubicación o no hay línea directa, muestra un aviso. Las caminatas usan Apple Directions y se identifican como aproximadas cuando ese servicio no responde.
- `TransitPlanner` busca una **línea directa** con paraderos próximos a ambos extremos y respeta el orden del recorrido. No calcula transbordos. Los tramos a pie se consultan con Apple Directions y tienen un respaldo aproximado.
- `PolylineMatching` proyecta el GPS sobre el recorrido para calcular avance y distancia a la ruta.
- El mapa principal tiene su propia simulación de buses; Tracking utiliza `SimulatedTrackingProvider`. `RealTrackingProvider` es un stub sin conexión a un servidor.

Los mapas base, las búsquedas y Apple Directions dependen de los servicios de Apple y de su disponibilidad de red y cobertura.

### Persistencia

Se usa `UserDefaults` para lugares, referencias de líneas, cupones, idioma, tema, modo de señas, preferencias de Perfil (notificaciones y compartir ubicación) y algunos datos personales. La foto de perfil se guarda en Documents mediante `ProfileImageStore`.

Los lugares guardados marcan el campus UTP con un campo `esFijo` persistido, no derivado del nombre: así la invariante «no se puede eliminar» sobrevive a cambios de texto. `LugaresStore` migra al cargar los datos guardados por versiones anteriores, que no traían ese campo.

El esquema de datos locales está versionado en `Services/Persistencia/Persistencia.swift`: una versión única y explícita, una lista ordenada de migraciones idempotentes y el inventario de llaves que la app considera suyas. `Persistencia.migrarSiHaceFalta()` se ejecuta una sola vez al arrancar, antes de que ninguna vista lea datos persistidos. Las llaves existentes **no** se renombran: renombrarlas perdería los datos ya guardados, así que el versionado se añade por encima.

No todo lo visible se persiste: parte del estado del perfil y de las pantallas sigue en `@State`; las reacciones comunitarias y sesiones de seguimiento permanecen en memoria. No hay autenticación ni sincronización entre dispositivos.

### Diseño, idiomas y señas

Los tokens visuales están en `Design/Colors.swift`, `Typography.swift` y `Spacing.swift`. Se utilizan SF Symbols.

La aplicación usa la **fuente del sistema**. Antes `Info.plist` declaraba Hanken Grotesk, Be Vietnam Pro y JetBrains Mono bajo `UIAppFonts`, pero sus `.ttf` nunca estuvieron en el repositorio: no había un solo archivo de fuente en el bundle compilado, así que la interfaz ya se veía con la fuente del sistema. Esa declaración se eliminó y los tokens de `Typography.swift` ahora usan `.system(size:weight:)` con los mismos tamaños y pesos, de modo que el aspecto no cambia. Los tokens son de tamaño fijo: recuperar el escalado de Dynamic Type requiere migrarlos a `@ScaledMetric`.

`IdiomaManager` persiste el idioma y `L.t` resuelve los textos español/inglés. El gestor es `@Observable`: cualquier vista que llame a `L.t()` en su `body` registra la dependencia y se actualiza sola, así que cambiar de idioma **no** reconstruye el árbol de vistas ni reinicia la pantalla en la que está el usuario. Las etiquetas que se guardan en propiedades almacenadas se resuelven al renderizar (o son propiedades calculadas) precisamente para no quedarse congeladas en el idioma de arranque.

El modo de señas relaciona claves estables con `senias/manifest.json` y busca vídeos en `senias/clips/es/` o `senias/clips/en/`. El reproductor vive en una ventana superpuesta para mostrarse también sobre formularios. Cuando falta un clip, muestra el estado pendiente. El manifiesto tiene 29 entradas; todavía faltan archivos para varias claves en ambos idiomas. Los botones señables muestran primero la tarjeta durante 3 segundos y luego ejecutan su acción una sola vez. Cerrar la tarjeta adelanta la acción; elegir otra acción o salir a otra pantalla cancela la anterior.

## Verificación y desarrollo

La compilación Debug para simulador se verificó durante la revisión del proyecto. Quedan advertencias de APIs obsoletas; no hay ninguna de concurrencia (`SWIFT_STRICT_CONCURRENCY = targeted`).

**Sobre iPad**: el proyecto declara `TARGETED_DEVICE_FAMILY = "1"` (solo iPhone). La interfaz está pensada para teléfono y el catálogo de iconos no incluía los tamaños que iPad exige (152 y 167 px); declarar soporte de iPad sin lo uno ni lo otro prometía una experiencia que no existe. Para dar soporte real hay que añadir esos iconos **y** maquetación de iPad.

El proyecto incluye el target de pruebas unitarias **RutaUTPTests**, que cubre el núcleo puro: `GTFSCSV`, `GTFSNombreParser`, `PolylineMatching`, `TransitItinerary.candidates`, la vigencia de cupones y `ParaderosIluminados.seleccionar`. Para ejecutarlo:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project RutaUTP.xcodeproj -scheme RutaUTP \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
```

No se prueban los ViewModels que leen `UserDefaults` directamente (`GuardadoViewModel`): hacerlo exigiría inyectar el almacén, y eso es un cambio de diseño, no una prueba.

En Debug se puede usar el argumento de lanzamiento `--pantalla` con `mapa`, `rutas`, `guardado`, `seguridad`, `perfil` o `tracking`. También existen argumentos específicos de algunas pantallas para abrir formularios y detalles; están documentados junto a sus hooks de depuración.

Para validar cambios funcionales, comprobar en simulador y, cuando corresponda, en un iPhone:

- Búsqueda, selección de destino, consulta del catálogo y navegación entre pestañas.
- Guardar y quitar lugares o líneas, y comprobar su persistencia al reiniciar.
- Permisos de ubicación concedidos y denegados, seguimiento y cancelación de viajes.
- Seguridad: abrir Añadir, seleccionar una foto de la biblioteca, cancelar el selector, quitar la imagen y tomar una foto en un dispositivo físico.
- Tema claro/oscuro, español/inglés y modo de señas con clips disponibles y pendientes.

La compilación por sí sola no verifica GPS, cámara, biblioteca de fotos ni cobertura de Apple Directions.

Los iconos de categorías de negocios y cupones usan **Uicons Regular Rounded de Flaticon**, incluidos como SVG locales. La atribución está en «Sobre nosotros» y la licencia y procedencia en `ThirdPartyNotices/Flaticon/`.

Comunidad incluye 24 publicaciones demo (6 con fotografías de referencia de Trujillo). Cada ventana muestra una publicación con foto y tres de texto. Créditos, fechas y enlaces a las licencias están en el detalle y en `ThirdPartyNotices/Comunidad/`. Las imágenes se incluyen en el bundle y se ven sin conexión.

La UTP Card del Perfil permite tomar una foto del carné o elegirla de la galería. Se guarda localmente en Documents (`utp-card.jpg`), separada de la foto de perfil, y se puede volver a abrir, ampliar o reemplazar. El estado «Carné guardado» confirma el almacenamiento, no una verificación universitaria.

Modo offline comprueba las rutas del feed incluido y muestra su cantidad real. No simula descargas ni cambia la conectividad del dispositivo. Los mapas base, búsquedas e indicaciones de Apple Maps no se garantizan sin internet.

Mis tarjetas permite añadir referencias, consultar su detalle, elegir una principal y eliminarlas con confirmación. Se guardan nombre, red y últimos cuatro dígitos en el llavero del dispositivo; no se almacenan números completos ni CVV y no se realizan cobros.

Antes de guardar la foto del carné, el editor permite moverla y ajustar el zoom dentro de un marco rectangular. «Guardar encuadre» conserva el recorte mostrado; cancelar mantiene la foto anterior. «Ajustar encuadre» permite volver a recortar la imagen guardada.

La foto de perfil usa el mismo editor con vista previa circular desde Datos Personales (Perfil y menú) y Carné Digital. Permite ajustar una foto nueva de cámara/galería o volver a encuadrar la actual; solo se reemplaza al confirmar el guardado.

El Carné Digital muestra un código de barras ampliado y el logo institucional UTP en monocromo al pie. La tarjeta de foto se identifica como «Carnet Universitario». Fuente del logo en `ThirdPartyNotices/UTP/`.
