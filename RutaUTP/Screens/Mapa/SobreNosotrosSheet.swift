//
//  SobreNosotrosSheet.swift
//  RutaUTP
//
//  Hoja "Sobre Nosotros" del menú lateral del Mapa.
//

import SwiftUI
import UIKit

struct SobreNosotrosSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var tamanoMarca = 30
    @ScaledMetric(relativeTo: .body) private var tamanoIcono = 18
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    /// Leer la version instalada evita que el texto quede desfasado del bundle.
    private var version: String? {
        guard let numero = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !numero.isEmpty else { return nil }
        return L.f("Versión {0}", "Version {0}", [numero])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    identidad
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    Text(L.t("Aplicación prototipo de movilidad en Trujillo para estudiantes y colaboradores. Permite elegir una sede de trabajo, buscar rutas de micros y combis, guardar lugares y consultar reportes comunitarios y seguimiento.",
                             "Prototype mobility app in Trujillo for students and employees. Choose a workplace, find bus and van routes, save places, and view community reports and tracking."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    featureRow(icon: "map", title: L.t("Rutas", "Routes"),
                               detail: L.t("Explora líneas y paraderos para planificar tu viaje.",
                                           "Explore routes and stops to plan your trip."))
                    featureRow(icon: "bookmark", title: L.t("Guardado", "Saved"),
                               detail: L.t("Ten a mano tus lugares y líneas favoritas.",
                                           "Keep your favorite places and routes close at hand."))
                    featureRow(icon: "location", title: L.t("Tu viaje", "Your trip"),
                               detail: L.t("Sigue tu avance durante el recorrido.",
                                           "Follow your progress along the route."))
                } header: {
                    Text(L.t("Sobre la app", "About the app"))
                }
                .textCase(nil)
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))

                Section {
                    creditoRow(L.t("Diseño y desarrollo", "Design and development"),
                               "Universidad Tecnológica del Perú S.A.C")
                    creditoRow(L.t("Institución", "Institution"), "Universidad Tecnológica del Perú")
                    Link(destination: URL(string: "https://www.flaticon.com/uicons")!) {
                        HStack(spacing: 12) {
                            Text("Uicons by Flaticon")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right")
                                .font(.subheadline)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .foregroundStyle(acento)
                    }
                    .accessibilityLabel(L.t("Iconos de negocios por Flaticon", "Business icons by Flaticon"))
                } header: {
                    Text(L.t("Equipo de desarrollo", "Development team"))
                }
                .textCase(nil)
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .formStyle(.grouped)
            .listSectionSpacing(24)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L.t("Sobre Nosotros", "About Us"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(acento)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var identidad: some View {
        VStack(spacing: 10) {
            Image(systemName: "bus")
                .font(.system(size: min(tamanoMarca, 40), weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("Ruta UTP Trujillo")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(L.t("Tu ciudad, más cerca.", "Your city, closer."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let version {
                Text(version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: min(tamanoIcono, 24)))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func creditoRow(_ rol: String, _ nombre: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rol)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(nombre)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
