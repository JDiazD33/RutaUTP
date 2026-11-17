import SwiftUI
import UniformTypeIdentifiers

/// Respaldos de los datos del usuario: crear, importar, restaurar, compartir
/// y eliminar. Las copias sobreviven a la pantalla que las creó; se releen
/// desde disco. La lógica de archivos vive en `RespaldoDatos`.
struct RespaldosRecuperacionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var respaldos: [FilaRespaldo] = []
    @State private var cargando = false
    @State private var lecturaFallida = false
    @State private var revision = 0
    @State private var lecturaActual = UUID()
    @State private var importando = false
    @State private var aviso: AvisoRespaldo?
    @State private var porEliminar: FilaRespaldo?
    @State private var ruta: [URL] = []

    var body: some View {
        NavigationStack(path: $ruta) {
            List {
                Section {
                    Button(action: crear) {
                        Label(L.t("Crear respaldo ahora", "Back up now"), systemImage: "plus.circle.fill")
                            .frame(minHeight: 44)
                    }
                    Button { importando = true } label: {
                        Label(L.t("Importar desde Archivos", "Import from Files"), systemImage: "square.and.arrow.down")
                            .frame(minHeight: 44)
                    }
                } footer: {
                    Text(L.t("Guarda tus lugares, líneas, accesos de Seguridad, cupones, lugares de subida, contacto de emergencia, datos personales y preferencias. No incluye fotos, tarjetas ni el saldo del monedero. Comparte un respaldo para conservarlo fuera del iPhone.",
                             "Saves your places, lines, safety shortcuts, coupons, boarding spots, emergency contact, personal details and preferences. Photos, cards and wallet balance aren't included. Share a backup to keep it off the iPhone."))
                }

                if cargando && respaldos.isEmpty {
                    ProgressView(L.t("Leyendo respaldos…", "Reading backups…"))
                } else if lecturaFallida {
                    Section {
                        Text(L.t("No se pudieron leer los respaldos. Inténtalo de nuevo con el dispositivo desbloqueado.",
                                 "Backups could not be read. Try again with the device unlocked."))
                        Button(L.t("Reintentar lectura", "Retry reading")) { revision += 1 }
                            .frame(minHeight: 44)
                    }
                } else if respaldos.isEmpty {
                    ContentUnavailableView(
                        L.t("Sin respaldos guardados", "No saved backups"),
                        systemImage: "archivebox",
                        description: Text(L.t("Crea un respaldo para recuperar tus datos si cambias de opinión o reinicias una sección. También aparecerán aquí las copias que la app guarda antes de reiniciar datos.",
                                               "Create a backup to recover your data if you change your mind or reset a section. Copies the app saves before resetting data also appear here.")))
                } else {
                    Section(L.t("Respaldos guardados", "Saved backups")) {
                        ForEach(respaldos) { fila in
                            NavigationLink(value: fila.archivo.url) {
                                FilaRespaldoView(fila: fila)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { porEliminar = fila } label: {
                                    Label(L.t("Eliminar", "Delete"), systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                ShareLink(item: fila.archivo.url) {
                                    Label(L.t("Compartir respaldo", "Share backup"), systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) { porEliminar = fila } label: {
                                    Label(L.t("Eliminar respaldo", "Delete backup"), systemImage: "trash")
                                }
                            }
                            .accessibilityActions {
                                Button(L.t("Eliminar respaldo", "Delete backup")) { porEliminar = fila }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L.t("Respaldos guardados", "Saved backups"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
            .navigationDestination(for: URL.self) { url in
                DetalleRespaldoView(fila: respaldos.first { $0.archivo.url == url }) { cambio in
                    revision += 1
                    if let cambio { aviso = cambio }
                }
            }
            .refreshable { await cargar() }
            .task(id: revision) { await cargar() }
            .fileImporter(isPresented: $importando, allowedContentTypes: [.propertyList]) { resultado in
                importar(resultado)
            }
            .confirmationDialog(L.t("¿Eliminar este respaldo?", "Delete this backup?"),
                                isPresented: Binding(get: { porEliminar != nil },
                                                     set: { if !$0 { porEliminar = nil } }),
                                titleVisibility: .visible,
                                presenting: porEliminar) { fila in
                Button(L.t("Eliminar", "Delete"), role: .destructive) { eliminar(fila) }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            } message: { _ in
                Text(L.t("Se borrará del iPhone y no se puede deshacer. Las copias que hayas compartido se conservan.",
                         "It will be deleted from this iPhone and can't be undone. Copies you've shared are kept."))
            }
            .alert(aviso?.titulo ?? "",
                   isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } }),
                   presenting: aviso) { _ in
                Button(L.t("Aceptar", "OK"), role: .cancel) {}
            } message: { aviso in
                Text(aviso.mensaje)
            }
        }
    }

    // MARK: Acciones

    private func crear() {
        do {
            try RespaldoDatos.crearManual()
            AppHaptics.success()
            aviso = AvisoRespaldo(titulo: L.t("Respaldo creado", "Backup created"),
                                  mensaje: L.t("Ya está en la lista. Puedes compartirlo para guardarlo en Archivos o en otro dispositivo.",
                                               "It's now in the list. You can share it to keep it in Files or on another device."))
        } catch {
            AppHaptics.warning()
            aviso = AvisoRespaldo(titulo: L.t("No se pudo crear el respaldo", "Couldn't create the backup"),
                                  mensaje: RespaldoDatos.mensaje(error))
        }
        revision += 1
    }

    private func importar(_ resultado: Result<URL, Error>) {
        do {
            let origen = try resultado.get()
            try RespaldoDatos.importar(desde: origen)
            AppHaptics.success()
            aviso = AvisoRespaldo(titulo: L.t("Respaldo importado", "Backup imported"),
                                  mensaje: L.t("Ábrelo en la lista para elegir qué restaurar.",
                                               "Open it in the list to choose what to restore."))
        } catch {
            AppHaptics.warning()
            aviso = AvisoRespaldo(titulo: L.t("No se pudo importar", "Couldn't import"),
                                  mensaje: RespaldoDatos.mensaje(error))
        }
        revision += 1
    }

    private func eliminar(_ fila: FilaRespaldo) {
        do {
            try RespaldoDatos.eliminar(fila.archivo.url)
            AppHaptics.success()
        } catch {
            aviso = AvisoRespaldo(titulo: L.t("No se pudo eliminar", "Couldn't delete"),
                                  mensaje: RespaldoDatos.mensaje(error))
        }
        porEliminar = nil
        revision += 1
    }

    @MainActor
    private func cargar() async {
        let lectura = UUID()
        lecturaActual = lectura
        cargando = true
        defer { if lecturaActual == lectura { cargando = false } }
        do {
            let archivos = try await RecuperacionPreferencias.listar()
            // Leer cada copia no ocupa MainActor; un archivo ilegible se lista igual.
            let filas = await Task.detached(priority: .utility) {
                archivos.map { FilaRespaldo(archivo: $0, contenido: try? RespaldoDatos.leer($0.url)) }
            }.value
            guard !Task.isCancelled, lecturaActual == lectura else { return }
            respaldos = filas
            lecturaFallida = false
            // Una copia eliminada no deja abierta su pantalla de detalle.
            ruta.removeAll { url in !filas.contains { $0.archivo.url == url } }
        } catch {
            guard !Task.isCancelled, lecturaActual == lectura else { return }
            lecturaFallida = true
        }
    }
}

// MARK: - Modelo de fila

struct FilaRespaldo: Identifiable, Sendable {
    var id: URL { archivo.url }
    let archivo: ArchivoRecuperacion
    /// nil si el archivo no se pudo interpretar (se puede compartir igual).
    let contenido: RespaldoDatos.Contenido?

    var titulo: String {
        contenido?.titulo ?? L.t("Archivo de respaldo", "Backup file")
    }

    var fechaTexto: String {
        guard let fecha = contenido?.fecha ?? archivo.fecha else { return L.t("Sin fecha disponible", "Date unavailable") }
        return FormatoFecha.formateador(patron: "d MMM yyyy, HH:mm", locale: FormatoFecha.localeActivo)
            .string(from: fecha)
    }

    var resumen: String {
        guard let contenido else { return L.t("No se pudo leer su contenido", "Its contents couldn't be read") }
        let categorias = contenido.categorias
        guard !categorias.isEmpty else { return L.t("Sin datos que restaurar", "Nothing to restore") }
        return categorias.map(\.titulo).joined(separator: ", ")
    }
}

struct AvisoRespaldo: Identifiable {
    let id = UUID()
    let titulo: String
    let mensaje: String
}

private struct FilaRespaldoView: View {
    let fila: FilaRespaldo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fila.titulo)
                .font(.subheadline.weight(.semibold))
            Text(fila.fechaTexto)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(fila.resumen)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detalle

private struct DetalleRespaldoView: View {
    let fila: FilaRespaldo?
    /// Avisa a la lista; recibe el mensaje que debe mostrar al volver.
    var alCambiar: (AvisoRespaldo?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seleccion: Set<RespaldoDatos.Categoria> = []
    @State private var confirmarRestaurar = false
    @State private var confirmarEliminar = false
    @State private var error: String?

    var body: some View {
        Group {
            if let fila {
                formulario(fila)
            } else {
                ContentUnavailableView(L.t("Respaldo no disponible", "Backup unavailable"), systemImage: "archivebox")
            }
        }
        .navigationTitle(fila?.titulo ?? L.t("Respaldo", "Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if seleccion.isEmpty { seleccion = Set(fila?.contenido?.categorias ?? []) }
        }
    }

    private func formulario(_ fila: FilaRespaldo) -> some View {
        Form {
            Section {
                LabeledContent(L.t("Fecha", "Date"), value: fila.fechaTexto)
                if let bytes = fila.archivo.bytes {
                    LabeledContent(L.t("Tamaño", "Size"),
                                   value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                }
                LabeledContent(L.t("Archivo", "File")) {
                    Text(fila.archivo.url.lastPathComponent)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }

            if let contenido = fila.contenido, !contenido.categorias.isEmpty {
                Section {
                    ForEach(contenido.categorias) { categoria in
                        Toggle(isOn: Binding(
                            get: { seleccion.contains(categoria) },
                            set: { activa in
                                if activa { seleccion.insert(categoria) } else { seleccion.remove(categoria) }
                            })) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(categoria.titulo)
                                    Text(contenido.resumen(categoria))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: categoria.icono).foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                } header: {
                    Text(L.t("Qué restaurar", "What to restore"))
                } footer: {
                    if contenido.ignoradas > 0 {
                        Text(L.f("Se ignoran {0} valores que esta versión de la app no reconoce.",
                                 "{0} values this version of the app doesn't recognize will be ignored.",
                                 ["\(contenido.ignoradas)"]))
                    }
                }

                Section {
                    Button {
                        confirmarRestaurar = true
                    } label: {
                        Label(L.t("Restaurar selección", "Restore selection"), systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 44)
                    }
                    .disabled(seleccion.isEmpty)
                } footer: {
                    Text(L.t("Antes de restaurar se guarda una copia automática de tus datos actuales: si cambias de opinión, restáurala desde esta lista.",
                             "Before restoring, an automatic copy of your current data is saved: if you change your mind, restore it from this list."))
                }
            } else {
                Section {
                    Text(fila.contenido == nil
                         ? L.t("No se pudo leer este archivo. Puedes compartirlo para conservarlo.",
                               "This file couldn't be read. You can share it to keep it.")
                         : L.t("Este respaldo no contiene datos que la app pueda restaurar. Puedes compartirlo para conservarlo.",
                               "This backup has no data the app can restore. You can share it to keep it."))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ShareLink(item: fila.archivo.url) {
                    Label(L.t("Compartir respaldo", "Share backup"), systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                Button(role: .destructive) {
                    confirmarEliminar = true
                } label: {
                    Label(L.t("Eliminar respaldo", "Delete backup"), systemImage: "trash")
                        .frame(minHeight: 44)
                }
            }
        }
        .confirmationDialog(L.t("¿Restaurar este respaldo?", "Restore this backup?"),
                            isPresented: $confirmarRestaurar, titleVisibility: .visible) {
            Button(L.t("Restaurar", "Restore"), role: .destructive) { restaurar(fila) }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L.f("Se sustituirán tus datos actuales de: {0}.", "Your current data will be replaced for: {0}.",
                     [ordenadas.map(\.titulo).joined(separator: ", ")]))
        }
        .confirmationDialog(L.t("¿Eliminar este respaldo?", "Delete this backup?"),
                            isPresented: $confirmarEliminar, titleVisibility: .visible) {
            Button(L.t("Eliminar", "Delete"), role: .destructive) { eliminar(fila) }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L.t("Se borrará del iPhone y no se puede deshacer. Las copias que hayas compartido se conservan.",
                     "It will be deleted from this iPhone and can't be undone. Copies you've shared are kept."))
        }
        .alert(L.t("No se pudo completar", "Couldn't complete"),
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var ordenadas: [RespaldoDatos.Categoria] {
        RespaldoDatos.Categoria.allCases.filter { seleccion.contains($0) }
    }

    private func restaurar(_ fila: FilaRespaldo) {
        guard let contenido = fila.contenido else { return }
        do {
            try RespaldoDatos.restaurar(contenido, categorias: seleccion)
            AppHaptics.success()
            let lista = ordenadas.map(\.titulo).joined(separator: ", ")
            alCambiar(AvisoRespaldo(
                titulo: L.t("Respaldo restaurado", "Backup restored"),
                mensaje: L.f("Se restauró: {0}. La copia de tus datos anteriores está en la lista.",
                             "Restored: {0}. A copy of your previous data is in the list.", [lista])))
            dismiss()
        } catch {
            AppHaptics.warning()
            self.error = RespaldoDatos.mensaje(error)
        }
    }

    private func eliminar(_ fila: FilaRespaldo) {
        do {
            try RespaldoDatos.eliminar(fila.archivo.url)
            AppHaptics.success()
            alCambiar(nil)
            dismiss()
        } catch {
            self.error = RespaldoDatos.mensaje(error)
        }
    }
}
