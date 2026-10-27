//
//  ExpandedRouteIncidentMap.swift
//  RutaUTP
//
//  Mapa ampliado para elegir el punto afectado.
//

import SwiftUI
import MapKit

struct ExpandedRouteIncidentMap: View {
    let route: RutaGTFS
    let onConfirm: (CLLocationCoordinate2D, MapCameraPosition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var point: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition

    init(route: RutaGTFS, initialPoint: CLLocationCoordinate2D?, initialCamera: MapCameraPosition,
         onConfirm: @escaping (CLLocationCoordinate2D, MapCameraPosition) -> Void) {
        self.route = route
        self.onConfirm = onConfirm
        _point = State(initialValue: initialPoint)
        _camera = State(initialValue: initialCamera)
    }

    var body: some View {
        NavigationStack {
            RouteIncidentMap(route: route, point: $point, camera: $camera)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        Text(L.t("Amplía con dos dedos y toca el lugar afectado.",
                                 "Pinch to zoom and tap the affected location."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        // Mismo veredicto que el formulario: ampliar el mapa no
                        // puede ser una puerta para saltarse el filtro.
                        AvisoCoherencia(evaluacion: coherencia, route: route)
                        Button {
                            withAnimation { camera = .automatic }
                        } label: {
                            Label(L.t("Ver ruta completa", "Show full route"), systemImage: "map")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
                .navigationTitle(L.t("Línea ", "Line ") + route.linea + " · " + route.variante)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.t("Cancelar", "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("Usar punto", "Use point")) {
                            guard let point else { return }
                            onConfirm(point, camera)
                            dismiss()
                        }
                        .disabled(point == nil || !coherenciaValida)
                    }
                }
        }
    }

    private var coherencia: CoherenciaPunto? {
        guard let point else { return nil }
        return VerificadorCoherencia.evaluar(point: point, ruta: route)
    }

    private var coherenciaValida: Bool { coherencia?.esValido ?? true }
}
