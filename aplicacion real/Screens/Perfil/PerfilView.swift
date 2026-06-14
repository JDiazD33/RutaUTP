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
    @State private var showEditSheet: Bool = false
    @State private var tempName: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    statsCard
                        .padding(.horizontal, 20)
                        .offset(y: -36)
                    configuracion
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    Spacer(minLength: 100)
                }
            }

            BottomNavBar()
        }
        .sheet(isPresented: $showEditSheet) {
            EditarPerfilSheet(nombre: $tempName) { newName in
                nombre = newName
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Hero
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 220)

            // Decorativo
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 200, height: 200)
                .offset(x: 220, y: -60)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 140, height: 140)
                .offset(x: -40, y: 40)

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
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
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
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
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
                    tempName = nombre
                    showEditSheet = true
                }
                Divider().padding(.leading, 56)
                chevronRow(icon: "pencil", iconColor: .onSurfaceVariant,
                           label: "Editar perfil") {
                    tempName = nombre
                    showEditSheet = true
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

// MARK: - Editar perfil sheet
private struct EditarPerfilSheet: View {
    @Binding var nombre: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Editar perfil")
                    .font(.headlineMd)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nombre completo")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                    TextField("Tu nombre", text: $nombre)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }

                Spacer()

                Button {
                    onSave(nombre)
                    dismiss()
                } label: {
                    Text("Guardar cambios")
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }
}

#Preview {
    PerfilView().environmentObject(AppRouter())
}
