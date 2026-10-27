//
//  SoporteSheet.swift
//  RutaUTP
//
//  Hoja de ayuda y preguntas frecuentes del menú lateral del Mapa.
//

import SwiftUI
import UIKit

struct SoporteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var tamanoCabecera = 28
    @ScaledMetric(relativeTo: .body) private var tamanoIcono = 18
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var busqueda = ""
    @State private var preguntaAbierta: Int?

    private struct Pregunta: Identifiable {
        let id: Int
        let icono: String
        let titulo: String
        let respuesta: String
    }

    private var preguntas: [Pregunta] {
        [
            Pregunta(id: 0, icono: "exclamationmark.bubble",
                     titulo: L.t("¿Cómo reporto un incidente?", "How do I report an incident?"),
                     respuesta: L.t("Toca el botón REPORTAR en el mapa o en Seguridad y describe la situación.",
                                    "Tap the REPORT button on the map or in Safety and describe the situation.")
                        + "\n\n" + L.t("En esta versión de prueba, los reportes no se envían a un servidor.",
                                             "In this trial version, reports are not sent to a server.")),
            Pregunta(id: 1, icono: "bookmark",
                     titulo: L.t("¿Cómo guardo un lugar?", "How do I save a place?"),
                     respuesta: L.t("En la pantalla de Guardado, presiona + Añadir y completa los datos.",
                                    "In the Saved screen, tap + Add and fill in the details.")),
            Pregunta(id: 2, icono: "location",
                     titulo: L.t("¿Cómo cambio mi destino?", "How do I change my destination?"),
                     respuesta: L.t("En el mapa, toca un chip (tu sede, Centro, Huanchaco o tus lugares guardados) para cambiar rápido. Elige tu sede en Ajustes.",
                                    "On the map, tap a chip (your workplace, Downtown, Huanchaco or your saved places) to switch quickly. Choose your workplace in Settings.")),
            Pregunta(id: 3, icono: "arrow.triangle.2.circlepath",
                     titulo: L.t("¿Cómo actualizo una ruta?", "How do I refresh a route?"),
                     respuesta: L.t("El catálogo de líneas y paraderos viene incluido en la app. Sus cambios llegan con las actualizaciones de la app.",
                                    "The route and stop catalog is included in the app. Changes arrive with app updates."))
        ]
    }

    private var preguntasFiltradas: [Pregunta] {
        let consulta = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else { return preguntas }
        let locale = IdiomaManager.shared.idioma.locale
        return preguntas.filter { pregunta in
            [pregunta.titulo, pregunta.respuesta].contains { texto in
                texto.range(of: consulta, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if busqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        encabezado
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Section {
                    if preguntasFiltradas.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("No encontramos respuestas", "No answers found"))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(L.t("Prueba con otra palabra o borra la búsqueda.",
                                     "Try another word or clear the search."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(preguntasFiltradas) { pregunta in
                            preguntaRow(pregunta)
                        }
                    }
                } header: {
                    Text(L.t("Preguntas frecuentes", "Frequently asked questions"))
                } footer: {
                    ayudaSinConexion
                }
                .textCase(nil)
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .formStyle(.grouped)
            .listSectionSpacing(24)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L.t("Soporte", "Support"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
            .searchable(text: $busqueda,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L.t("Buscar en la ayuda", "Search help"))
            .autocorrectionDisabled()
            .submitLabel(.search)
        }
        .tint(acento)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: min(tamanoCabecera, 36), weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L.t("¿En qué te ayudamos?", "How can we help?"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(L.t("Encuentra respuestas para usar la app y moverte por Trujillo.",
                     "Find answers about using the app and getting around Trujillo."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var ayudaSinConexion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L.t("Ayuda sin conexión", "Offline help"), systemImage: "wifi.slash")
                .font(.footnote.weight(.medium))
            Text(L.t("Puedes consultar estas respuestas aunque no tengas internet.",
                     "You can read these answers even without an internet connection."))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func preguntaRow(_ pregunta: Pregunta) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { preguntaAbierta == pregunta.id },
            set: { abierta in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    preguntaAbierta = abierta ? pregunta.id : nil
                }
            }
        )) {
            Text(pregunta.respuesta)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
        } label: {
            Label {
                Text(pregunta.titulo)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: pregunta.icono)
                    .font(.system(size: min(tamanoIcono, 24)))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
            .frame(minHeight: 44, alignment: .leading)
        }
    }
}
