//
//  OfflineMapSheet.swift
//  RutaUTP
//
//  Qué funciona y qué no sin conexión.
//
//  Vivía dentro de `PerfilView`, que era su único acceso. Se saca aquí para
//  que el aviso de «caminata estimada» de Mapa y Tracking pueda ofrecerlo: son
//  justo las pantallas donde el usuario se topa con la limitación.
//

import SwiftUI

// MARK: - Disponibilidad real de datos locales
struct OfflineMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var comprobando = true
    @State private var numeroRutas = 0
    @State private var revision = 0
    @State private var errorCarga: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: comprobando ? "internaldrive" : (numeroRutas > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle"))
                        .font(.system(size: 48))
                        .foregroundStyle(Color.appPrimary)
                        .frame(maxWidth: .infinity)
                    Text(comprobando
                         ? L.t("Comprobando datos locales…", "Checking local data…")
                         : numeroRutas > 0
                            ? L.t("Rutas disponibles sin conexión", "Routes available offline")
                            : errorCarga != nil
                                ? L.t("No se pudieron cargar las rutas", "Couldn't load routes")
                                : L.t("El catálogo no contiene rutas", "The catalog contains no routes"))
                        .font(.title2.bold())
                    if comprobando {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if numeroRutas > 0 {
                        Label(L.t("\(numeroRutas) rutas cargadas desde la app", "\(numeroRutas) routes loaded from the app"), systemImage: "bus.fill")
                        Text(L.t("Los recorridos y paraderos vienen incluidos en la app. No necesitas descargarlos ni activar un interruptor para consultarlos sin internet.", "Routes and stops are included in the app. No download or switch is needed to view them offline."))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(errorCarga ?? L.t("El catálogo local se cargó correctamente, pero no incluye rutas.", "The local catalog loaded successfully but contains no routes."))
                            .foregroundStyle(.secondary)
                        if errorCarga != nil {
                            Button(L.t("Reintentar", "Retry")) { revision += 1 }
                                .buttonStyle(.bordered)
                        }
                    }
                    Divider()
                    Label(L.t("También se conserva", "Also kept on this device"), systemImage: "bookmark")
                        .font(.headline)
                    Text(L.t("Tus lugares y líneas guardados, y las fotos del perfil y carné que hayas añadido.", "Your saved places and lines, plus any profile and card photos you have added."))
                        .foregroundStyle(.secondary)
                    Divider()
                    Label(L.t("Necesita conexión", "Requires a connection"), systemImage: "wifi")
                        .font(.headline)
                    Text(L.t("La búsqueda de direcciones y el cálculo de indicaciones de Apple Maps requieren internet. El mapa base puede no mostrarse si no está en caché. Esta app no descarga mapas de Apple para uso offline ni garantiza navegación completa sin conexión.", "Address search and Apple Maps directions require internet. The base map may be unavailable when it isn't cached. This app doesn't download Apple maps for offline use or guarantee fully offline navigation."))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color.appSurface)
            .navigationTitle(L.t("Modo offline", "Offline mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
        }
        .task(id: revision) {
            comprobando = true
            errorCarga = nil
            do {
                let rutas = try await GTFSRepository.shared.cargarRutas(reintentar: revision > 0)
                guard !Task.isCancelled else { return }
                numeroRutas = rutas.count
            } catch {
                guard !Task.isCancelled else { return }
                errorCarga = (error as? FalloCargaGTFS)?.mensajeUsuario
                    ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
            }
            comprobando = false
        }
    }
}
