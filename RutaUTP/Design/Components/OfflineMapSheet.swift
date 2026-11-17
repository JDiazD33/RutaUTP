//
//  OfflineMapSheet.swift
//  RutaUTP
//
//  Modo offline: estado real de la conexión, interruptor y datos disponibles.
//
//  Vivía dentro de `PerfilView`, que era su único acceso. Se saca aquí para
//  que el aviso de «caminata estimada» de Mapa y Tracking pueda ofrecerlo: son
//  justo las pantallas donde el usuario se topa con la limitación.
//
//  El estado lo da `ConectividadService` (NWPathMonitor). Sin red, o con el
//  interruptor activado, el Mapa busca entre paraderos y lugares guardados y
//  estima las caminatas sin consultar Apple Maps.
//

import SwiftUI

// MARK: - Disponibilidad real de datos locales
struct OfflineMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var conectividad = ConectividadService.shared
    @State private var comprobando = true
    @State private var numeroRutas = 0
    @State private var numeroParaderos = 0
    @State private var revision = 0
    @State private var errorCarga: String?
    @State private var guardados = RespaldoDatos.ResumenLocal()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    estadoConexion
                }

                Section {
                    Toggle(isOn: $conectividad.modoOfflineManual) {
                        Label(L.t("Modo offline", "Offline mode"), systemImage: "wifi.slash")
                    }
                } footer: {
                    Text(L.t("Úsalo con mala señal o para ahorrar datos: el Mapa deja de consultar Apple Maps, busca entre paraderos y lugares guardados y estima las caminatas al instante. Si pierdes la conexión, se aplica solo.",
                             "Use it with poor signal or to save data: the Map stops querying Apple Maps, searches stops and saved places, and estimates walks instantly. If you lose your connection, it applies automatically."))
                }

                Section {
                    filaDato(L.t("Rutas y recorridos", "Routes"), icono: "bus.fill",
                             valor: comprobando ? nil : "\(numeroRutas)")
                    filaDato(L.t("Paraderos para buscar", "Searchable stops"), icono: "mappin.and.ellipse",
                             valor: comprobando ? nil : "\(numeroParaderos)")
                    filaDato(L.t("Lugares guardados", "Saved places"), icono: "bookmark.fill",
                             valor: "\(guardados.lugares)")
                    filaDato(L.t("Líneas guardadas", "Saved lines"), icono: "point.topleft.down.to.point.bottomright.curvepath",
                             valor: "\(guardados.lineas)")
                    filaDato(L.t("Contacto de emergencia", "Emergency contact"), icono: "person.crop.circle.badge.checkmark",
                             valor: guardados.contactoConfigurado ? L.t("Configurado", "Set up") : L.t("Sin configurar", "Not set up"))
                } header: {
                    Text(L.t("Guardado en este iPhone", "Stored on this iPhone"))
                } footer: {
                    if let errorCarga {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorCarga)
                            Button(L.t("Reintentar", "Retry")) { revision += 1 }
                                .frame(minHeight: 44)
                        }
                    } else if !comprobando && numeroRutas == 0 && TransporteApp.rutasUTPPendientes {
                        Text(TransporteApp.mensajePendiente)
                    } else {
                        Text(L.t("Los recorridos y paraderos vienen incluidos en la app; no hace falta descargarlos.",
                                 "Routes and stops ship with the app; there's nothing to download."))
                    }
                }

                Section(L.t("Funciona sin conexión", "Works offline")) {
                    funcion(L.t("Buscar destino entre paraderos y lugares guardados", "Search for a destination among stops and saved places"),
                            icono: "magnifyingglass")
                    funcion(L.t("Calcular la ruta en micro con los recorridos del iPhone", "Plan the bus route with the routes on this iPhone"),
                            icono: "bus")
                    funcion(L.t("Estimar la caminata en línea recta", "Estimate the walk in a straight line"),
                            icono: "figure.walk")
                    funcion(L.t("Ver tus lugares, líneas y respaldos guardados", "View your saved places, lines and backups"),
                            icono: "archivebox")
                    funcion(L.t("Llamar al 105 o a tu contacto de emergencia (usa la red telefónica)", "Call 105 or your emergency contact (uses the phone network)"),
                            icono: "phone")
                }

                Section {
                    funcion(L.t("Buscar direcciones y lugares en Apple Maps", "Search addresses and places in Apple Maps"),
                            icono: "map")
                    funcion(L.t("Indicaciones de caminata calle por calle", "Street-by-street walking directions"),
                            icono: "figure.walk.motion")
                    funcion(L.t("Comisarías, salud y bomberos cercanos", "Nearby police, healthcare and fire stations"),
                            icono: "cross.case")
                    funcion(L.t("Alertas de cambios de ruta", "Route change alerts"),
                            icono: "exclamationmark.bubble")
                } header: {
                    Text(L.t("Necesita conexión", "Requires a connection"))
                } footer: {
                    Text(L.t("El mapa base de Apple solo se muestra si ya está en caché. La app no descarga mapas para usarlos sin conexión.",
                             "Apple's base map only appears if it's already cached. The app doesn't download maps for offline use."))
                }
            }
            .navigationTitle(L.t("Modo offline", "Offline mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
        }
        .tint(Color.appAccent)
        .task(id: revision) { await cargar() }
    }

    // MARK: Estado

    private var estadoConexion: some View {
        let (titulo, detalle, icono, color) = descripcionEstado
        return HStack(spacing: 14) {
            Image(systemName: icono)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.headline)
                Text(detalle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var descripcionEstado: (String, String, String, Color) {
        switch conectividad.estado {
        case .comprobando:
            return (L.t("Comprobando conexión…", "Checking connection…"),
                    L.t("Mientras tanto, la app funciona con normalidad.", "The app works normally meanwhile."),
                    "network", .secondary)
        case .sinConexion:
            return (L.t("Sin conexión", "No connection"),
                    L.t("La app usa los datos guardados en este iPhone.", "The app uses the data stored on this iPhone."),
                    "wifi.slash", .appError)
        case .conectado:
            if conectividad.modoOfflineManual {
                return (L.t("Modo offline activado", "Offline mode on"),
                        L.t("Hay conexión, pero la app usa solo los datos de este iPhone.",
                            "You're connected, but the app only uses data on this iPhone."),
                        "wifi.slash", .appAccent)
            }
            let titulo: String
            let icono: String
            switch conectividad.interfaz {
            case .wifi?:
                titulo = L.t("Conectado por Wi-Fi", "Connected via Wi-Fi"); icono = "wifi"
            case .datosMoviles?:
                titulo = L.t("Conectado por datos móviles", "Connected via mobile data"); icono = "antenna.radiowaves.left.and.right"
            default:
                titulo = L.t("Conectado a internet", "Connected to the internet"); icono = "network"
            }
            let detalle = conectividad.datosLimitados
                ? L.t("Conexión con datos limitados: el Modo offline te ayuda a ahorrarlos.",
                      "Limited data connection: Offline mode helps you save data.")
                : L.t("Si pierdes la señal, la app pasa sola a los datos del iPhone.",
                      "If you lose signal, the app switches to on-device data automatically.")
            return (titulo, detalle, icono, .appAccent)
        }
    }

    // MARK: Filas

    private func filaDato(_ titulo: String, icono: String, valor: String?) -> some View {
        LabeledContent {
            if let valor {
                Text(valor).monospacedDigit()
            } else {
                ProgressView()
                    .accessibilityLabel(L.t("Comprobando", "Checking"))
            }
        } label: {
            Label(titulo, systemImage: icono)
        }
    }

    private func funcion(_ texto: String, icono: String) -> some View {
        Label {
            Text(texto).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icono).foregroundStyle(Color.appAccent)
        }
    }

    // MARK: Carga

    @MainActor
    private func cargar() async {
        guardados = RespaldoDatos.resumenLocal()
        comprobando = true
        errorCarga = nil
        do {
            let rutas = try await TransporteApp.repositorio.cargarRutas(reintentar: revision > 0)
            guard !Task.isCancelled else { return }
            numeroRutas = rutas.count
            await IndiceLocalDestinos.shared.preparar(TransporteApp.repositorio)
            guard !Task.isCancelled else { return }
            numeroParaderos = IndiceLocalDestinos.shared.numeroParaderos
        } catch {
            guard !Task.isCancelled else { return }
            errorCarga = (error as? FalloCargaGTFS)?.mensajeUsuario
                ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
        }
        comprobando = false
    }
}
