# RutaUTP — Aplicacion Nativa SwiftUI

Esta carpeta contiene el codigo fuente 100% SwiftUI nativo de la app
**Ruta UTP Trujillo**, lista para reemplazar el prototipo WKWebView + HTML.

El prototipo HTML original se mantiene intacto en `../RutaUTP/` para
referencia visual y comparacion. Cuando compiles el proyecto Xcode,
apunta los archivos a esta carpeta `aplicacion real/`.

---

## Tabla de contenidos

1. [Descripcion general](#descripcion-general)
2. [Requisitos](#requisitos)
3. [Estructura del proyecto](#estructura-del-proyecto)
4. [Instalacion paso a paso](#instalacion-paso-a-paso)
5. [Configuracion de fuentes](#configuracion-de-fuentes)
6. [Design System](#design-system)
7. [Arquitectura y navegacion](#arquitectura-y-navegacion)
8. [Pantallas implementadas](#pantallas-implementadas)
9. [Modelos de datos](#modelos-de-datos)
10. [Reglas de implementacion](#reglas-de-implementacion)
11. [Animaciones](#animaciones)
12. [Accesibilidad](#accesibilidad)
13. [Solucion de problemas](#solucion-de-problemas)

---

## Descripcion general

Ruta UTP Trujillo es una aplicacion iOS orientada a estudiantes de la
Universidad Tecnologica del Peru (sede Trujillo) que necesitan movilizarse
desde distintos puntos de la ciudad hasta el campus usando transporte
publico (micros y combis).

Funcionalidades principales:
- Visualizacion del mapa con ubicacion del usuario y del campus UTP.
- Busqueda y seleccion de rutas en tiempo real.
- Detalle de ruta con tiempo, costo, transbordos y pasos guiados.
- Lugares guardados (Casa, UTP, etc.) y lineas favoritas.
- Reportes de la comunidad sobre trafico, alertas y sugerencias.
- Perfil con estadisticas de uso y preferencias configurables.

Stack tecnico:
- Swift 5.9+
- SwiftUI (iOS 16+)
- Navegacion con `ObservableObject` + `enum` propio (sin NavigationStack)
- Sin dependencias externas (cero paquetes de terceros)
- Sin conexion a internet: todos los datos son de muestra

---

## Requisitos

Para compilar y ejecutar la aplicacion necesitas:

- macOS Ventura (13.0) o superior
- Xcode 15.0 o superior
- iOS 16.0+ como target de despliegue
- Una cuenta de Apple ID (gratuita sirve para correr en simulador)
- Opcional: un dispositivo fisico iOS 16+ para probar animaciones y blur

---

## Estructura del proyecto

```
aplicacion real/
|
|-- RutaUTPApp.swift              Punto de entrada (@main)
|
|-- Navigation/
|   |-- AppRouter.swift           Enum AppScreen + clase AppRouter (ObservableObject)
|   `-- RootView.swift            Switch central entre pantallas con animacion
|
|-- Design/
|   |-- Colors.swift              Paleta completa (30+ tokens) + init Color(hex:)
|   |-- Typography.swift          Tokens tipograficos (Hanken, Be Vietnam, JetBrains)
|   |-- Spacing.swift             AppSpacing + AppRadius
|   `-- Components/
|       |-- BottomNavBar.swift    Barra inferior compartida
|       |-- TopAppBar.swift       Header reutilizable
|       `-- RouteCard.swift       Card horizontal de micro/combi
|
|-- Models/
|   |-- Ruta.swift                Modelo Ruta + TipoVehiculo
|   |-- LugarGuardado.swift       LugarGuardado + LineaGuardada + CategoriaLugar
|   `-- ReporteComunidad.swift    ReporteComunidad + TipoReporte
|
|-- Screens/
|   |-- Bienvenida/
|   |   `-- BienvenidaView.swift         Pantalla de presentacion
|   |-- Mapa/
|   |   |-- MapaView.swift               Pantalla principal
|   |   `-- SideDrawer.swift             Drawer lateral del mapa
|   |-- DetalleRuta/
|   |   `-- DetalleRutaView.swift        Detalle de la ruta seleccionada
|   |-- Guardado/
|   |   `-- GuardadoView.swift           Lugares y lineas guardadas
|   |-- Seguridad/
|   |   `-- SeguridadView.swift          Resumen, lugares, rutas y comunidad
|   `-- Perfil/
|       `-- PerfilView.swift             Perfil y preferencias
|
|-- Resources/
|   `-- Info.plist                UIAppFonts + orientacion + launch screen
|
`-- README.md                     Este archivo
```

Total: 21 archivos Swift + 1 Info.plist + 1 README.

---

## Instalacion paso a paso

### Opcion A: Crear un proyecto Xcode desde cero

1. Abre Xcode y selecciona **File > New > Project...**
2. En la plantilla **iOS** elige **App** y presiona **Next**.
3. Completa los campos:
   - Product Name: `RutaUTP`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Presiona **Next** y elige una ubicacion (por ejemplo, junto a esta
     carpeta `aplicacion real/`).
4. En el Finder, abre la carpeta del proyecto nuevo y **arrastra toda la
   carpeta `aplicacion real/`** dentro del grupo raiz del proyecto Xcode.
5. En el dialogo que aparece, marca:
   - **Copy items if needed**: activado
   - **Create groups**: seleccionado
   - **Add to targets**: `RutaUTP`
   - Presiona **Finish**.
6. En el panel izquierdo de Xcode, selecciona el archivo
   `RutaUTPApp.swift` generado automaticamente por Xcode y **borralo**
   (clic derecho > Move to Trash). Ya tenemos el nuestro.
7. Asegurate de que el target `RutaUTP` ahora compila con nuestros
   archivos. Compilacion rapida: **Cmd + B**.
8. Ejecuta en un simulador iOS 16+ con **Cmd + R**.

### Opcion B: Reemplazar el proyecto Xcode existente

El proyecto actual (`../RutaUTP.xcodeproj`) usa WKWebView. Para migrarlo:

1. Abre `RutaUTP.xcodeproj` en Xcode.
2. En el navegador de proyectos, **elimina los archivos antiguos** del
   target `RutaUTP` (los .swift del WebView y los .html).
   - NO elimines `Assets.xcassets` ni los iconos.
3. Arrastra la carpeta `aplicacion real/` al proyecto (mismos checks que
   en Opcion A).
4. Ve a **Target > RutaUTP > Info** y verifica que las claves
   `UIAppFonts` y `UISupportedInterfaceOrientations` coincidan con las de
   `Resources/Info.plist`. Si tu Info.plist es autogenerado por Xcode,
   copia las claves manualmente desde nuestro `Info.plist`.
5. Compila con **Cmd + B** y corre con **Cmd + R**.

### Verificacion post-instalacion

Despues de la primera compilacion exitosa:

- La app abre directamente en la pantalla **Bienvenida**.
- Toca **Comenzar** y deberias llegar al **Mapa** con el drawer lateral
  funcional al tocar el boton de menu.
- La barra inferior debe mostrar 5 tabs (Mapa, Rutas, Guardado,
  Seguridad, Perfil) y el tab activo debe tener fondo `primaryContainer`.
- Toca cualquier card de micro en el mapa para abrir el **Detalle de Ruta**.
- En **Guardado**, el boton `+ Anadir` debe abrir un sheet en la mitad
  inferior de la pantalla.
- En **Seguridad**, el boton flotante inferior derecho debe tener
  animacion de presion.
- En **Perfil**, los toggles deben animarse al alternarlos.

---

## Configuracion de fuentes

La aplicacion usa 3 familias tipograficas. Si NO agregas las fuentes, la
app hace **fallback automatico a `.system`** y sigue compilando y
funcionando; solo cambiara la apariencia de los textos.

### Familias requeridas

| Familia         | PostScript name   | Pesos usados              | Origen                      |
|-----------------|-------------------|---------------------------|-----------------------------|
| Hanken Grotesk  | `HankenGrotesk`   | Regular, Bold, ExtraBold  | Google Fonts                |
| Be Vietnam Pro  | `BeVietnamPro`    | Regular, Medium, SemiBold | Google Fonts                |
| JetBrains Mono  | `JetBrainsMono`   | Regular, SemiBold         | JetBrains                   |

### Como agregar las fuentes al proyecto

1. Descarga los archivos `.ttf` de los tres sitios oficiales.
2. Arrastra los `.ttf` al navegador de proyectos de Xcode.
3. Marca **Add to target: RutaUTP**.
4. Confirma que aparecen en **Build Phases > Copy Bundle Resources**.
5. El archivo `Resources/Info.plist` ya incluye las entradas de
   `UIAppFonts`. Si usas un Info.plist autogenerado por Xcode, copia
   las claves correspondientes.
6. Limpia el build folder con **Product > Clean Build Folder**
   (Shift + Cmd + K) y vuelve a compilar.

### Verificacion

Si las fuentes cargan correctamente:
- Los titulos de Bienvenida se ven mas anchos y compactos.
- Los labels UPPERCASE tienen tipografia monoespaciada.
- El body usa una sans-serif con terminales humanistas.

Si ves la tipografia del sistema por defecto, revisa:
- Que los archivos esten en **Copy Bundle Resources**.
- Que `UIAppFonts` liste exactamente los nombres PostScript correctos.
- Que no haya espacios extra o mayusculas/minusculares mal en el plist.

---

## Design System

### Paleta de colores

Tokens principales definidos en `Design/Colors.swift`:

| Token                   | Hex       | Uso                                     |
|-------------------------|-----------|-----------------------------------------|
| `appPrimary`            | `#a80033` | Rojo UTP, CTAs principales              |
| `primaryContainer`      | `#d31245` | Estados activos, badges, tabs           |
| `onPrimaryContainer`    | `#ffe8e8` | Texto sobre `primaryContainer`          |
| `secondary`             | `#3c5d9c` | Combi, congestion                       |
| `secondaryContainer`    | `#99b8fe` | Badges combi, marcador de usuario       |
| `tertiary`              | `#005b6e` | Seguridad, frecuente                    |
| `tertiaryContainer`     | `#00758d` | Badges de tiempo en lineas              |
| `appBackground`         | `#f7f9fb` | Fondo general                           |
| `surfaceContainerLowest`| `#ffffff` | Cards elevadas                          |
| `surfaceContainer`      | `#eceef0` | Cards de baja elevacion, summary bar    |
| `outlineVariant`        | `#e4bdbf` | Bordes sutiles                          |
| `onSurface`             | `#191c1e` | Texto principal                         |
| `onSurfaceVariant`      | `#5c3f41` | Texto secundario                        |
| `appError`              | `#ba1a1a` | Errores                                 |
| `errorContainer`        | `#ffdad6` | Fondo de badges de alerta               |

### Tipografia

Definida en `Design/Typography.swift`. Familias:

- **Hanken Grotesk** para titulares (`headlineLgMobile`, `headlineSm`).
- **Be Vietnam Pro** para cuerpo (`bodyMd`, `bodySm`).
- **JetBrains Mono** para labels UPPERCASE con tracking ancho
  (`labelCapsMd`).

Aplicar tracking ancho:

```swift
Text("REPORTAR")
    .font(.labelCapsMd)
    .appTracking(AppTracking.wideLabel)
```

### Espaciados y radios

Tokens definidos en `Design/Spacing.swift`:

- `AppSpacing.stackGap` = 12
- `AppSpacing.gutter` = 16
- `AppSpacing.containerPadding` = 20
- `AppSpacing.touchTargetMin` = 48
- `AppRadius.medium` = 8
- `AppRadius.large` = 12
- `AppRadius.xl` = 16
- `AppRadius.card` = 20
- `AppRadius.cardLarge` = 26
- `AppRadius.pill` = 9999

### Iconografia

Todos los iconos usan **SF Symbols** nativos. Mapeo principal:

| Material Symbol        | SF Symbol                          |
|------------------------|------------------------------------|
| `directions_bus`       | `bus.fill`                         |
| `shield_with_heart`    | `heart.shield.fill`                |
| `payments`             | `creditcard.fill`                  |
| `arrow_forward`        | `arrow.right`                      |
| `arrow_back`           | `arrow.left`                       |
| `map`                  | `map.fill`                         |
| `bookmark`             | `bookmark.fill`                    |
| `person`               | `person.fill`                      |
| `school`               | `graduationcap.fill`               |
| `home`                 | `house.fill`                       |
| `search`               | `magnifyingglass`                  |
| `location_on`          | `mappin.and.ellipse`               |
| `schedule`             | `clock.fill`                       |
| `navigation`           | `location.fill`                    |
| `menu`                 | `line.3.horizontal`                |
| `campaign`             | `megaphone.fill`                   |
| `report`               | `exclamationmark.triangle.fill`    |
| `verified_user`        | `checkmark.shield.fill`            |
| `groups`               | `person.3.fill`                    |
| `thumb_up`             | `hand.thumbsup.fill`               |
| `chat_bubble`          | `bubble.left.fill`                 |
| `night_shelter`        | `moon.zzz.fill`                    |
| `visibility`           | `eye.fill`                         |
| `logout`               | `rectangle.portrait.and.arrow.right` |
| `notifications`        | `bell.fill`                        |
| `settings`             | `gearshape.fill`                   |
| `info`                 | `info.circle.fill`                 |
| `support_agent`        | `headphones`                       |
| `person_pin_circle`    | `figure.walk.circle.fill`          |
| `lightbulb`            | `lightbulb.fill`                   |
| `today`                | `calendar`                         |
| `edit`                 | `pencil`                           |
| `add`                  | `plus`                             |

---

## Arquitectura y navegacion

La navegacion NO usa `NavigationStack` ni `NavigationLink`. Toda la
transicion entre pantallas pasa por un `AppRouter` central.

### Componentes

1. **`AppScreen`** (enum) lista las pantallas posibles:
   - `bienvenida`
   - `mapaPrincipal`
   - `detalleRuta`
   - `guardado`
   - `seguridad`
   - `perfil`

2. **`AppRouter`** (clase `ObservableObject`):
   - `@Published var currentScreen: AppScreen`
   - `func navigate(to: AppScreen)` anima la transicion.

3. **`RootView`** hace `switch` sobre `router.currentScreen` y monta la
   vista correspondiente. Toda la app se anima con
   `.animation(.easeInOut(duration: 0.25), value: router.currentScreen)`.

### Diagrama de transiciones

```
Bienvenida  ->  Mapa
                  |
                  +->  DetalleRuta  ->  Mapa
                  |
                  +->  Guardado
                  +->  Seguridad
                  +->  Perfil
```

### Como navegar desde una vista

```swift
@EnvironmentObject private var router: AppRouter

Button("Ir al mapa") {
    router.navigate(to: .mapaPrincipal)
}
```

El `AppRouter` se inyecta automaticamente en `RootView` con
`.environmentObject(router)`.

### BottomNavBar como overlay

La barra inferior es una vista independiente que **no** usa `TabView`.
Se renderiza como `VStack { Spacer(); BottomNavBar() }` dentro de un
`ZStack`, de modo que flota sobre el contenido sin alterar el layout.

El tab activo se calcula en funcion de `router.currentScreen`:

```swift
private var activeTab: NavTab? {
    switch router.currentScreen {
    case .mapaPrincipal, .detalleRuta: return .mapa
    case .guardado:                    return .guardado
    case .seguridad:                   return .seguridad
    case .perfil:                      return .perfil
    case .bienvenida:                  return nil
    }
}
```

---

## Pantallas implementadas

### 1. Bienvenida

Archivo: `Screens/Bienvenida/BienvenidaView.swift`

Secciones (de arriba a abajo):
- Barra de progreso decorativa (gradiente 4pt alto).
- Header con titulo **Ruta UTP Trujillo** y boton **Saltar**.
- Card **LLEGANDO EN 3 min** con icono de bus rojo.
- Imagen de bus (placeholder con SF Symbol si no hay asset).
- Hero text **Llega a la UTP sin perderte**.
- Indicadores de pagina (3 dots).
- Grid 2x1 con cards de **Seguridad** y **Ahorro**.
- Boton CTA **Comenzar** full-width.
- Footer legal con enlace a Terminos.

CTA primario navega a `.mapaPrincipal`.

### 2. Mapa

Archivo: `Screens/Mapa/MapaView.swift` + `Screens/Mapa/SideDrawer.swift`

Elementos:
- Header con boton de menu y titulo **Mapa**.
- Fondo decorativo con "calles" estilizadas en `Path`.
- Marcador del usuario con animacion ping.
- Marcador de UTP con pill **UTP Trujillo** y graduation cap.
- Panel de busqueda flotante con `ultraThinMaterial`.
- Chips horizontales de destino (Casa / UTP / Trabajo).
- Pill **REPORTAR** inferior izquierdo.
- Titulo **Transportes cercanos** + badge **En vivo**.
- Scroll horizontal con cards de micros (Línea 10, 4, 7).
- SideDrawer animado con spring, swipe-to-close, 5 items + logout.

Tocar una card de micro navega a `.detalleRuta`.

### 3. Detalle de Ruta

Archivo: `Screens/DetalleRuta/DetalleRutaView.swift`

Secciones:
- Header con back, icono de bus y titulo **Rutas**.
- Hero mapa (353pt alto) con gradiente y ruta punteada.
- Badge **RUTA SEGURA** en esquina superior derecha.
- Card de detalle con overlap -32pt sobre el mapa.
- Bento grid 2x2 con stats (Tiempo, Costo, Transbordos, Congestion).
- **Guia paso a paso** con 3 nodos (Caminar, Bus, Destino) y linea
  conectora vertical.
- CTA **Iniciar Navegacion** full-width con icono `location.fill`.

### 4. Guardado

Archivo: `Screens/Guardado/GuardadoView.swift`

Elementos:
- Header con icono `bookmark.fill` + titulo **Guardado** + boton
  **+ Anadir** (pill `primaryContainer`).
- Tabs segmento **Lugares** / **Lineas** con underline animado.
- Lista de lugares (6 lugares de muestra) con icono circular, badge
  FRECUENTE en UTP, chevron a la derecha.
- Lista de lineas (B, 7, C) con badge de tiempo en `tertiary`.
- Sheet **Guardar lugar** (`.presentationDetents([.medium])`) con
  campos nombre y direccion.

Tocar un lugar navega a `.mapaPrincipal`.

### 5. Seguridad

Archivo: `Screens/Seguridad/SeguridadView.swift`

Secciones:
- Header con `heart.shield.fill` + titulo **Seguridad**.
- **Summary bar** sticky con contadores y botones Denunciar / Llamar 105.
- **Greeting card** con saludo dinamico (Buenos dias / tardes / noches)
  y fecha actual en espanol.
- **Lugares Guardados** grid 3x1 (Casa, UTP, Anadir) con bordes
  punteados en el placeholder.
- **Rutas Seguras Hoy** con imagen de mapa nocturno (192pt), gradiente
  superpuesto, y label "Paraderos iluminados activos: 24".
- Lista de rutas seguras con borde izquierdo de acento (`tertiary`).
- **Comunidad** con 2 reportes de muestra y chips de util/comentarios.
- **FAB** flotante (megaphone) en `bottom: 90pt, trailing: 24pt`.

### 6. Perfil

Archivo: `Screens/Perfil/PerfilView.swift`

Elementos:
- Hero gradient banner (220pt) con avatar de iniciales **JD**, nombre
  **Joaquin Diaz** y badge de rol.
- Card de stats (47 viajes, 12 rutas, 3 logros) con divisores.
- Seccion **Preferencias** con 3 toggles y 2 chevron rows.
- Sheet **Editar perfil** para cambiar el nombre.

---

## Modelos de datos

### Ruta

```swift
struct Ruta: Identifiable, Equatable {
    let id: String
    let linea: String           // "LINEA 10"
    let nombre: String          // "El Cortijo"
    let empresa: String         // "Salaverry"
    let tipo: TipoVehiculo      // .micro | .combi | .bus
    let placa: String           // "T1B-721"
    let minutosLlegada: Int
    let colorIdentificador: Color
}
```

### LugarGuardado

```swift
struct LugarGuardado: Identifiable, Equatable {
    let id: UUID
    var nombre: String
    var direccion: String
    var categoria: CategoriaLugar
    var esFrecuente: Bool
    var colorBadge: Color
}
```

### ReporteComunidad

```swift
struct ReporteComunidad: Identifiable, Equatable {
    let id: UUID
    let iniciales: String       // "JD"
    let nombre: String          // "Jorge D."
    let hace: String            // "HACE 5 MIN"
    let tipo: TipoReporte       // .alerta | .trafico | .sugerencia | .otro
    let cuerpo: String
    let utiles: Int
    let comentarios: Int
    let utilMarcado: Bool
    let avatarColor: Color
    let avatarForeground: Color
}
```

Todos los modelos son `Equatable` para facilitar previews y testing.

---

## Reglas de implementacion

Reglas seguidas durante el desarrollo (verificables en el codigo):

- Cero `import WebKit` en todo el proyecto.
- Cero `NavigationStack` y `NavigationLink`.
- `BottomNavBar` es un overlay flotante, no usa `tabItem` de `TabView`.
- Las imagenes del mapa son placeholders generados con `Path` o
  `LinearGradient` (no se bloquea el hilo principal descargando URLs).
- `ScrollView` con `showsIndicators: false` en todas las listas.
- El tab activo en `BottomNavBar` se deriva de `router.currentScreen`,
  no de un `@State` local.
- Cada `View` tiene su `#Preview` con un `AppRouter` de muestra.
- `.accessibilityLabel()` en todos los botones que solo muestran icono.
- Colores consumidos unicamente desde `Color.appPrimary`, etc., nunca
  hex inline.
- Safe area respetada en header y navbar.

---

## Animaciones

| Elemento                      | Animacion                                           |
|-------------------------------|-----------------------------------------------------|
| Cambio de pantalla            | `.easeInOut(duration: 0.25)` en el switch global    |
| Boton CTA presionado          | `scaleEffect(0.95)` con spring 0.2                 |
| Boton FAB                     | `scaleEffect(0.92)` con spring 0.2                 |
| SideDrawer open / close       | `.spring(response: 0.28, dampingFraction: 0.85)`   |
| Marcador de usuario (ping)    | `scaleEffect` 1.0 a 1.6, opacidad 1.0 a 0, infinite |
| Toggle switch                 | `withAnimation(.easeInOut(duration: 0.2))`          |
| Tabs Lugares / Lineas         | Underline animado con `easeInOut` 0.2              |

---

## Accesibilidad

- `.accessibilityLabel()` en todos los botones de icono (menu, back,
  reportar, megaphone, add, chevron, etc.).
- Familias de fuente claras y con peso distinguible.
- Contraste AA cumplido en todas las combinaciones de texto.
- Touch targets minimo 44pt (la mayoria son 48pt+).
- Roles visuales diferenciados (icono + texto + color).

---

## Solucion de problemas

### La app no compila por errores de tipo `Cannot find 'X' in scope`

Verifica que todos los archivos `.swift` de la carpeta `aplicacion real/`
esten agregados al **target de compilacion** del proyecto Xcode. En el
navegador de proyectos, selecciona cada archivo y revisa el panel
**File Inspector** (icono de hoja) a la derecha. La casilla bajo
**Target Membership** debe tener `RutaUTP` marcado.

### Las fuentes no se ven diferentes a las del sistema

1. Confirma que los archivos `.ttf` estan en **Copy Bundle Resources**
   (Build Phases del target).
2. Verifica que `Resources/Info.plist` (o las claves mergeadas en tu
   Info.plist) lista los nombres **PostScript** correctos, no los
   nombres de archivo.
3. Limpia el build folder (**Shift + Cmd + K**) y vuelve a compilar.
4. Si aun no funciona, fuerza reinicio del simulador
   (**Device > Erase All Content and Settings**).

### El SideDrawer no se abre al tocar el menu

Asegurate de que la vista este observando la notificacion
`.openSideDrawer`. Esto ya esta implementado en `MapaView.onReceive`.
Si lo moviste, agrega el observer de nuevo o llama a
`SideDrawer(isOpen: $drawerOpen)` directamente desde un `@State`.

### El BottomNavBar no aparece en una pantalla

Revisa que la vista tenga la siguiente estructura:

```swift
ZStack {
    // contenido
    VStack {
        Spacer()
        BottomNavBar()
    }
}
```

Las pantallas que ya lo incluyen son: Mapa, DetalleRuta, Guardado,
Seguridad y Perfil.

### Los `presentationDetents` no funcionan

`presentationDetents` requiere iOS 16+. Si tu target es iOS 15 o
anterior, actualiza el deployment target en **Target > General >
Minimum Deployments**.

### Quiero anadir una pantalla nueva

1. Agrega un caso al enum `AppScreen` en `Navigation/AppRouter.swift`.
2. Crea el archivo `Screens/Nombre/NombreView.swift`.
3. Agrega el `case` correspondiente en el `switch` de
   `Navigation/RootView.swift`.
4. Si quieres que aparezca en la barra inferior, agrega el caso a
   `NavTab` en `Design/Components/BottomNavBar.swift`.

### Quiero cambiar los colores globalmente

Todos los colores viven en `Design/Colors.swift`. Modifica el `hex` y
todos los consumidores se actualizan automaticamente. Manten el orden
de los tokens (Primarios, Secundarios, Terciarios, Superficie,
On-Surface, Outline, Error) para no romper la consistencia.

---

## Licencia y creditos

Codigo generado para el proyecto academico **RutaUTP** del curso de
Productos y Servicios (ciclo 7), a partir del prototipo HTML original
de JDiazD33.

- Iconografia: SF Symbols de Apple (uso libre).
- Tipografias: Hanken Grotesk y Be Vietnam Pro (Google Fonts, SIL
  Open Font License), JetBrains Mono (Apache 2.0).
- Paleta inspirada en Material Design 3 adaptada a la identidad UTP.
