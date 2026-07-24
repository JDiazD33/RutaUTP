# 🚌 Buses Animados en Tiempo Real sobre Rutas del Mapa

Implementar buses animados que se muevan sobre las calles reales del mapa (como InDrive/Uber muestra carros), con popup de detalles al tocarlos.

## Contexto del Proyecto Actual

Ya existen en la app:
- **`RutaCoordenadas`** con arrays de coordenadas para Línea 10, Línea 4 y Línea B
- **`BusCard`** en el bottom panel del mapa con datos de Línea 10 (El Cortijo) y Línea 4 (Salaverry)
- **`MapMarkers.swift`** con `BusMarker`, `PulsingUserMarker`, `MarcadorUTP`, `MarcadorDestinoBuscado`
- **`RouteCalculationService`** que calcula polylines reales con `MKDirections`
- Modelo `BusSimulado` ya definido en `MapaViewModel` (pero sin uso activo actualmente)

## Propuesta de Diseño

### Cómo Funciona (Flujo del Usuario)

1. **Usuario abre el mapa** → Se muestran 2 buses animados moviéndose por las rutas reales de calles
2. **Bus Línea 10** (El Cortijo) se mueve por `RutaCoordenadas.linea10` con color `appPrimary`
3. **Bus Línea 4** (Salaverry) se mueve por `RutaCoordenadas.linea4` con color `secondary`
4. Los buses **se deslizan suavemente** de punto a punto interpolando posiciones (no saltan)
5. **Al tocar un bus** → aparece un popup card con detalles de esa línea (nombre, empresa, ETA, tipo, placa)
6. El popup tiene botón para ver la ruta completa (navega a pantalla Rutas)

### Comportamiento de Animación

- Los buses recorren los arrays de coordenadas de ida y vuelta en loop continuo
- Velocidad simulada: ~3 segundos por segmento entre cada par de coordenadas
- Interpolación lineal suave entre puntos (como un vehículo real)
- El icono del bus rota según la dirección de movimiento (heading)

---

## Proposed Changes

### Componente: MapMarkers

#### [MODIFY] [MapMarkers.swift](file:///c:/Users/frixi/Documents/ciclo%207/Productos%20y%20Servicios/alucina/RutaUTP/RutaUTP/Screens/Mapa/MapMarkers.swift)
- Agregar nuevo componente `AnimatedBusMarker` con icono de bus (`bus.fill`), etiqueta de línea visible, y animación pulsante
- Diseño tipo pin premium: círculo con icono de bus + badge con el número de línea arriba

---

### Componente: MapaViewModel (Motor de Simulación)

#### [MODIFY] [MapaViewModel.swift](file:///c:/Users/frixi/Documents/ciclo%207/Productos%20y%20Servicios/alucina/RutaUTP/RutaUTP/Screens/Mapa/MapaViewModel.swift)
- Agregar array `@Published var busesAnimados: [BusAnimado]` con 2 buses (Línea 10 y Línea 4)
- Cada `BusAnimado` contiene: id, línea, empresa, tipo, placa, minutos, color, coordenada actual animada, heading actual
- Timer cada ~0.05s que interpola la posición de cada bus entre los waypoints de su ruta
- Los buses van y vuelven (ping-pong) sobre las coordenadas de `RutaCoordenadas`
- Agregar `@Published var busSeleccionado: BusAnimado?` para controlar el popup de detalles
- `func iniciarSimulacionBuses()` se llama en `onAppear`
- `func detenerSimulacionBuses()` limpia el timer

---

### Componente: MapaView (Renderizado + Popup)

#### [MODIFY] [MapaView.swift](file:///c:/Users/frixi/Documents/ciclo%207/Productos%20y%20Servicios/alucina/RutaUTP/RutaUTP/Screens/Mapa/MapaView.swift)
- En el `Map { }`, agregar `Annotation` por cada bus en `vm.busesAnimados` con el nuevo `AnimatedBusMarker`
- Cada `Annotation` tiene `.onTapGesture` que setea `vm.busSeleccionado = bus`
- Agregar overlay popup (`BusDetailPopup`) que aparece con animación desde abajo cuando `vm.busSeleccionado != nil`
- El popup muestra: icono de línea, nombre empresa, ETA, tipo vehículo, placa, y botón "Ver Ruta Completa"

---

## Modelo de Datos Nuevo

```swift
struct BusAnimado: Identifiable, Equatable {
    let id: Int
    let linea: String        // "10", "4"
    let empresa: String      // "El Cortijo", "Salaverry"
    let tipo: String          // "Micro", "Combi"
    let placa: String         // "T1B-721"
    let minutosLlegada: Int   // 4, 12
    let color: Color          // .appPrimary, .secondary
    var lat: Double           // posición actual (animada)
    var lon: Double
    var heading: Double       // ángulo de dirección
    let rutaCoordenadas: [CLLocationCoordinate2D]  // waypoints
}
```

---

## Verification Plan

### Manual Verification
- Abrir vista de mapa y verificar que 2 buses se mueven suavemente por las calles
- Tocar un bus y verificar que aparece popup con detalles correctos
- Verificar que los buses no "flotan" fuera de las calles
- Verificar que el popup se cierra al tocar fuera o presionar X
- Verificar que el botón "Ver Ruta" del popup navega a la pantalla de Rutas

> [!IMPORTANT]
> Los buses se moverán sobre los waypoints existentes en `RutaCoordenadas` (7 puntos para Línea 10 y 6 para Línea 4). La interpolación lineal entre estos puntos dará un movimiento suave, aunque no seguirá la curvatura exacta de cada calle — para eso se necesitarían muchos más waypoints o usar MKDirections para cada segmento.

> [!NOTE]  
> La animación es **simulada** (no datos GPS reales de buses). Es una representación visual para la demo/presentación. Los datos de ETA, placa, empresa son los mismos que ya están en las `BusCard` del bottom panel.
