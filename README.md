# Ruta UTP Trujillo – Prototipo iOS

App prototipo con 4 pantallas navegables, construida con WKWebView sobre Swift/SwiftUI.

## Estructura del proyecto

```
RutaUTP/
├── RutaUTP.xcodeproj/
│   └── project.pbxproj
└── RutaUTP/
    ├── RutaUTPApp.swift       ← Entry point (@main)
    ├── ContentView.swift      ← Stack de navegación entre pantallas
    ├── WebScreenView.swift    ← WKWebView + interceptor de app://
    ├── bienvenida.html        ← Pantalla 1: Onboarding
    ├── mapa_principal.html    ← Pantalla 2: Mapa principal
    ├── seguridad.html         ← Pantalla 3: Seguridad y guardados
    └── detalle_ruta.html      ← Pantalla 4: Detalle de ruta
```

## Cómo abrir en Xcode

1. Abre Xcode → **Open a project or file**
2. Selecciona la carpeta `RutaUTP/`
3. Xcode detecta el `.xcodeproj` automáticamente

## Primer build

1. En Xcode, selecciona tu iPhone como destino (arriba a la izquierda)
2. Si pide firma, ve a **Signing & Capabilities** → pon tu Apple ID
3. Presiona ▶️ o `Cmd + R`
4. La primera vez puede pedir que confíes el developer en tu iPhone:
   - **Ajustes → General → VPN y gestión de dispositivos → confiar**

## Flujo de navegación

```
Bienvenida
    │ "Comenzar" o "Saltar"
    ▼
Mapa Principal ◄─────────────────────────┐
    │ navbar "Guardado" / "Seguridad"     │
    ▼                                     │
Seguridad y Guardados                     │
    │ navbar "Mapa"                       │
    └─────────────────────────────────────┘
    │
    │ navbar "Rutas" / card de ruta
    ▼
Detalle de Ruta
    │ botón ← (arrow_back)
    └──────────────────────────────────────►
                                        Mapa Principal
```

## Cómo funciona el puente JS→Swift

Cada HTML tiene inyectado este patrón:
```javascript
window.location.href = 'app://navigate/mapa_principal';
```

`WebScreenView.swift` intercepta ese esquema `app://` en el delegado de navegación
y llama a `onNavigate(destination)` en Swift, que actualiza el stack de pantallas.

## Agregar más pantallas

1. Crea el HTML con el bridge JS
2. Agrega el caso al enum `AppScreen` en `ContentView.swift`
3. Agrega el `case` en el `switch` y en la función `navigate(to:)`
4. Arrastra el HTML al grupo `RutaUTP` en Xcode (marca "Copy if needed" + "Add to target")
