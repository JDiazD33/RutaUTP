//
//  RutaMapKitView.swift
//  RutaUTP
//
//  Mapa del recorrido en el detalle de ruta: una imagen fija preparada con
//  MKMapSnapshotter, con el trazado y sus extremos dibujados encima.
//  - Badge "RECORRIDO OFICIAL" sobre el mapa en esquina superior derecha.
//    Antes decía "RUTA SEGURA", que afirmaba una seguridad que el feed GTFS
//    no respalda: el feed describe el trazado y los paraderos, no si la zona
//    es segura. "Recorrido oficial" sí es cierto y verificable.
//  - No captura gestos: el padre abre el explorador al tocarla.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Imagen del recorrido
//
// El detalle de ruta mostraba un `MKMapView` vivo que no admite gestos. Crear
// esa vista ocupa el hilo principal y sigue dibujando teselas mientras se
// desplaza la pantalla; en teléfonos antiguos se notaba al entrar y al bajar.
// `MKMapSnapshotter` prepara la misma imagen fuera del hilo principal y una
// imagen fija no cuesta nada al desplazar. Se conserva en memoria por ruta,
// tema y tamaño, así que volver a una línea ya vista es inmediato.
enum InstantaneaRecorrido {
    struct Clave: Hashable {
        let idRuta: String
        let oscuro: Bool
        let ancho: Int
        let alto: Int
        let escala: Int

        var texto: NSString { "\(idRuta)|\(oscuro)|\(ancho)x\(alto)@\(escala)" as NSString }
        var valida: Bool { ancho > 0 && alto > 0 && escala > 0 }
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 16
        return cache
    }()

    static func guardada(_ clave: Clave) -> UIImage? { cache.object(forKey: clave.texto) }

    /// Márgenes del recorrido dentro de la imagen, en puntos.
    private static let margenes = UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30)

    /// Prepara la captura en el hilo principal, que es breve; el mapa y el
    /// dibujo del trazado se resuelven fuera de él. `nil` si se cancela o falla.
    @MainActor
    static func generar(_ clave: Clave, coordenadas: [CLLocationCoordinate2D],
                        colorLinea: UIColor) async -> UIImage? {
        guard clave.valida, coordenadas.count >= 2 else { return nil }
        if let guardada = guardada(clave) { return guardada }

        let tamano = CGSize(width: clave.ancho, height: clave.alto)
        let rasgos = UITraitCollection { rasgos in
            rasgos.userInterfaceStyle = clave.oscuro ? .dark : .light
            rasgos.displayScale = CGFloat(clave.escala)
        }
        let limites = MKPolyline(coordinates: coordenadas, count: coordenadas.count).boundingMapRect
        let opciones = MKMapSnapshotter.Options()
        opciones.size = tamano
        opciones.traitCollection = rasgos
        opciones.pointOfInterestFilter = .excludingAll
        opciones.mapRect = encuadre(limites, en: tamano)

        let tarea = TareaInstantanea(MKMapSnapshotter(options: opciones))
        let color = colorLinea.resolvedColor(with: rasgos)
        // Dibujar con menos puntos no cambia la imagen a este tamaño.
        let trazo = PolylineMatching.decimate(coordenadas, maxPoints: 400)
        let imagen = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuacion: CheckedContinuation<UIImage?, Never>) in
                tarea.iniciar { instantanea in
                    guard let instantanea else {
                        continuacion.resume(returning: nil)
                        return
                    }
                    continuacion.resume(returning: dibujar(instantanea, trazo: trazo.count >= 2 ? trazo : coordenadas,
                                                           color: color, tamano: tamano, rasgos: rasgos))
                }
            }
        } onCancel: {
            tarea.cancelar()
        }
        guard let imagen, !Task.isCancelled else { return nil }
        cache.setObject(imagen, forKey: clave.texto)
        return imagen
    }

    /// Región del mapa que deja el recorrido dentro de los márgenes.
    private static func encuadre(_ limites: MKMapRect, en tamano: CGSize) -> MKMapRect {
        let anchoUtil = max(1, Double(tamano.width - margenes.left - margenes.right))
        let altoUtil = max(1, Double(tamano.height - margenes.top - margenes.bottom))
        // Puntos de mapa por punto de pantalla; un recorrido mínimo evita una
        // región vacía cuando todos los puntos coinciden.
        let porPunto = max(limites.size.width / anchoUtil, limites.size.height / altoUtil, 1)
        let ancho = porPunto * Double(tamano.width)
        let alto = porPunto * Double(tamano.height)
        return MKMapRect(x: limites.midX - ancho / 2, y: limites.midY - alto / 2, width: ancho, height: alto)
    }

    private static func dibujar(_ instantanea: MKMapSnapshotter.Snapshot, trazo: [CLLocationCoordinate2D],
                                color: UIColor, tamano: CGSize, rasgos: UITraitCollection) -> UIImage {
        let formato = UIGraphicsImageRendererFormat(for: rasgos)
        formato.opaque = true
        return UIGraphicsImageRenderer(size: tamano, format: formato).image { contexto in
            instantanea.image.draw(at: .zero)

            let linea = UIBezierPath()
            for (indice, coordenada) in trazo.enumerated() {
                let punto = instantanea.point(for: coordenada)
                if indice == 0 { linea.move(to: punto) } else { linea.addLine(to: punto) }
            }
            linea.lineWidth = 5
            linea.lineCapStyle = .round
            linea.lineJoinStyle = .round
            color.setStroke()
            linea.stroke()

            // Inicio: punto del color de la línea. Final: bandera, como en el
            // explorador y en la guía.
            if let inicio = trazo.first {
                marcador(en: instantanea.point(for: inicio), radio: 8, relleno: color,
                         simbolo: nil, contexto: contexto.cgContext)
            }
            if let fin = trazo.last {
                marcador(en: instantanea.point(for: fin), radio: 13, relleno: .systemRed.resolvedColor(with: rasgos),
                         simbolo: "flag.fill", contexto: contexto.cgContext)
            }
        }
    }

    private static func marcador(en centro: CGPoint, radio: CGFloat, relleno: UIColor,
                                 simbolo: String?, contexto: CGContext) {
        let marco = CGRect(x: centro.x - radio, y: centro.y - radio, width: radio * 2, height: radio * 2)
        contexto.saveGState()
        contexto.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                           color: UIColor.black.withAlphaComponent(0.25).cgColor)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: marco.insetBy(dx: -2, dy: -2)).fill()
        contexto.restoreGState()
        relleno.setFill()
        UIBezierPath(ovalIn: marco).fill()
        guard let simbolo,
              let icono = UIImage(systemName: simbolo,
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: radio * 0.95, weight: .bold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
        icono.draw(at: CGPoint(x: centro.x - icono.size.width / 2, y: centro.y - icono.size.height / 2))
    }
}

