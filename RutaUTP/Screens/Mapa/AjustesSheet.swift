//
//  AjustesSheet.swift
//  RutaUTP
//
//  Hoja de ajustes del menú lateral del Mapa.
//

import SwiftUI

struct AjustesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator

    /// La confirmación completa se presenta antes de activar la contribución.
    @State private var mostrarConsentimiento = false
    @State private var mostrarDetallesContribucion = false
    @State private var mostrarNotificaciones = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Tema
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("APARIENCIA", "APPEARANCE"))
                            .font(.labelCapsMd)
                            .foregroundStyle(.onSurfaceVariant)
                            .appTracking(AppTracking.wideLabel)
                        HStack(spacing: 12) {
                            temaButton(.light, icon: "sun.max.fill", label: L.t("Claro", "Light"))
                            temaButton(.dark, icon: "moon.fill", label: L.t("Oscuro", "Dark"))
                        }
                    }

                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    SelectorTematicaEmpresa()
                    SelectorSedeTrabajo()
                    if TematicaEmpresaStore.shared.seleccion != .utp || !TransporteApp.utpComoReferencia {
                        Button {
                            AppHaptics.selection()
                            TransporteApp.usarSedeTrabajo(CatalogoSedesTrabajo.campusUTP)
                        } label: {
                            Label(L.t("Volver a UTP", "Return to UTP"), systemImage: "arrow.uturn.backward")
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint(L.t("Restaura los colores UTP y el campus de Trujillo en el mapa", "Restores UTP colors and the Trujillo campus on the map"))
                    }
                } header: { Text(L.t("Personalización", "Personalization")) }

                Section {
                    Button { mostrarNotificaciones = true } label: {
                        TimelineView(.periodic(from: .now, by: 60)) { contexto in
                            FilaAjustes(titulo: L.t("Notificaciones", "Notifications"), simbolo: "bell.fill",
                                        detalle: NotificacionesService.shared.resumen(ahora: contexto.date))
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: Binding(
                        get: { trackingCoordinator.isEnabled },
                        set: { activar in
                            if activar {
                                mostrarConsentimiento = true
                            } else {
                                trackingCoordinator.setContributionEnabled(false)
                            }
                        }
                    )) {
                        FilaAjustes(titulo: L.t("Ayudar con ubicaciones", "Help with locations"), simbolo: "location.fill",
                                    detalle: resumenContribucion, muestraFlecha: false)
                    }
                    .disabled(!trackingCoordinator.isPublisherConfigured)
                    .accessibilityHint(TextoConsentimientoContribucion.pistaAccesibilidad)

                    Button { mostrarDetallesContribucion = true } label: {
                        Label(L.t("Uso de ubicaciones", "Location data use"), systemImage: "info.circle")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint(L.t("Muestra qué datos se envían y cuándo", "Shows which data is sent and when"))
                } header: { Text(L.t("Servicios", "Services")) }
            }
            .estiloFormularioPreferencias()
            .navigationTitle(L.t("Ajustes", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tintePreferencias()
        .sheet(isPresented: $mostrarNotificaciones) {
            NotificacionesView().seguirTemaForzado().presentationDetents([.large])
        }
        .confirmationDialog(
            L.t("Ayudar con ubicaciones en tiempo real",
                "Help with real-time locations"),
            isPresented: $mostrarConsentimiento,
            titleVisibility: .visible
        ) {
            Button(L.t("Aceptar y activar", "Accept and turn on")) {
                trackingCoordinator.setContributionEnabled(true)
            }

            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            // El alcance se declara ANTES de pedir el consentimiento, no
            // después: la baliza solo transmite con la app abierta, y prometer
            // continuidad en segundo plano sería anunciar algo que el sistema
            // no hace con la configuración actual.
            Text(TextoConsentimientoContribucion.confirmacion)
        }
        .alert(L.t("Contribución de ubicaciones", "Location contribution"),
               isPresented: $mostrarDetallesContribucion) {
            Button(L.t("Entendido", "OK"), role: .cancel) {}
        } message: {
            Text(TextoConsentimientoContribucion.explicacion)
        }
    }

    private var resumenContribucion: String {
        trackingCoordinator.isPublisherConfigured
            ? L.t("Solo con la app abierta", "Only while the app is open")
            : L.t("Servicio no configurado", "Service not configured")
    }

    private enum TemaOpcion { case light, dark }

    private func temaButton(_ tema: TemaOpcion, icon: String, label: String) -> some View {
        let isSelected: Bool = {
            switch tema {
            case .light: return !isDarkMode
            case .dark:  return isDarkMode
            }
        }()
        return Button {
            // Sin withAnimation: animar la escritura de isDarkMode es parte
            // de lo que dejaba el tema "pegado" en oscuro. El cross-fade
            // visual lo pone UIKit; aquí solo se anima el resaltado.
            isDarkMode = (tema == .dark)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                Text(label)
                    .font(.bodyMdMedium)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .foregroundStyle(isSelected ? Color.onPrimaryContainer : Color.onSurface)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.primaryContainer : Color.surfaceContainerLow)
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Apariencia ", "Appearance ") + label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
