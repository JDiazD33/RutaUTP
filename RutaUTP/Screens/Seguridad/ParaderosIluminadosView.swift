//
//  ParaderosIluminadosView.swift
//  RutaUTP
//
//  Mapa a pantalla completa con los paraderos iluminados de la red
//  (selección determinista de paraderos reales del feed GTFS).
//
//  Cada paradero se dibuja como una burbuja azul con forma de foco y
//  glow animado (pulso), más una leyenda con conteo y toggles de radio.
//

import SwiftUI
import MapKit

// MARK: - Selección determinista de paraderos "iluminados"
enum ParaderosIluminados {

    /// 24 paraderos de la red: determinista por día (mismo día → mismos
    /// paraderos), mezclando zonas del norte, centro y oeste de Trujillo.
    static func seleccionar(_ feed: [RutaGTFS], cantidad: Int = 24) -> [ParaderoGTFS] {
        var vistos: [Int64: ParaderoGTFS] = [:]
        for ruta in feed {
            for p in ruta.paraderos {
                let key = Int64(round(p.lat * 1e6)) * 10_000 + Int64(round(p.lon * 1e6)) * 10
                if vistos[key] == nil {
                    vistos[key] = p
                }
            }
        }
        let todos = Array(vistos.values)

        // Semilla por día: mismo día → misma selección.
        let dia = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        var semilla = UInt64(dia * 2654435761 % 4294967296)
        func proximo() -> UInt64 {
            semilla = semilla &* 6364136223846793005 &+ 1442695040888963407
            return semilla >> 33
        }

        var indices = Array(todos.indices)
        // Fisher–Yates determinista
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            let j = Int(proximo() % UInt64(i + 1))
            indices.swapAt(i, j)
        }
        return indices.prefix(cantidad).map { todos[$0] }
    }
}

// MARK: - Anotación
final class ParaderoIluminadoAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let nombre: String
    var title: String? { nombre }
    init(coordinate: CLLocationCoordinate2D, nombre: String) {
        self.coordinate = coordinate
        self.nombre = nombre
    }
}

// MARK: - Mapa representable
private struct MapaParaderosRepresentable: UIViewRepresentable {
    let paraderos: [ParaderoGTFS]
    var reciente: String?                    // id del paradero a centrar
    var onTocar: ((String) -> Void)? = nil   // nombre del paradero tocado

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true

        let anotaciones = paraderos.map {
            ParaderoIluminadoAnnotation(coordinate: $0.coordinate, nombre: $0.nombre)
        }
        mapView.addAnnotations(anotaciones)

        context.coordinator.onTap = { nombre in
            self.onTocar?(nombre)
        }

        if let primero = paraderos.first {
            encuadrar(mapView, centro: primero.coordinate)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        guard let reciente, reciente != context.coordinator.ultimoCentro else { return }
        context.coordinator.ultimoCentro = reciente
        if let p = paraderos.first(where: { $0.id == reciente }) {
            mapView.setRegion(
                MKCoordinateRegion(center: p.coordinate,
                                   span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)),
                animated: true)
        }
    }

    private func encuadrar(_ mapView: MKMapView, centro: CLLocationCoordinate2D) {
        mapView.setRegion(
            MKCoordinateRegion(center: centro,
                               span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)),
            animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var ultimoCentro: String?
        var onTap: ((String) -> Void)?

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard annotation is ParaderoIluminadoAnnotation else { return nil }

            let id = "paradero-iluminado"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKAnnotationView)
                        ?? MKAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = annotation
            view.image = UIImage.focoBurbuja()
            view.canShowCallout = false
            view.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let a = view.annotation as? ParaderoIluminadoAnnotation else { return }
            mapView.deselectAnnotation(a, animated: false)
            onTap?(a.nombre)
        }
    }
}

// Burbuja azul con foco (dibujada en canvas para no depender de assets).
extension UIImage {
    static func focoBurbuja() -> UIImage {
        let size = CGSize(width: 44, height: 52)
        return UIGraphicsImageRenderer(size: size).image { _ in
            // Glow exterior
            let glow = CGMutablePath()
            glow.addEllipse(in: CGRect(x: 2, y: 2, width: 40, height: 40))
            UIColor.systemBlue.withAlphaComponent(0.18).setFill()
            let ctx = UIGraphicsGetCurrentContext()!
            ctx.addPath(glow)
            ctx.fillPath()

            // Burbuja
            let burbuja = UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: 28, height: 28))
            UIColor.systemBlue.setFill()
            burbuja.fill()
            UIColor.white.setStroke()
            burbuja.lineWidth = 2
            burbuja.stroke()

            // Puntita inferior
            let punta = UIBezierPath()
            punta.move(to: CGPoint(x: 19, y: 34))
            punta.addLine(to: CGPoint(x: 22, y: 44))
            punta.addLine(to: CGPoint(x: 25, y: 34))
            punta.close()
            UIColor.systemBlue.setFill()
            punta.fill()

            // Foco
            let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            if let foco = UIImage(systemName: "lightbulb.fill", withConfiguration: config) {
                let tintColor = UIColor.white
                let rect = CGRect(x: 15, y: 15, width: 14, height: 14)
                tintColor.set()
                foco.withTintColor(tintColor, renderingMode: .alwaysOriginal)
                    .draw(in: rect)
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - Vista principal
struct ParaderosIluminadosView: View {
    let paraderos: [ParaderoGTFS]

    @Environment(\.dismiss) private var dismiss
    @State private var seleccionado: ParaderoGTFS?
    @State private var pulso = false

    var body: some View {
        ZStack(alignment: .top) {
            MapaParaderosRepresentable(
                paraderos: paraderos,
                reciente: seleccionado?.id,
                onTocar: { nombre in
                    if let p = paraderos.first(where: { $0.nombre == nombre }) {
                        withAnimation(.spring(response: 0.4)) {
                            seleccionado = p
                        }
                    }
                }
            )
            .ignoresSafeArea()

            // Chrome superior
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.onSurface)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.appSurface))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Paraderos iluminados")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.onSurface)
                        Text("\(paraderos.count) activos hoy en la red")
                            .font(.system(size: 10))
                            .foregroundStyle(.onSurfaceVariant)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.appSurface))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Leyenda inferior
            VStack {
                Spacer()
                leyenda
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var leyenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulso ? 1.25 : 0.95)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulso)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 26, height: 26)
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .onAppear { pulso = true }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Paradero con iluminación verificada", "Stop with verified lighting"))
                        .font(.bodySm)
                        .fontWeight(.semibold)
                        .foregroundStyle(.onSurface)
                    Text("Zonas monitoreadas de la red · toca un foco en el mapa")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Text("\(paraderos.count)")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.blue)
            }

            if let p = seleccionado {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.nombre)
                            .font(.bodySm)
                            .fontWeight(.semibold)
                            .foregroundStyle(.onSurface)
                            .lineLimit(1)
                        Text("Paradero iluminado · seleccionado")
                            .font(.system(size: 10))
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    Spacer()
                    Button {
                        withAnimation { seleccionado = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
    }
}

#Preview {
    ParaderosIluminadosView(paraderos: [])
}
