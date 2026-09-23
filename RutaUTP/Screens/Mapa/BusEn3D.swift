//
//  BusEn3D.swift
//  RutaUTP
//
//  El bus del mapa: un fotograma de la tira de giros de la combi trujillana.
//
//  ── De dónde sale la imagen ──────────────────────────────────────────────
//  El modelo original es `modelo 3D/combi_trujillo_lowpoly.glb`, generado con
//  Python. **Ninguna biblioteca de Apple lee `.glb`**: se comprobó con SceneKit,
//  con ModelIO y con RealityKit, que responde «No importer can load».
//
//  Se probaron dos caminos antes de este:
//
//    1. **Convertir a USDZ y dibujarlo con SceneKit** en cada marcador. Funciona
//       (el conversor es `modelo 3D/glb_a_usdz.py`), pero SceneKit está obsoleto
//       desde iOS 17 y cada marcador montaba su propio contexto de render.
//    2. **Una imagen fija** del bus. Barata, pero no gira: el rumbo no se vería.
//
//  Lo que hay ahora es el camino que se eligió: **una tira de 36 fotogramas**
//  renderizada con Blender (`tira_giros.py`) desde la vista de tres cuartos, uno
//  por cada 10° de giro. Se dibuja el fotograma que toca y ya está: aspecto de
//  3D, gira fino, y en tiempo de ejecución no cuesta más que una imagen.
//
//  ── Tres cosas que hay que respetar si se regenera la tira ───────────────
//
//    1. **La cámara de Blender va con acimut 0**, es decir, justo detrás del bus
//       mirando al norte. Con acimut distinto de 0, «arriba en la imagen» deja de
//       coincidir con el norte y el bus sale torcido sobre el mapa: con 35° el
//       marcador apuntaba 47° a la derecha yendo al norte. El aspecto de tres
//       cuartos se consigue **subiendo la elevación**, no girando la cámara.
//    2. **El fotograma 0 apunta al norte** y el orden avanza en el sentido de las
//       agujas (el 9 es el este, el 18 el sur, el 27 el oeste).
//    3. **Cada fotograma mide 168 px** = 56 pt a 3x, que es el alto del marcador.
//       Si cambia ese alto, hay que regenerar la tira con el mismo lado.
//

import SwiftUI

/// El bus visto desde arriba y atrás, girado según su rumbo.
///
/// Dibuja un fotograma de la tira `bus-giros` en vez de rotar nada: como los 36
/// fotogramas ya vienen girados, elegir el que toca es exacto y no cuesta GPU.
struct BusEn3D: View {

    /// Rumbo en grados (0 = norte, en sentido horario). Negativo = desconocido.
    let rumbo: Double

    /// Lado del marcador en puntos. Debe coincidir con el de la tira (168 px a
    /// 3x = 56 pt).
    var lado: CGFloat = 56

    /// Un bus seleccionado se dibuja algo más grande.
    var seleccionado: Bool = false

    /// Fotogramas de la tira y grados que cubre cada uno.
    static let fotogramas = 36
    static let gradosPorFotograma = 360.0 / Double(fotogramas)

    /// Fotograma que corresponde al rumbo.
    ///
    /// Un rumbo desconocido devuelve el 0 (mirando al norte) en lugar de fallar:
    /// es preferible un bus quieto y bien dibujado a un hueco en el mapa.
    var indice: Int {
        guard rumbo.isFinite, rumbo >= 0 else { return 0 }

        let normalizado = rumbo.truncatingRemainder(dividingBy: 360)
        let bruto = Int((normalizado / Self.gradosPorFotograma).rounded())

        return bruto % Self.fotogramas
    }

    var body: some View {
        Image("bus-giros")
            .resizable()
            // Suavizado al reducir: la tira viene a resolución 3x.
            .interpolation(.high)
            .frame(width: lado * CGFloat(Self.fotogramas), height: lado)
            .offset(x: -lado * CGFloat(indice))
            // El marco recorta la tira entera y deja ver solo el fotograma. El
            // `alignment: .topLeading` es lo que hace que el recorte caiga donde
            // toca: alinea el origen de la tira con el del marco, y el desplazo
            // de arriba es el que elige la columna.
            .frame(width: lado, height: lado, alignment: .topLeading)
            .clipped()
            .scaleEffect(seleccionado ? 1.18 : 1)
            .animation(.easeInOut(duration: 0.18), value: seleccionado)
    }
}
