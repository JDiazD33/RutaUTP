//
//  PerfilView.swift
//  RutaUTP
//
//  Pantalla de perfil: hero gradient con billetera, configuración con toggles.
//

import SwiftUI
import UIKit

struct PerfilView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var nombre: String = "Joaquín Díaz"
    @State private var notifOn: Bool = true
    @State private var ubicacionOn: Bool = true
    /// Modo Señas. Se lee desde varias pantallas, por eso va en AppStorage
    /// y no en @State: cualquier vista reacciona al cambio al instante.
    @AppStorage(SeniasService.llaveModo) private var modoSenias: Bool = false
    @State private var showOfflineMapPopup: Bool = false
    @State private var showUbicacionPopup: Bool = false
    @State private var ubicacionPopupMensaje: String = ""
    @State private var ubicacionPopupSubtitulo: String = ""
    @State private var showEditAlert: Bool = false
    @State private var newNameInput: String = ""
    @State private var showDatosPersonales: Bool = false
    @State private var showVoiceOverHelp: Bool = false
    //  CORREGIDO V3: estado para Wallet
    @State private var showTarjetaSheet: Bool = false
    @State private var showCarneDigital: Bool = false
    @State private var showCarnetScanner: Bool = false
    @State private var carnetGuardado: Bool = false
    @StateObject private var tarjetasStore = TarjetasStore()
    /// Misma foto que en el drawer: ProfileImageStore es la fuente única.
    @State private var fotoPerfil: UIImage? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero

                        PerfilCuponesGuardados()
                            .padding(.top, 24)

                        configuracion
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        Spacer(minLength: 140)
                    }
                }
                .padding(.bottom, 64)

                BottomNavBar()
            }

        }
        .ignoresSafeArea(edges: .bottom)
        // Foto de perfil: recargar al entrar y al volver de Datos Personales.
        .onAppear {
            fotoPerfil = ProfileImageStore.load()
            carnetGuardado = CarnetImageStore.load() != nil
            // Solo DEBUG: abre directo el Carné Digital, p.ej.
            // xcrun simctl launch ... apolito.RutaUTP --pantalla perfil --carne
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--carne") { showCarneDigital = true }
            #endif
        }
        .onChange(of: showDatosPersonales) { abierto in
            if !abierto { fotoPerfil = ProfileImageStore.load() }
        }
        // La foto puede cambiar dentro del Carné Digital: recargar al cerrar.
        .onChange(of: showCarneDigital) { abierto in
            if !abierto { fotoPerfil = ProfileImageStore.load() }
        }
        .onChange(of: ubicacionOn) { activo in
            if activo {
                ubicacionPopupMensaje = "Ubicación compartida"
                ubicacionPopupSubtitulo = "Tu ubicación en tiempo real se compartirá para el seguimiento de rutas UTP."
            } else {
                ubicacionPopupMensaje = "Sin ubicación compartida"
                ubicacionPopupSubtitulo = "Tu ubicación en tiempo real no se compartirá con otros usuarios."
            }
            showUbicacionPopup = true
        }
        .alert(ubicacionPopupMensaje, isPresented: $showUbicacionPopup) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text(ubicacionPopupSubtitulo)
        }
        .alert("Editar nombre", isPresented: $showEditAlert) {
            TextField("Nombre completo", text: $newNameInput)
            Button("Guardar") {
                if !newNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nombre = newNameInput
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(L.t("Ingresa tu nuevo nombre para actualizar tu perfil.", "Enter your new name to update your profile."))
        }
        // Sheet de Tarjeta
        .sheet(isPresented: $showTarjetaSheet) {
            MetodosPagoSheet(store: tarjetasStore)
            .presentationDetents([.large])
        }
        // Sheet del Carné Digital (identificación con código de barras)
        .sheet(isPresented: $showCarneDigital) {
            CarneDigitalView(nombre: nombre)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        // Scanner de Carnet
        .fullScreenCover(isPresented: $showCarnetScanner) {
            CarnetScannerView {
                carnetGuardado = true
            }
        }
        // Sheet de Datos Personales (reutilizado del SideDrawer)
        .sheet(isPresented: $showDatosPersonales) {
            DatosPersonalesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Disponibilidad y límites de los datos sin conexión
        .sheet(isPresented: $showOfflineMapPopup) {
            OfflineMapSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        // Sheet con instrucciones para activar VoiceOver
        .sheet(isPresented: $showVoiceOverHelp) {
            VoiceOverHelpSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Banner Sin Conexión (Top)
    // MARK: - Hero
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 420)
            .accessibilityHidden(true)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: 230, y: -70)
                .accessibilityHidden(true)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 150, height: 150)
                .offset(x: -50, y: 50)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 56)

                // Avatar + Nombre + Rol
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.inversePrimary)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        if let fotoPerfil {
                            Image(uiImage: fotoPerfil)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .accessibilityHidden(true)
                        } else {
                            Text(iniciales(nombre))
                                .font(.headlineMd)
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel("Foto de perfil, \(iniciales(nombre))")
                    .accessibilityAddTraits(.isImage)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(nombre)
                            .font(.headlineLgMobile)
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text(L.t("ESTUDIANTE UTP", "UTP STUDENT"))
                                .font(.labelCapsSm)
                                .foregroundStyle(.white.opacity(0.95))
                                .appTracking(AppTracking.wideLabel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.20)))
                            if carnetGuardado {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .accessibilityHidden(true)
                                    Text(L.t("CARNÉ GUARDADO", "CARD SAVED"))
                                        .font(.labelCapsSm)
                                        .appTracking(AppTracking.wideLabel)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.tertiary))
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(nombre), estudiante UTP\(carnetGuardado ? ", carné guardado" : "")")
                .accessibilityAddTraits(.isHeader)

                // Mi Wallet integrado debajo del nombre
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("MI BILLETERA", "MY WALLET"))
                        .font(.labelCapsSm)
                        .foregroundStyle(.white.opacity(0.85))
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 12) {
                        // Tarjeta de pago translúcida
                        Button {
                            AppHaptics.impact(.light)
                            showTarjetaSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.t("Método Pago", "Payment"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(tarjetasStore.principal?.etiqueta ?? L.t("Agregar tarjeta", "Add card"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Método de pago")
                        .accessibilityValue(tarjetasStore.principal?.etiqueta ?? "Sin tarjeta, agregar")
                        .accessibilityHint("Doble toque para administrar tu tarjeta")

                        // Carnet UTP translúcido
                        Button {
                            AppHaptics.impact(.light)
                            showCarnetScanner = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.text.rectangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.t("Carnet Universitario", "University Card"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(carnetGuardado ? L.t("Ver foto guardada", "View saved photo") : L.t("Añadir foto", "Add photo"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Carné Digital: debajo del método de pago
                    Button {
                        AppHaptics.impact(.light)
                        showCarneDigital = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("Carné Digital", "Digital ID"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(L.t("Tu identificación para ingresar al campus", "Your ID to enter the campus"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Carné Digital", "Digital ID"))
                    .accessibilityHint(L.t("Doble toque para mostrar tu identificación con código de barras", "Double tap to show your ID with barcode"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                Spacer()
            }
        }
    }

    // MARK: - Configuración
    private var configuracion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Preferencias", "Preferences"))
                .font(.labelCapsLg)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                toggleRow(icon: "bell.fill", iconColor: .appPrimary,
                          label: L.t("Notificaciones", "Notifications"), isOn: $notifOn)
                Divider().padding(.leading, 56).accessibilityHidden(true)
                toggleRow(icon: "mappin.circle.fill", iconColor: .secondary,
                          label: L.t("Compartir ubicación", "Share location"), isOn: $ubicacionOn)
                Divider().padding(.leading, 56).accessibilityHidden(true)
                offlineToggleRow
                Divider().padding(.leading, 56).accessibilityHidden(true)
                toggleRow(icon: "hand.raised.fill", iconColor: .purple,
                          label: L.signable("perfil.modo_senias", "Modo Señas", "Sign Language Mode"), isOn: $modoSenias)
                    .seniable("perfil.modo_senias")
                Divider().padding(.leading, 56).accessibilityHidden(true)
                chevronRow(icon: "pencil", iconColor: .onSurfaceVariant,
                           label: L.t("Editar perfil", "Edit profile")) {
                    AppHaptics.impact(.light)
                    showDatosPersonales = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                    )
            )

            // ── Accesibilidad (VoiceOver) ──
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("Accesibilidad", "Accessibility"))
                    .font(.labelCapsLg)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    accesibilidadRow()
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surfaceContainerLowest)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    // MARK: - Fila Accesibilidad (VoiceOver)
    @ViewBuilder
    private func accesibilidadRow() -> some View {
        let voiceOverOn = UIAccessibility.isVoiceOverRunning
        Button {
            AppHaptics.impact(.light)
            if voiceOverOn {
                // Ya está activo: abrir ajustes de la app (por si quiere ajustar algo)
                abrirAjustesIOS()
            } else {
                // Mostrar instrucciones + botón a Ajustes
                showVoiceOverHelp = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: voiceOverOn ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("VoiceOver", "VoiceOver"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(voiceOverOn ? "Activado" : "Desactivado")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("VoiceOver")
        .accessibilityValue(voiceOverOn ? "Activado" : "Desactivado")
        .accessibilityHint("Doble toque para ver cómo activar VoiceOver en tu iPhone")
    }

    private func abrirAjustesIOS() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func toggleRow(icon: String, iconColor: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            Text(label)
                .font(.bodyMdMedium)
                .foregroundStyle(.onSurface)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.appPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "Activado" : "Desactivado")
        .accessibilityHint("Doble toque para cambiar")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Disponibilidad sin conexión
    private var offlineToggleRow: some View {
        Button {
            AppHaptics.impact(.light)
            showOfflineMapPopup = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Modo offline", "Offline mode"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(L.t("Consulta qué puedes usar sin internet", "See what works without internet"))
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chevronRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.14)).frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)
                Text(label)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Doble toque para abrir")
    }

    // MARK: - Helpers
    private func iniciales(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0) }.joined()
    }
}

// MARK: - Disponibilidad real de datos locales
private struct OfflineMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var comprobando = true
    @State private var numeroRutas = 0
    @State private var revision = 0

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
                            : L.t("No se pudieron cargar las rutas", "Couldn't load routes"))
                        .font(.title2.bold())
                    if comprobando {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if numeroRutas > 0 {
                        Label(L.t("\(numeroRutas) rutas cargadas desde la app", "\(numeroRutas) routes loaded from the app"), systemImage: "bus.fill")
                        Text(L.t("Los recorridos y paraderos vienen incluidos en la app. No necesitas descargarlos ni activar un interruptor para consultarlos sin internet.", "Routes and stops are included in the app. No download or switch is needed to view them offline."))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L.t("No podemos confirmar que los datos de rutas estén disponibles. Vuelve a intentarlo o actualiza la app.", "We couldn't confirm route data availability. Try again or update the app."))
                            .foregroundStyle(.secondary)
                        Button(L.t("Reintentar", "Retry")) { revision += 1 }
                            .buttonStyle(.bordered)
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
            let rutas = await GTFSRepository.shared.rutas()
            guard !Task.isCancelled else { return }
            numeroRutas = rutas.count
            comprobando = false
        }
    }
}

// MARK: - Sheet de ayuda para activar VoiceOver
private struct VoiceOverHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let pasos: [(icon: String, texto: String)] = [
        ("gearshape.fill", L.t("Abre la app Ajustes de tu iPhone", "Open your iPhone Settings app")),
        ("hand.point.right.fill", L.t("Toca Accesibilidad", "Tap Accessibility")),
        ("speaker.wave.2.fill", L.t("Toca VoiceOver, primera opción", "Tap VoiceOver, first option")),
        ("togglepower", L.t("Activa el interruptor VoiceOver", "Turn on the VoiceOver switch"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                .accessibilityHidden(true)
                Text(L.t("Activar VoiceOver", "Enable VoiceOver"))
                    .font(.headlineMd)
                    .foregroundStyle(.onSurface)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(L.t("VoiceOver lee en voz alta lo que tocas en pantalla. Sigue estos pasos para activarlo en tu iPhone:", "VoiceOver reads aloud what you touch on screen. Follow these steps to enable it on your iPhone:"))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(pasos.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.10))
                                .frame(width: 32, height: 32)
                            Image(systemName: pasos[i].icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.appPrimary)
                        }
                        .accessibilityHidden(true)
                        Text("\(i + 1). \(pasos[i].texto)")
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Paso \(i + 1): \(pasos[i].texto)")
                }
            }

            Spacer()

            Button {
                AppHaptics.impact(.light)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .accessibilityHidden(true)
                    Text(L.t("Abrir Ajustes del iPhone", "Open iPhone Settings"))
                }
                .font(.bodyMdMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir Ajustes del iPhone")
            .accessibilityHint("Doble toque para ir directamente a la configuración de la app")

            Button {
                dismiss()
            } label: {
                Text(L.t("Cerrar", "Close"))
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar instrucciones")
        }
        .padding(20)
    }
}

#Preview {
    PerfilView().environmentObject(AppRouter())
}



// MARK: - Cupones de los negocios del Tracking Demo

private struct PerfilCuponesGuardados: View {
    @EnvironmentObject private var router: AppRouter
    @State private var negocios: [Negocio] = []
    @State private var seleccionado: Negocio?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Color.appPrimary)
                Text(L.t("Mis cupones", "My coupons"))
                    .font(.title3.bold())
                Spacer()
                Text("\(negocios.count)")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.appPrimary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 20)

            Text(L.t("Tus promociones guardadas en Tracking Demo.",
                     "Your saved offers from Tracking Demo."))
                .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                .padding(.horizontal, 20)

            if negocios.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "ticket")
                        .font(.system(size: 32)).foregroundStyle(Color.appPrimary)
                    Text(L.t("Tu próxima promo te espera", "Your next offer awaits"))
                        .font(.headline)
                    Text(L.t("Abre un negocio en el mapa y toca Guardar en su cupón. Aparecerá aquí.",
                             "Open a business on the map and tap Save on its coupon. It will appear here."))
                        .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    Button {
                        router.navigate(to: .trackingDemo)
                    } label: {
                        Label(L.t("Explorar negocios", "Explore businesses"), systemImage: "map.fill")
                            .font(.subheadline.bold()).padding(.vertical, 10).padding(.horizontal, 16)
                            .foregroundStyle(.white)
                            .background(Color.appPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity).padding(22)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(negocios) { negocio in
                            PerfilCuponCard(negocio: negocio) { seleccionado = negocio }
                                .frame(width: 285)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20).padding(.bottom, 4)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .foregroundStyle(Color.onSurface)
        .onAppear(perform: actualizar)
        .onReceive(NotificationCenter.default.publisher(for: NegociosService.cuponesActualizados)
            .receive(on: RunLoop.main)) { _ in actualizar() }
        .sheet(item: $seleccionado, onDismiss: actualizar) { negocio in
            ScrollView {
                NegocioDetailCard(negocio: negocio, ubicacion: nil) { seleccionado = nil }
                    .padding(20)
            }
            .background(Color.appBackground)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .seguirTemaForzado()
        }
    }

    private func actualizar() {
        negocios = NegociosService.shared.cuponesGuardados()
    }
}

