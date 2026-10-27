//
//  CiudadSheet.swift
//  RutaUTP
//
//  Hoja de selección de ciudad del menú lateral del Mapa.
//

import SwiftUI
import UIKit

// La app solo tiene datos GTFS de Trujillo: es la única ciudad seleccionable.
// Las demás se muestran bloqueadas ("Próximamente") para comunicar la visión
// del producto sin prometer algo que aún no existe.
struct CiudadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("ciudadSeleccionada") private var ciudadSeleccionada: String = "Trujillo"

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    private struct Ciudad: Identifiable {
        let nombre: String
        let disponible: Bool
        var id: String { nombre }
    }

    private let ciudades: [Ciudad] = [
        Ciudad(nombre: "Trujillo", disponible: true),
        Ciudad(nombre: "Lima", disponible: false),
        Ciudad(nombre: "Chiclayo", disponible: false),
        Ciudad(nombre: "Piura", disponible: false),
        Ciudad(nombre: "Arequipa", disponible: false),
        Ciudad(nombre: "Cuzco", disponible: false)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ciudades.filter { $0.disponible }) { ciudad in
                        ciudadRow(ciudad)
                    }
                } footer: {
                    Text(L.t("RutaUTP opera con datos de transporte de Trujillo. Estamos trabajando para llegar a más ciudades.",
                             "RutaUTP runs on Trujillo transit data. We're working on more cities."))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    ForEach(ciudades.filter { !$0.disponible }) { ciudad in
                        ciudadRow(ciudad)
                    }
                } header: {
                    Text(L.t("Próximamente", "Coming soon"))
                }
                .textCase(nil)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(L.t("Ciudad", "City"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(acento)
    }

    @ViewBuilder
    private func ciudadRow(_ ciudad: Ciudad) -> some View {
        if ciudad.disponible {
            HStack(spacing: 12) {
                Image(systemName: "building.2")
                    .font(.title2)
                    .foregroundStyle(acento)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ciudad.nombre)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("Rutas y paraderos activos", "Routes and stops active"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(acento)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ciudad.nombre + L.t(", ciudad actual", ", current city"))
            .accessibilityValue(L.t("Rutas y paraderos activos", "Routes and stops active"))
            .accessibilityAddTraits(.isSelected)
            .onAppear { ciudadSeleccionada = "Trujillo" }
        } else {
            HStack(spacing: 12) {
                Text(ciudad.nombre)
                    .font(.body)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "lock")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ciudad.nombre + L.t(", próximamente", ", coming soon"))
            .accessibilityHint(L.t("Esta ciudad aún no está disponible", "This city is not available yet"))
        }
    }
}
