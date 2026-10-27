//
//  AddLineaSheet.swift
//  RutaUTP
//
//  Hoja para guardar una línea del catálogo GTFS.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Add Linea sheet (selector de líneas GTFS reales)
struct AddLineaSheet: View {
    let catalogo: [RutaOpcion]
    /// Distingue carga, fallo y catálogo vacío sin ocultar los errores del feed.
    let cargando: Bool
    var errorCatalogo: FalloCargaGTFS? = nil
    var onRetry: () -> Void = {}
    let yaGuardadas: Set<String>
    var onSave: (RutaOpcion) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var texto = ""
    @State private var errorAlGuardar = false
    @FocusState private var busquedaEnfocada: Bool

    private var filtradas: [RutaOpcion] {
        let consulta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else { return catalogo }
        return catalogo.filter {
            $0.linea.localizedCaseInsensitiveContains(consulta)
            || $0.empresa.localizedCaseInsensitiveContains(consulta)
            || $0.recorrido.localizedCaseInsensitiveContains(consulta)
        }
    }

    var body: some View {
        let rutas = filtradas
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                encabezado(total: rutas.count)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                buscador
                    .padding(.horizontal, 20)
                resultados(rutas)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("Añadir línea", "Add line"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .tint(Color.appAccent)
        .alert(L.t("No se pudo guardar la línea", "Unable to save line"), isPresented: $errorAlGuardar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Reintenta su lectura desde Guardado.",
                     "The original data has been preserved. Retry reading it from Saved."))
        }
    }

    private func encabezado(total: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Elige tu ruta", "Pick your route"))
                    .font(.headlineSm)
                    .foregroundStyle(Color.onSurface)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("Toca una línea para guardarla.", "Tap a line to save it."))
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !cargando, errorCatalogo == nil, !catalogo.isEmpty {
                Text("\(total)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.onPrimaryContainer)
                    .padding(12)
                    .background(Color.primaryContainer, in: Capsule())
                    .accessibilityLabel(L.f("{0} rutas encontradas", "{0} routes found", ["\(total)"]))
            }
        }
    }

    private var buscador: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .accessibilityHidden(true)
            TextField(L.t("Buscar línea, empresa o avenida", "Search line, company or avenue"), text: $texto)
                .font(.bodySm)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($busquedaEnfocada)
                .onSubmit { busquedaEnfocada = false }
                .accessibilityLabel(L.t("Buscar línea para guardar", "Search for a line to save"))
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Borrar búsqueda", "Clear search"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        }
    }

    private func resultados(_ rutas: [RutaOpcion]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if cargando {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L.t("Cargando rutas…", "Loading routes…"))
                            .font(.bodySm)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else if let error = errorCatalogo {
                    VStack(spacing: 12) {
                        estado(icono: "exclamationmark.triangle", mensaje: error.mensajeUsuario)
                        Button(L.t("Reintentar", "Try again"), action: onRetry)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.onPrimaryFill)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(Color.primaryFill, in: Capsule())
                            .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if catalogo.isEmpty {
                    estado(icono: "bus", mensaje: TransporteApp.rutasUTPPendientes
                           ? TransporteApp.mensajePendiente
                           : L.t("El catálogo no contiene líneas.", "The catalog contains no routes."))
                } else if rutas.isEmpty {
                    estado(icono: "magnifyingglass", mensaje:
                            L.t("Sin coincidencias para ", "No matches for ") + "“\(texto)”")
                } else {
                    ForEach(rutas) { ruta in
                        filaCatalogo(ruta)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func estado(icono: String, mensaje: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icono)
                .font(.title)
                .accessibilityHidden(true)
            Text(mensaje)
                .font(.bodySm)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.onSurfaceVariant)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func filaCatalogo(_ ruta: RutaOpcion) -> some View {
        let guardada = yaGuardadas.contains(ruta.id)
        return Button {
            guard !guardada else { return }
            busquedaEnfocada = false
            guard onSave(ruta) else {
                errorAlGuardar = true
                return
            }
            AppHaptics.success()
            dismiss()
        } label: {
            RutaOpcionCard(ruta: ruta, accesorio: guardada ? .guardada : .añadir)
        }
        .buttonStyle(.plain)
        .disabled(guardada)
        .accessibilityHint(guardada ? "" : L.t("Añade esta línea a Guardado", "Adds this line to Saved"))
        .accessibilityAddTraits(guardada ? .isSelected : [])
    }
}