/// Permite cancelar la captura desde la tarea que la espera. Entrega el
/// resultado una sola vez, también si la captura se cancela sin responder.
private final class TareaInstantanea: @unchecked Sendable {
    private let captura: MKMapSnapshotter
    private let candado = NSLock()
    private var alTerminar: (@Sendable (MKMapSnapshotter.Snapshot?) -> Void)?
    private var cancelada = false

    init(_ captura: MKMapSnapshotter) { self.captura = captura }

    func iniciar(_ alTerminar: @escaping @Sendable (MKMapSnapshotter.Snapshot?) -> Void) {
        candado.lock()
        let yaCancelada = cancelada
        if !yaCancelada { self.alTerminar = alTerminar }
        candado.unlock()
        guard !yaCancelada else {
            alTerminar(nil)
            return
        }
        captura.start(with: DispatchQueue.global(qos: .userInitiated)) { [weak self] instantanea, _ in
            self?.entregar(instantanea)
        }
    }

    func cancelar() {
        candado.lock()
        cancelada = true
        candado.unlock()
        captura.cancel()
        entregar(nil)
    }

    private func entregar(_ instantanea: MKMapSnapshotter.Snapshot?) {
        candado.lock()
        let pendiente = alTerminar
        alTerminar = nil
        candado.unlock()
        pendiente?(instantanea)
    }
}

// MARK: - Vista SwiftUI con mapa + badge
struct RutaMapKitView: View {
    let ruta: RutaOpcion

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var tamano: CGSize = .zero
    @State private var imagen: UIImage?
    @State private var claveMostrada: InstantaneaRecorrido.Clave?

    /// Shape real del feed GTFS.
    ///
    /// Ya NO hay trazado de respaldo. Antes, si la ruta no traía geometría, se
    /// dibujaba una línea inventada: el usuario veía como "su recorrido" un
    /// trazado que no era el suyo, sin nada que lo delatara. Ahora se muestra
    /// un estado vacío explícito.
    private var coordenadas: [CLLocationCoordinate2D] { ruta.shape }

    private var clave: InstantaneaRecorrido.Clave {
        InstantaneaRecorrido.Clave(idRuta: ruta.id, oscuro: colorScheme == .dark,
                                   ancho: Int(tamano.width.rounded()), alto: Int(tamano.height.rounded()),
                                   escala: Int(displayScale.rounded()))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if coordenadas.count >= 2 {
                Color.surfaceContainerLow
                    .overlay {
                        if let imagen, claveMostrada == clave {
                            Image(uiImage: imagen)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        }
                    }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { tamano = $0 }
                    .task(id: clave) { await cargar(clave) }
            } else {
                sinTrazado
            }

            // Badge "RECORRIDO OFICIAL"
            HStack(spacing: 5) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .accessibilityHidden(true)
                Text(L.t("RECORRIDO OFICIAL", "OFFICIAL ROUTE"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(12)
            .accessibilityElement(children: .combine)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Una imagen ya preparada aparece al instante. La primera vez espera a
    /// que termine la entrada de la pantalla para no competir con su animación.
    private func cargar(_ clave: InstantaneaRecorrido.Clave) async {
        guard clave.valida else { return }
        if let guardada = InstantaneaRecorrido.guardada(clave) {
            imagen = guardada
            claveMostrada = clave
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled,
              let nueva = await InstantaneaRecorrido.generar(clave, coordenadas: coordenadas,
                                                             colorLinea: UIColor(ruta.colorLinea)),
              !Task.isCancelled else { return }
        withAnimation(reducirMovimiento ? nil : .easeOut(duration: 0.2)) {
            imagen = nueva
            claveMostrada = clave
        }
    }

    /// Estado honesto para una ruta sin geometría en el feed.
    private var sinTrazado: some View {
        ZStack {
            Color.surfaceContainerLow
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(L.t("Esta línea no trae trazado en el feed",
                         "This line has no geometry in the feed"))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RutaMapKitView(ruta: RutaOpcion(
        id: "17419574", linea: "C-06", empresa: "Titanic Express",
        recorrido: "Vía Panamericana Norte (ramal circular)",
        frecuenciaMin: 5, duracionMin: 45, costo: "S/ 2.50",
        numParaderos: 120, distanciaKm: 18.4, colorLinea: Color(hex: "#9999FF"),
        shape: [], paraderos: [],
        paradaInicio: "Panamericana Norte", paradaFin: "Av. América"
    ))
    .frame(height: 280)
    .padding()
}
