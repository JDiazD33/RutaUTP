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
    @State private var modoOffline: Bool = false
    /// Modo Señas. Se lee desde varias pantallas, por eso va en AppStorage
    /// y no en @State: cualquier vista reacciona al cambio al instante.
    @AppStorage(SeniasService.llaveModo) private var modoSenias: Bool = false
    @State private var showOfflineMapPopup: Bool = false
    @State private var mapsDownloaded: Bool = false
    @State private var showUbicacionPopup: Bool = false
    @State private var ubicacionPopupMensaje: String = ""
    @State private var ubicacionPopupSubtitulo: String = ""
    @State private var showEditAlert: Bool = false
    @State private var newNameInput: String = ""
    @State private var showDatosPersonales: Bool = false
    @State private var showVoiceOverHelp: Bool = false
    //  CORREGIDO V3: estado para Wallet
    @State private var showTarjetaSheet: Bool = false
    @State private var showCarnetScanner: Bool = false
    @State private var carnetVerificado: Bool = false
    @State private var metodoPagoGuardado: String? = nil
    /// Misma foto que en el drawer: ProfileImageStore es la fuente única.
    @State private var fotoPerfil: UIImage? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero

                        configuracion
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        Spacer(minLength: 140)
                    }
                }
                .padding(.bottom, 64)

                BottomNavBar()
            }

            // ── BANNER "SIN CONEXIÓN" (Top Banner en Modo Offline) ──
            if modoOffline {
                offlineTopBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.28), value: modoOffline)
        .onChange(of: modoOffline) { activo in
            if activo {
                showOfflineMapPopup = true
            }
        }
        // Foto de perfil: recargar al entrar y al volver de Datos Personales.
        .onAppear { fotoPerfil = ProfileImageStore.load() }
        .onChange(of: showDatosPersonales) { abierto in
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
            TarjetaFormSheet { numero in
                let ultimos4 = numero.filter { $0.isNumber }.suffix(4)
                metodoPagoGuardado = String(ultimos4)
            }
            .presentationDetents([.large])
        }
        // Scanner de Carnet
        .fullScreenCover(isPresented: $showCarnetScanner) {
            CarnetScannerView {
                carnetVerificado = true
            }
        }
        // Sheet de Datos Personales (reutilizado del SideDrawer)
        .sheet(isPresented: $showDatosPersonales) {
            DatosPersonalesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Sheet Modal de Descarga de Mapas Offline
        .sheet(isPresented: $showOfflineMapPopup) {
            OfflineMapSheet(mapsDownloaded: $mapsDownloaded)
                .presentationDetents([.medium, .large])
        }
        // Sheet con instrucciones para activar VoiceOver
        .sheet(isPresented: $showVoiceOverHelp) {
            VoiceOverHelpSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Banner Sin Conexión (Top)
    private var offlineTopBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.20))
                    .frame(width: 32, height: 32)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orange)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L.t("SIN CONEXIÓN", "OFFLINE"))
                        .font(.labelCapsSm)
                        .foregroundStyle(Color.orange)
                        .appTracking(AppTracking.wideLabel)
                    Text(L.t("• Modo Offline", "• Offline Mode"))
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Text(mapsDownloaded ? "Mapas de Trujillo listos localmente" : "Operando con datos almacenados")
                    .font(.system(size: 11))
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
            Button {
                AppHaptics.impact(.light)
                showOfflineMapPopup = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: mapsDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(mapsDownloaded ? "Mapas OK" : "Descargar")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mapsDownloaded ? "Mapas descargados correctamente" : "Descargar mapas offline")
            .accessibilityHint("Doble toque para administrar los mapas locales")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.40), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 50)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aviso: sin conexión, modo offline activo")
        .accessibilityAddTraits(.updatesFrequently)
    }

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
                            if carnetVerificado {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .accessibilityHidden(true)
                                    Text(L.t("VERIFICADO", "VERIFIED"))
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
                .accessibilityLabel("\(nombre), estudiante UTP\(carnetVerificado ? ", carnet verificado" : "")")
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
                                    Text(metodoPagoGuardado.map { "Visa •••• \($0)" } ?? L.t("Agregar tarjeta", "Add card"))
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
                        .accessibilityValue(metodoPagoGuardado.map { "Visa terminación \($0)" } ?? "Sin tarjeta, agregar")
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
                                    Text(L.t("Carnet UTP", "UTP Card"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(carnetVerificado ? "Verificado" : L.t("Escanear ahora", "Scan now"))
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
                toggleRow(icon: "wifi.slash", iconColor: .orange,
                          label: L.t("Modo offline", "Offline mode"), isOn: $modoOffline)
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

// MARK: - Sheet Modal de Descarga de Mapas Offline
private struct OfflineMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var mapsDownloaded: Bool
    @State private var isDownloading: Bool = false
    @State private var progress: Double = 0.0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.appPrimary.opacity(0.20), Color.orange.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: mapsDownloaded ? "checkmark.seal.fill" : "map.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(mapsDownloaded ? Color.green : Color.appPrimary)
            }
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text(mapsDownloaded ? "Mapas Offline Descargados" : "Descargar Mapas Locales")
                    .font(.headlineLgMobile)
                    .foregroundStyle(.onSurface)
                Text(
                    mapsDownloaded
                    ? "Tienes el mapa de Trujillo y campus UTP guardado. Puedes navegar completamente sin conexión a internet."
                    : "Descarga los mapas del campus UTP y rutas de Trujillo para continuar navegando aun cuando te quedes sin datos o señal."
                )
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                mapPackageRow(
                    icon: "graduationcap.fill",
                    title: "Campus UTP Trujillo",
                    detail: "Edificios, pabellones y paraderos • 12 MB"
                )
                mapPackageRow(
                    icon: "bus.fill",
                    title: "Rutas de Transporte Urbano",
                    detail: "Líneas 10, 4 y paraderos cercanos • 28 MB"
                )
            }

            if isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        Text(L.t("Descargando mapas locales...", "Downloading local maps..."))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.onSurface)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                    }
                    ProgressView(value: progress)
                        .tint(Color.appPrimary)
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    if mapsDownloaded {
                        dismiss()
                    } else {
                        iniciarDescarga()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mapsDownloaded ? "checkmark.circle.fill" : (isDownloading ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill"))
                        Text(mapsDownloaded ? L.t("Entendido, cerrar", "Got it, close") : (isDownloading ? L.t("Descargando...", "Downloading...") : L.t("Descargar Mapas (40 MB)", "Download Maps (40 MB)")))
                    }
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(mapsDownloaded ? Color.green : Color.appPrimary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)

                if !isDownloading && !mapsDownloaded {
                    Button {
                        dismiss()
                    } label: {
                        Text(L.t("Ahora no", "Not now"))
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .background(Color.appSurface)
    }

    private func mapPackageRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.surfaceContainerHigh)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.onSurface)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
            Image(systemName: mapsDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundStyle(mapsDownloaded ? Color.green : Color.onSurfaceVariant.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceContainerLow)
        )
    }

    private func iniciarDescarga() {
        isDownloading = true
        progress = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { timer in
            progress += 0.08
            if progress >= 1.0 {
                progress = 1.0
                timer.invalidate()
                isDownloading = false
                mapsDownloaded = true
            }
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

