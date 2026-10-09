import SwiftUI
import Combine

/// Política local para decoración: visibilidad, escena, accesibilidad y energía.
/// No modifica ubicación, sesión ni animaciones que comunican progreso real.
struct DecorativeAnimationScope<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var bajoConsumo = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(visible && scenePhase == .active && !reduceMotion && !bajoConsumo)
            .onAppear {
                bajoConsumo = ProcessInfo.processInfo.isLowPowerModeEnabled
                visible = true
            }
            .onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: RunLoop.main)) { _ in
                bajoConsumo = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}