private struct PerfilCuponCard: View {
    let negocio: Negocio
    let abrir: () -> Void
    @State private var copiado = false

    var body: some View {
        if let cupon = negocio.cupon {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: abrir) {
                    HStack(spacing: 10) {
                        NegocioIcono(categoria: negocio.categoria, size: 26)
                            .foregroundStyle(Color.onSurface)
                            .frame(width: 50, height: 50)
                            .background(negocio.categoria.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(negocio.nombre).font(.headline).lineLimit(2)
                            Text(negocio.categoria.etiqueta)
                                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(cupon.detalle.texto)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Label(cupon.vigente ? L.t("Guardado", "Saved") : L.t("Vencido", "Expired"),
                          systemImage: cupon.vigente ? "bookmark.fill" : "clock.badge.exclamationmark")
                    Spacer()
                    Text(L.t("Cupón demo", "Demo coupon"))
                }
                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                if let fecha = cupon.fechaVencimiento {
                    Text(L.t("Vence: ", "Expires: ") + fecha.formatted(
                        .dateTime.day().month(.abbreviated).year()
                            .locale(Locale(identifier: IdiomaManager.shared.esIngles ? "en_US" : "es_PE"))))
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                Rectangle().fill(negocio.categoria.color.opacity(0.25)).frame(height: 1)
                Button {
                    UIPasteboard.general.string = cupon.codigo
                    copiado = true
                    AppHaptics.success()
                } label: {
                    HStack {
                        Text(cupon.codigo).font(.system(.body, design: .monospaced).bold())
                        Spacer()
                        Image(systemName: copiado ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    .padding(12)
                    .background(negocio.categoria.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!cupon.vigente)
                .accessibilityLabel(L.t("Copiar código ", "Copy code ") + cupon.codigo)
                if copiado {
                    Text(L.t("Código copiado", "Code copied"))
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                HStack {
                    Button(L.t("Ver promoción", "View offer"), action: abrir)
                        .font(.subheadline.bold()).foregroundStyle(negocio.categoria.color)
                    Spacer()
                    Button(role: .destructive) {
                        NegociosService.shared.quitarCupon(negocio)
                    } label: {
                        Image(systemName: "bookmark.slash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L.t("Quitar cupón de ", "Remove coupon from ") + negocio.nombre)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24)
                .stroke(negocio.categoria.color.opacity(0.22), lineWidth: 1))
        }
    }
}
