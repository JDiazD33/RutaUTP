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
    @State private var ecoOff: Bool = false
    @State private var showEditAlert: Bool = false
    @State private var newNameInput: String = ""
    //  CORREGIDO V3: estado para Wallet
    @State private var showTarjetaSheet: Bool = false
    @State private var showCarnetScanner: Bool = false
    @State private var carnetVerificado: Bool = false
    @State private var metodoPagoGuardado: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

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
                        .padding(.top, 24)
                    Spacer(minLength: 140)
                }
            }
            .padding(.bottom, 64)

            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
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
        //  CORREGIDO V3: sheet de tarjeta
        .sheet(isPresented: $showTarjetaSheet) {
            TarjetaFormSheet { numero in
                let ultimos4 = numero.filter { $0.isNumber }.suffix(4)
                metodoPagoGuardado = String(ultimos4)
            }
            .presentationDetents([.large])
        }
        //  CORREGIDO V3: scanner de carnet
        .fullScreenCover(isPresented: $showCarnetScanner) {
            CarnetScannerView {
                carnetVerificado = true
            }
        }
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
                            //  CORREGIDO V3: badge Verificado
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
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                toggleRow(icon: "bell.fill", iconColor: .appPrimary,
                          label: "Notificaciones", isOn: $notifOn)
                Divider().padding(.leading, 56)
                toggleRow(icon: "mappin.circle.fill", iconColor: .secondary,
                          label: "Compartir ubicación", isOn: $ubicacionOn)
                Divider().padding(.leading, 56)
                toggleRow(icon: "creditcard.fill", iconColor: .tertiary,
                          label: "Modo económico", isOn: $ecoOff)
                Divider().padding(.leading, 56)
                chevronRow(icon: "person.crop.circle.fill", iconColor: .appPrimary,
                           label: "Nombre: \(nombre)") {
                    newNameInput = nombre
                    showEditAlert = true
                }
                Divider().padding(.leading, 56)
                chevronRow(icon: "pencil", iconColor: .onSurfaceVariant,
                           label: "Editar perfil") {
                    newNameInput = nombre
                    showEditAlert = true
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



#Preview {
    PerfilView().environmentObject(AppRouter())
}

