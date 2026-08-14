//
//  PerfilView.swift
//  RutaUTP
//
//  Pantalla de perfil: hero gradient, stats, configuración con toggles.
//

import SwiftUI

struct PerfilView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var nombre: String = "Joaquín Díaz"
    @State private var notifOn: Bool = true
    @State private var ubicacionOn: Bool = true
    @State private var modoOffline: Bool = false
    @State private var showOfflineMapPopup: Bool = false
    @State private var mapsDownloaded: Bool = false
    @State private var showUbicacionPopup: Bool = false
    @State private var ubicacionPopupMensaje: String = ""
    @State private var ubicacionPopupSubtitulo: String = ""
    @State private var showEditAlert: Bool = false
    @State private var newNameInput: String = ""
    @State private var showDatosPersonales: Bool = false
    //  CORREGIDO V3: estado para Wallet
    @State private var showTarjetaSheet: Bool = false
    @State private var showCarnetScanner: Bool = false
    @State private var carnetVerificado: Bool = false
    @State private var metodoPagoGuardado: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            hero
                            statsCard
                                .padding(.horizontal, 20)
                                .offset(y: 45)
                        }
                        .frame(height: 420)

                        configuracion
                            .padding(.horizontal, 20)
                            .padding(.top, 56)
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
            Text("Ingresa tu nuevo nombre para actualizar tu perfil.")
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("SIN CONEXIÓN")
                        .font(.labelCapsSm)
                        .foregroundStyle(Color.orange)
                        .appTracking(AppTracking.wideLabel)
                    Text("• Modo Offline")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Text(mapsDownloaded ? "Mapas de Trujillo listos localmente" : "Operando con datos almacenados")
                    .font(.system(size: 11))
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
            Button {
                showOfflineMapPopup = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: mapsDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(mapsDownloaded ? "Mapas OK" : "Descargar")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
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
    }

    // MARK: - Hero
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 420)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: 230, y: -70)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 150, height: 150)
                .offset(x: -50, y: 50)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 56)

                // Avatar + Nombre + Rol
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.inversePrimary)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        Text(iniciales(nombre))
                            .font(.headlineMd)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(nombre)
                            .font(.headlineLgMobile)
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text("ESTUDIANTE UTP")
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
                                    Text("VERIFICADO")
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

                // Mi Wallet integrado debajo del nombre
                VStack(alignment: .leading, spacing: 10) {
                    Text("MI BILLETERA")
                        .font(.labelCapsSm)
                        .foregroundStyle(.white.opacity(0.85))
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 4)

                    HStack(spacing: 12) {
                        // Tarjeta de pago translúcida
                        Button {
                            showTarjetaSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Método Pago")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(metodoPagoGuardado.map { "Visa •••• \($0)" } ?? "Agregar tarjeta")
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

                        // Carnet UTP translúcido
                        Button {
                            showCarnetScanner = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.text.rectangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Carnet UTP")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(carnetVerificado ? "Verificado" : "Escanear ahora")
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

    // MARK: - Stats
    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(value: "47", label: "VIAJES")
            divider
            statColumn(value: "12", label: "RUTAS")
            divider
            statColumn(value: "3", label: "LOGROS")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.50))
            .frame(width: 1, height: 36)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.displayNumberMd)
                .foregroundStyle(.onSurface)
            Text(label)
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Configuración
    private var configuracion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferencias")
                .font(.labelCapsLg)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                toggleRow(icon: "bell.fill", iconColor: .appPrimary,
                          label: "Notificaciones", isOn: $notifOn)
                Divider().padding(.leading, 56)
                toggleRow(icon: "mappin.circle.fill", iconColor: .secondary,
                          label: "Compartir ubicación", isOn: $ubicacionOn)
                Divider().padding(.leading, 56)
                toggleRow(icon: "wifi.slash", iconColor: .orange,
                          label: "Modo offline", isOn: $modoOffline)
                Divider().padding(.leading, 56)
                chevronRow(icon: "pencil", iconColor: .onSurfaceVariant,
                           label: "Editar perfil") {
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
        }
    }

    private func toggleRow(icon: String, iconColor: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)
            }
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
                Text(label)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
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
                        Text("Descargando mapas locales...")
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
                        Text(mapsDownloaded ? "Entendido, cerrar" : (isDownloading ? "Descargando..." : "Descargar Mapas (40 MB)"))
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
                        Text("Ahora no")
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

#Preview {
    PerfilView().environmentObject(AppRouter())
}

