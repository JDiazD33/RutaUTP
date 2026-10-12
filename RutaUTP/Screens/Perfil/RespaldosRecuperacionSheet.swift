import SwiftUI

/// Las copias sobreviven a la pantalla que las creó; se releen desde disco.
struct RespaldosRecuperacionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var respaldos: [ArchivoRecuperacion] = []
    @State private var cargando = false
    @State private var lecturaFallida = false
    @State private var revision = 0
    @State private var lecturaActual = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L.t("Aquí están las copias de los datos originales que guardaste antes de reiniciar una sección. Puedes compartirlas para conservarlas fuera de la app.",
                             "Here are the copies of the original data you saved before resetting a section. You can share them to keep them outside the app."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if cargando {
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
                        description: Text(L.t("Las copias aparecerán aquí cuando respaldes y reinicies datos desde una sección.",
                                               "Copies will appear here when you back up and reset data from a section.")))
                } else {
                    Section(L.t("Respaldos guardados", "Saved backups")) {
                        ForEach(respaldos) { respaldo in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(respaldo.url.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                Text(fechaTexto(respaldo))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let bytes = respaldo.bytes {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ShareLink(item: respaldo.url) {
                                    Label(L.t("Compartir respaldo", "Share backup"),
                                          systemImage: "square.and.arrow.up")
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(minHeight: 44)
                                }
                                .accessibilityLabel(L.t("Compartir respaldo ", "Share backup ")
                                                    + respaldo.url.lastPathComponent)
                            }
                            .padding(.vertical, 6)
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
            .refreshable { await cargar() }
            .task(id: revision) { await cargar() }
        }
    }

    @MainActor
    private func cargar() async {
        let lectura = UUID()
        lecturaActual = lectura
        cargando = true
        defer { if lecturaActual == lectura { cargando = false } }
        do {
            let actuales = try await RecuperacionPreferencias.listar()
            guard !Task.isCancelled, lecturaActual == lectura else { return }
            respaldos = actuales
            lecturaFallida = false
        } catch {
            guard !Task.isCancelled, lecturaActual == lectura else { return }
            lecturaFallida = true
        }
    }

    private func fechaTexto(_ respaldo: ArchivoRecuperacion) -> String {
        guard let fecha = respaldo.fecha else { return L.t("Sin fecha disponible", "Date unavailable") }
        return FormatoFecha.formateador(patron: "d MMM yyyy, HH:mm", locale: FormatoFecha.localeActivo)
            .string(from: fecha)
    }
}
