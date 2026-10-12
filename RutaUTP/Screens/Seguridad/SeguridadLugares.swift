//
//  SeguridadLugares.swift
//  RutaUTP
//
//  Tiles de lugares guardados: selector, efecto jiggle de edición y
//  delegado de arrastre para reordenar.
//  
//  Estaba dentro de `SeguridadView.swift`.

import SwiftUI
import UIKit
import UniformTypeIdentifiers
// MARK: - Elegir Lugares sheet (tiles de Seguridad)
struct ElegirLugaresSheet: View {
    let lugares: [LugarGuardado]          // sin incluir UTP (fijo, siempre está)
    let seleccion: Set<UUID>
    var irAGuardado: () -> Void
    var onGuardar: (Set<UUID>) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var elegidos: Set<UUID> = []
    @State private var errorGuardado = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("Elige los lugares que verás aquí", "Choose which places appear here"))
                    .font(.headlineMd)
                Text(L.t("Tus lugares guardados de la pestaña Guardado. UTP siempre aparece.", "Your saved places. UTP always appears."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)

                if lugares.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.onSurfaceVariant)
                        Text(L.t("Aún no tienes lugares guardados", "No saved places yet"))
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurface)
                        Button {
                            irAGuardado()
                        } label: {
                            Label(L.t("Ir a Guardado", "Go to Saved"), systemImage: "plus.circle.fill")
                                .font(.headlineSm)
                                .foregroundStyle(.onPrimaryFill)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primaryFill))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(lugares) { lugar in
                                filaLugar(lugar)
                            }
                        }
                    }
                    botonListo
                }
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
            .onAppear { elegidos = seleccion }
            .alert(L.t("No se pudo guardar la selección", "Couldn't save selection"), isPresented: $errorGuardado) {
                Button(L.t("Aceptar", "OK"), role: .cancel) {}
            } message: {
                Text(L.t("No se pudieron leer tus lugares o accesos. Se conservaron los datos originales.",
                         "Your places or shortcuts could not be read. The original data was preserved."))
            }
        }
    }

    private func filaLugar(_ lugar: LugarGuardado) -> some View {
        Button {
            AppHaptics.selection()
            if elegidos.contains(lugar.id) {
                elegidos.remove(lugar.id)
            } else {
                elegidos.insert(lugar.id)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.primaryContainer.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: lugar.icono)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(lugar.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(lugar.direccion)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: elegidos.contains(lugar.id)
                      ? "checkmark.circle.fill"
                      : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(elegidos.contains(lugar.id) ? Color.appPrimary : Color.outlineVariant)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(elegidos.contains(lugar.id)
                          ? Color.primaryContainer.opacity(0.25)
                          : Color.surfaceContainerLowest)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lugar.nombre)
        .accessibilityValue(lugar.direccion)
        .accessibilityAddTraits(elegidos.contains(lugar.id) ? .isSelected : [])
        .accessibilityHint(L.t("Añade o quita este lugar de los accesos de Seguridad", "Adds or removes this place from Safety shortcuts"))
    }

    private var botonListo: some View {
        Button {
            if onGuardar(elegidos) {
                AppHaptics.success()
                dismiss()
            } else {
                errorGuardado = true
            }
        } label: {
            Text(L.t("Guardar selección", "Save selection"))
                .font(.headlineSm)
                .foregroundStyle(.onPrimaryFill)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primaryFill))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Efecto jiggle (estilo pantalla de inicio del iPhone)
/// Rotación oscilante con desfase por tile para que se muevan "en ola".
struct JiggleEffect: ViewModifier {
    let active: Bool
    /// Posición del tile en la cuadrícula. Solo se usa para alternar el signo.
    var indice: Int = 0

    func body(content: Content) -> some View {
        DecorativeAnimationScope { permitirAnimacion in
            let animar = active && permitirAnimacion
            content
                .rotationEffect(.degrees(animar ? jiggleAngle : 0))
                .animation(
                    animar
                    ? Animation.easeInOut(duration: 0.12).repeatForever(autoreverses: true)
                    : nil,
                    value: animar
                )
        }
    }

    /// Ángulo del temblor.
    ///
    /// El efecto "ola" no sale de un retardo —que habría que escalonar tile a
    /// tile— sino de ALTERNAR el signo según la posición: los tiles pares
    /// giran a un lado y los impares al otro. Aquí había un
    /// `.delay(fase * 0.0)` que multiplicaba por cero y no hacía nada.
    ///
    /// La paridad se mide sobre el ÍNDICE, no sobre una fase escalada. Cuando
    /// esto era `fase.truncatingRemainder(dividingBy: 2)` con una fase de
    /// `índice × 1,7`, el resto solo salía 0 en el primer tile y **los demás
    /// giraban todos al mismo lado**: la ola no existía.
    private var jiggleAngle: Double {
        1.6 * (indice.isMultiple(of: 2) ? 1 : -1)
    }
}

/// Marcos de los accesos en la cuadrícula para resolver el destino del arrastre local.
struct MarcosTilesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, nuevo in nuevo })
    }
}
