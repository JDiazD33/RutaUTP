//
//  MapaElegirExpandido.swift
//  RutaUTP
//
//  Selector de ubicación a pantalla completa para AddLugarSheet.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Mapa expandido para elegir ubicación (desde AddLugarSheet)
/// El mismo selector `MapaElegirLugar` a pantalla completa: comparte la
/// coordenada con el formulario vía binding y sincroniza cada toque.
struct MapaElegirExpandido: View {
    @Binding var coordenada: CLLocationCoordinate2D?
    @ObservedObject var ubicacion: UbicacionMapaLugar
    let locationService: LocationServiceProtocol
    var iconoPin: String = "mappin.circle.fill"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var alturaCabecera: CGFloat = 52
    /// Se dispara en cada toque del mapa, después de actualizar la coordenada.
    /// Recibe la coordenada tocada para poder geocodificarla.
    var onTocar: (CLLocationCoordinate2D) -> Void
    var onCerrar: () -> Void

    var body: some View {
        MapaElegirLugar(
            colorPin: .appPrimary,
            coordenada: coordenada,
            onTocar: { coord in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    coordenada = coord
                }
                onTocar(coord)
            },
            spanInicial: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006),
            spanRecentrado: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006),
            iconoPin: iconoPin,
            centroCamara: ubicacion.centro,
            recentrarCamaraTrigger: ubicacion.revisionCamara,
            onInteraccion: { ubicacion.interactuar() },
            controles: .ubicacionYCiudad,
            espacioSuperiorControles: alturaCabecera,
            onUbicar: { ubicacion.buscar(desde: locationService) }
        )
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) {
                barraSuperior.background {
                    GeometryReader { geometria in
                        Color.clear.preference(key: AlturaCabecera.self, value: geometria.size.height)
                    }
                }
            }
            .onPreferenceChange(AlturaCabecera.self) { alturaCabecera = $0 }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if let aviso = ubicacion.aviso {
                        Text(aviso)
                            .font(.footnote)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                    }
                    pie
                        .padding(.bottom, 4)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: coordenada == nil)
    }

    private struct AlturaCabecera: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L.t("Elige la ubicación", "Pick the location"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer()

            Button {
                onCerrar()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Abajo: instrucción mientras no haya pin; botón de confirmar cuando sí.
    @ViewBuilder
    private var pie: some View {
        if coordenada != nil {
            Button {
                onCerrar()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                    Text(L.t("Usar esta ubicación", "Use this location"))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.onPrimaryFill)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Text(L.t("Toca el mapa para ubicar el lugar", "Tap the map to pin the location"))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }
}
