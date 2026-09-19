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
    var onGuardar: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var elegidos: Set<UUID> = []

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
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
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
                    Image(systemName: lugar.categoria.icono)
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
    }

    private var botonListo: some View {
        Button {
            AppHaptics.success()
            onGuardar(elegidos)
            dismiss()
        } label: {
            Text(L.t("Guardar selección", "Save selection"))
                .font(.headlineSm)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
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
        content
            .rotationEffect(.degrees(active ? jiggleAngle : 0))
            .animation(
                active
                ? Animation.easeInOut(duration: 0.12).repeatForever(autoreverses: true)
                : .default,
                value: active
            )
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

// MARK: - Drop delegate para reordenar tiles
struct TileDropDelegate: DropDelegate {
    let destino: LugarGuardado
    @Binding var tiles: [LugarGuardado]
    @Binding var arrastrando: LugarGuardado?
    var onPersistir: () -> Void

    func dropEntered(info: DropInfo) {
        guard let arrastrando,
              arrastrando.id != destino.id,
              !destino.esFijo, !arrastrando.esFijo,
              let desde = tiles.firstIndex(where: { $0.id == arrastrando.id }),
              let hasta = tiles.firstIndex(where: { $0.id == destino.id })
        else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            let movido = tiles.remove(at: desde)
            // Tras remover, el índice destino puede correrse: recalculamos.
            if let nuevoHasta = tiles.firstIndex(where: { $0.id == destino.id }) {
                tiles.insert(movido, at: nuevoHasta)
            } else {
                tiles.insert(movido, at: hasta)
            }
        }
        onPersistir()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        DispatchQueue.main.async { arrastrando = nil }
        return true
    }
}

