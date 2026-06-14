# Ruta UTP Trujillo

Aplicacion iOS para orientar a estudiantes de la Universidad Tecnologica
del Peru (sede Trujillo) en sus traslados en transporte publico desde
distintos puntos de la ciudad hasta el campus.

Este repositorio contiene **dos implementaciones** de la misma aplicacion:

1. **Prototipo original (WKWebView + HTML)** en `RutaUTP/`. Sirve como
   referencia visual rapida: cada pantalla es un archivo HTML servido
   dentro de un `WKWebView`.
2. **Version nativa SwiftUI 100%** en `aplicacion real/`. Es la
   implementacion de produccion: 21 archivos Swift, sin HTML, sin
   WebView, con todos los componentes, animaciones y navegacion hechos
   en SwiftUI puro.

Ambas versiones comparten el mismo Design System (paleta, tipografia,
iconografia, espaciados).

---

## Tabla de contenidos

1. [Comparacion de las dos implementaciones](#comparacion-de-las-dos-implementaciones)
2. [Cual usar](#cual-usar)
3. [Requisitos](#requisitos)
4. [Estructura del proyecto](#estructura-del-proyecto)
5. [Como abrir en Xcode](#como-abrir-en-xcode)
6. [Como compilar y ejecutar](#como-compilar-y-ejecutar)
7. [Prototipo WKWebView (HTML)](#prototipo-wkwebview-html)
8. [Version nativa SwiftUI](#version-nativa-swiftui)
9. [Design System](#design-system)
10. [Navegacion](#navegacion)
11. [Solucion de problemas](#solucion-de-problemas)

---

## Comparacion de las dos implementaciones

| Aspecto                 | Prototipo WKWebView           | Version Nativa SwiftUI          |
|-------------------------|-------------------------------|---------------------------------|
| Tecnologia              | HTML + CSS + JS + WKWebView   | SwiftUI 100%                    |
| Lineas de codigo        | ~800 HTML + ~50 Swift        | ~2,500 Swift                    |
| Tiempo de carga        | Carga el HTML al iniciar     | Instantaneo                     |
| Animaciones            | CSS transitions               | SwiftUI animations + springs    |
| Acceso al hardware     | Limitado                      | Completo (GPS, mapas, etc.)     |
| App Store              | No publicable                 | Lista para publicar             |
| Codigo duplicado        | HTML + Swift para bridge      | Solo Swift                      |
| Dependencias externas   | Google Fonts (CSS)            | SF Symbols (sistema)            |
| Targets iOS             | iOS 14+                       | iOS 16+                         |

---

## Cual usar

- Si solo quieres **ver el diseno rapido** sin compilar: abre los archivos
  HTML directamente en un navegador o usa la opcion Live Preview del
  prototipo.
- Si quieres **desarrollar la app real** (recomendado): usa la version
  SwiftUI nativa en `aplicacion real/`. Es la base sobre la que se
  construiran las siguientes iteraciones.
- Si quieres **mantener el puente JS-Swift** por motivos de
  retrocompatibilidad o por restricciones del proyecto, conserva el
  prototipo WKWebView.

---

## Requisitos

Para cualquiera de las dos versiones:

- macOS Ventura (13.0) o superior
- Xcode 15.0 o superior
- Cuenta de Apple ID (gratuita sirve para correr en simulador)
- Para la version SwiftUI: iOS 16+ como target
- Para el prototipo WKWebView: iOS 14+ como target

---

## Estructura del proyecto

```
RutaUTP/                                       Raiz del proyecto
|
|-- RutaUTP.xcodeproj/                         Proyecto Xcode (apunta a la version WKWebView)
|   `-- project.pbxproj
|
|-- RutaUTP/                                   Prototipo WKWebView (HTML + Swift bridge)
|   |-- RutaUTPApp.swift                       Entry point
|   |-- ContentView.swift                      Switch entre WebViews
|   |-- WebScreenView.swift                    WKWebView + interceptor app://
|   |-- bienvenida.html                        Pantalla 1: Onboarding
|   |-- mapa_principal.html                    Pantalla 2: Mapa principal
|   |-- seguridad.html                         Pantalla 3: Seguridad y guardados
|   |-- detalle_ruta.html                      Pantalla 4: Detalle de ruta
|   |-- guardado.html                          Pantalla 5: Lugares guardados
|   |-- perfil.html                            Pantalla 6: Perfil
|   |-- bus.png                                Asset de imagen
|   `-- Assets.xcassets/                       Iconos y assets
|
|-- aplicacion real/                           Version nativa SwiftUI (sin WKWebView)
|   |-- README.md                              Documentacion detallada de la version SwiftUI
|   |-- RutaUTPApp.swift                       Entry point (@main)
|   |-- Navigation/
|   |   |-- AppRouter.swift                    Enum AppScreen + ObservableObject
|   |   `-- RootView.swift                     Switch animado de pantallas
|   |-- Design/
|   |   |-- Colors.swift                       30+ tokens de color + init Color(hex:)
|   |   |-- Typography.swift                   3 familias tipograficas
|   |   |-- Spacing.swift                      AppSpacing + AppRadius
|   |   `-- Components/
|   |       |-- BottomNavBar.swift             Barra inferior compartida
|   |       |-- TopAppBar.swift                Header reutilizable
|   |       `-- RouteCard.swift                Card de micro horizontal
|   |-- Models/
|   |   |-- Ruta.swift
|   |   |-- LugarGuardado.swift
|   |   `-- ReporteComunidad.swift
|   |-- Screens/
|   |   |-- Bienvenida/BienvenidaView.swift
|   |   |-- Mapa/MapaView.swift
|   |   |-- Mapa/SideDrawer.swift
|   |   |-- DetalleRuta/DetalleRutaView.swift
|   |   |-- Guardado/GuardadoView.swift
|   |   |-- Seguridad/SeguridadView.swift
|   |   `-- Perfil/PerfilView.swift
|   `-- Resources/
|       `-- Info.plist                         UIAppFonts + orientacion
|
`-- README.md                                  Este archivo
```

---

## Como abrir en Xcode

1. Abre Xcode.
2. Selecciona **File > Open...** (o **Open a project or file** desde la
   pantalla de bienvenida).
3. Selecciona la carpeta `RutaUTP/` que contiene el archivo
   `RutaUTP.xcodeproj`.
4. Xcode detectara el proyecto automaticamente y lo abrira en el editor.

Si solo quieres trabajar con la version SwiftUI nativa, puedes crear un
proyecto nuevo (ver seccion [Version nativa SwiftUI](#version-nativa-swiftui)).

---

## Como compilar y ejecutar

### Para el prototipo WKWebView

1. Abre el proyecto `RutaUTP.xcodeproj` en Xcode.
2. En la barra superior, selecciona un destino:
   - **Simulador**: cualquier iPhone con iOS 14 o superior (recomendado
     iPhone 14 Pro para mejor visualizacion).
   - **Dispositivo fisico**: conecta tu iPhone por USB y confia en el
     equipo.
3. Si Xcode pide firma:
   - Ve a **Signing & Capabilities**.
   - Activa **Automatically manage signing**.
   - Selecciona tu **Team** (tu Apple ID personal funciona en modo
     desarrollo).
4. Presiona **Cmd + R** o el boton de play (run) en la barra superior.
5. Si ejecutas en un dispositivo fisico, la primera vez pedira que
   confies en el developer:
   - Abre **Ajustes > General > VPN y gestion de dispositivos** en el
     iPhone.
   - Toca el perfil de tu Apple ID y selecciona **Confiar**.

### Para la version nativa SwiftUI

1. Crea un proyecto Xcode nuevo (ver
   [Version nativa SwiftUI](#version-nativa-swiftui)).
2. Arrastra la carpeta `aplicacion real/` al proyecto.
3. Compila con **Cmd + B** y ejecuta con **Cmd + R**.

---

## Prototipo WKWebView (HTML)

Esta implementacion sirve como prototipo rapido y referencia visual.
Cada pantalla es un archivo HTML independiente que se carga dentro de
un `WKWebView` por medio de `WebScreenView.swift`.

### Archivos principales

- `RutaUTP/RutaUTPApp.swift`: entry point de la app.
- `RutaUTP/ContentView.swift`: switch entre las 4 `WebScreenView`.
- `RutaUTP/WebScreenView.swift`: `WKWebView` que carga un HTML y
  expone un puente JS-Swift.

### Como funciona el puente JS a Swift

Cada HTML dispara navegacion con este patron:

```javascript
window.location.href = 'app://navigate/mapa_principal';
```

`WebScreenView.swift` implementa el delegado de navegacion del
`WKWebView`. Cuando detecta una URL con esquema `app://`, la intercepta
y llama al callback `onNavigate(destination)` con el nombre de la
pantalla. `ContentView.swift` actualiza el `@State` que controla el
switch de pantallas.

### Como agregar una pantalla al prototipo

1. Crea el archivo HTML en `RutaUTP/` con el patron `app://` para
   navegar.
2. Arrastra el HTML al grupo `RutaUTP` en Xcode. Marca
   **Copy items if needed** y **Add to target: RutaUTP**.
3. Agrega un caso al enum `AppScreen` en `RutaUTP/ContentView.swift`.
4. Agrega el `case` en el `switch` y en la funcion `navigate(to:)`.

---

## Version nativa SwiftUI

La version de produccion vive en `aplicacion real/`. Toda la
documentacion detallada (instalacion, configuracion, design system,
modelos, troubleshooting) esta en
[`aplicacion real/README.md`](aplicacion%20real/README.md).

### Resumen rapido

- 21 archivos Swift organizados por capas: `Navigation`, `Design`,
  `Models`, `Screens`, `Resources`.
- 6 pantallas: Bienvenida, Mapa (con SideDrawer), Detalle de Ruta,
  Guardado, Seguridad, Perfil.
- Navegacion centralizada en `AppRouter` (sin `NavigationStack`).
- `BottomNavBar` como overlay flotante, no como `TabView`.
- Cero dependencias externas, cero `import WebKit`.

### Crear un proyecto Xcode para la version SwiftUI

1. **File > New > Project...** en Xcode.
2. Plantilla: **iOS > App**. Presiona **Next**.
3. Configuracion:
   - Product Name: `RutaUTPNative`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Presiona **Next** y elige la ubicacion.
4. En el Finder, arrastra la carpeta `aplicacion real/` al proyecto
   Xcode.
   - Marca **Copy items if needed**.
   - Selecciona **Create groups**.
   - Marca **Add to targets: RutaUTPNative**.
5. Borra el `ContentView.swift` autogenerado (ya tenemos el nuestro).
6. **Cmd + B** para compilar. **Cmd + R** para ejecutar.

Para detalles completos (configuracion de fuentes, troubleshooting,
como agregar pantallas, paleta de colores) consulta
[`aplicacion real/README.md`](aplicacion%20real/README.md).

---

## Design System

Ambas implementaciones comparten la misma identidad visual. Los
colores y tokens viven como codigo en `aplicacion real/Design/` y como
variables CSS en los archivos HTML del prototipo.

### Paleta principal

| Token             | Hex       | Uso                                     |
|-------------------|-----------|-----------------------------------------|
| Rojo UTP          | `#a80033` | CTAs principales, marca                 |
| Rojo container    | `#d31245` | Estados activos, badges, tabs           |
| Azul              | `#3c5d9c` | Combi, congestion                       |
| Teal              | `#005b6e` | Seguridad, badge FRECUENTE              |
| Fondo             | `#f7f9fb` | Background general                      |
| Superficie        | `#ffffff` | Cards elevadas                          |
| Texto principal   | `#191c1e` | Body y titulos                          |
| Texto secundario  | `#5c3f41` | Labels y subtitulos                     |
| Outline           | `#e4bdbf` | Bordes sutiles                          |

### Tipografia

- **Hanken Grotesk**: titulares y numeros grandes (32-42px, 700-800).
- **Be Vietnam Pro**: cuerpo y parrafos (14-20px, 400-500).
- **JetBrains Mono**: labels UPPERCASE con tracking ancho (12-14px,
  600, tracking 0.05-0.20em).

### Iconografia

Todos los iconos del prototipo HTML son Material Symbols. En la
version SwiftUI se mapean a SF Symbols nativos del sistema. La tabla
completa de mapeo esta en `aplicacion real/README.md`.

---

## Navegacion

### Flujo del prototipo WKWebView

```
Bienvenida
    | "Comenzar" o "Saltar"
    v
Mapa Principal
    | navbar "Guardado" / "Seguridad"
    v
Seguridad y Guardados
    | navbar "Mapa"
    +--------------------+
    v                    |
Mapa Principal          |
    |                    |
    | card de ruta       |
    v                    |
Detalle de Ruta         |
    | boton back         |
    +------------------- +
```

### Flujo de la version SwiftUI

```
Bienvenida  -->  Mapa
                   |
                   +--> Detalle de Ruta  --> Mapa
                   |
                   +--> Guardado
                   +--> Seguridad
                   +--> Perfil
```

Toda transicion usa `router.navigate(to:)` con animacion
`easeInOut(duration: 0.25)`.

---

## Solucion de problemas

### La app no compila: "Cannot find 'X' in scope"

Verifica que todos los archivos Swift de la carpeta correspondiente
esten en el **target de compilacion**. En Xcode, selecciona cada
archivo y revisa el panel **File Inspector** (icono de hoja a la
derecha). La casilla bajo **Target Membership** debe estar marcada.

### "Failed to instantiate the default view controller"

Limpia el build folder: **Product > Clean Build Folder**
(Shift + Cmd + K). Luego **Cmd + R** de nuevo.

### El simulador muestra pantalla negra

Abre **Device > Erase All Content and Settings** en el menu del
simulador y reinicia. Si persiste, cierra y reabre Xcode.

### El prototipo WKWebView no navega al tocar un boton

Abre el archivo HTML correspondiente y verifica que el boton use el
patron `window.location.href = 'app://navigate/...';` y no `onclick`
con codigo JS arbitrario. El esquema `app://` es el unico que el
`WKWebView` intercepta.

### Quiero pasar del prototipo WKWebView a la version SwiftUI

Sigue los pasos de la seccion
[Version nativa SwiftUI](#version-nativa-swiftui). La carpeta
`aplicacion real/` es independiente del proyecto Xcode existente; no
rompe nada.

### Quiero anadir una pantalla nueva a la version SwiftUI

1. Agrega un caso al enum `AppScreen` en
   `aplicacion real/Navigation/AppRouter.swift`.
2. Crea el archivo `aplicacion real/Screens/Nombre/NombreView.swift`.
3. Agrega el `case` en el `switch` de
   `aplicacion real/Navigation/RootView.swift`.
4. Si quieres que aparezca en la barra inferior, agrega el caso a
   `NavTab` en `aplicacion real/Design/Components/BottomNavBar.swift`.

---

## Licencia y creditos

Proyecto academico del curso de Productos y Servicios (ciclo 7).

- Prototipo HTML original: JDiazD33.
- Version SwiftUI nativa: generada con asistencia de IA, manteniendo
  la identidad visual del prototipo.
- Iconografia: SF Symbols de Apple y Material Symbols de Google.
- Tipografias: Hanken Grotesk y Be Vietnam Pro (Google Fonts, SIL OFL),
  JetBrains Mono (Apache 2.0).
- Paleta inspirada en Material Design 3 adaptada a identidad UTP.
