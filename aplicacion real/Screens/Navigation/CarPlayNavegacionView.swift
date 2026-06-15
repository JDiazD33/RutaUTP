//
//  CarPlayNavegacionView.swift
//  RutaUTP
//
//  CORREGIDO V3: Vista de navegacion tipo CarPlay/turn-by-turn.
//  - Fondo oscuro #0a0a0a
//  - Franja superior con nombre de ruta + boton Finalizar
//  - Mapa oscuro 60% altura con MKPolyline
//  - Panel inferior con maniobra + instruccion + progress + tiempo/distancia
//  - Timer rota instrucciones cada 4 segundos
//

import SwiftUI
import MapKit

// MARK: - Modelo de instruccion
struct NavegacionInstruction: Identifiable, Equatable {
    let id: Int
    let texto: String
    let distancia: String
    let icono: String
}

private let instruccionesDefault: [NavegacionInstruction] = [
    NavegacionInstruction(id: 0, texto: "Camina 250m hasta Av. Espana",
                           distancia: "250 m",  icono: "figure.walk"),
    NavegacionInstruction(id: 1, texto: "Sube al bus Linea B en el paradero",
                           distancia: "15 min",  icono: "bus.fill"),
    NavegacionInstruction(id: 2, texto: "Continua por Av. Espana por 1.5 km",
                           distancia: "1.5 km",  icono: "arrow.up"),
    NavegacionInstruction(id: 3, texto: "Baja en el frontis de UTP Trujillo",
                           distancia: "200 m",  icono: "arrow.down"),
    NavegacionInstruction(id: 4, texto: "Llegaste a tu destino!",
                           distancia: "",        icono: "checkmark.circle.fill")
]

// MARK: - Vista principal
struct CarPlayNavegacionView: View {
    let rutaNombre: String
    let onFinish: () -> Void

    @State private var instructionIndex: Int = 0
    @State private var timer: Timer? = nil
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )

    private let polylineCoords: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -8.1180, longitude: -79.0350),
        CLLocationCoordinate2D(latitude: -8.1140, longitude: -79.0320),
        CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287)
    ]

    private var instruccionActual: NavegacionInstruction {
        instruccionesDefault[instructionIndex]
    }

    private var progreso: Double {
        Double(instructionIndex) / Double(max(instruccionesDefault.count - 1, 1))
    }

    private var tiempoRestante: String {
        ["4 min", "3 min", "2 min", "1 min", "0 min"][min(instructionIndex, 4)]
    }

    private var distanciaRestante: String {
        ["2.0 km", "1.8 km", "1.5 km", "0.5 km", "0 m"][min(instructionIndex, 4)]
    }

    var body: some View {
        ZStack {
            Color(hex: "#0a0a0a").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                mapArea
                bottomPanel
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NAVEGANDO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .appTracking(1.5)
                Text(rutaNombre)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button(action: {
                stopTimer()
                onFinish()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Finalizar")
                        .font(.system(size: 12, weight: .bold))
                        .appTracking(0.5)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.appPrimary)
    }

    // MARK: - Map area (60% del alto)
    private var mapArea: some View {
        GeometryReader { geo in
            Map(position: $cameraPosition) {
                MapPolyline(coordinates: polylineCoords)
                    .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Annotation("UTP", coordinate: polylineCoords.last!) {
                    ZStack {
                        Circle().fill(Color.appPrimary).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .colorScheme(.dark)
            .allowsHitTesting(false)
            .frame(height: geo.size.height * 0.6)
        }
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Maniobra + instruccion + distancia
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.appPrimary.opacity(0.20)).frame(width: 56, height: 56)
                    Image(systemName: instruccionActual.icono)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(instruccionActual.texto)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if !instruccionActual.distancia.isEmpty {
                        Text(instruccionActual.distancia)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
            }

            // Progress bar
            ProgressView(value: progreso)
                .progressViewStyle(.linear)
                .tint(.appPrimary)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.vertical, 4)

            // Tiempo y distancia restantes
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TIEMPO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .appTracking(1.5)
                    Text(tiempoRestante)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DISTANCIA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .appTracking(1.5)
                    Text(distanciaRestante)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#1a1a1a"))
    }

    // MARK: - Timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if instructionIndex < instruccionesDefault.count - 1 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        instructionIndex += 1
                    }
                } else {
                    stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    CarPlayNavegacionView(rutaNombre: "Linea B - Salaverry", onFinish: {})
}

