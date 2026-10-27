//
//  SeniableModifier.swift
//  RutaUTP
//
//  Modificador .seniable(clave:): vuelve tocable un texto cuando el Modo
//  Señas está activado y le añade el distintivo de la manita.
//

import SwiftUI

// MARK: - 3. Modificador

/// Vuelve un texto tocable cuando el Modo Señas está activado.
///
/// Con el modo apagado no añade NADA: ni gesto ni distintivo ni trait de
/// accesibilidad.
struct SeniableModifier: ViewModifier {

    let clave: String
    /// Corrimiento extra del distintivo hacia la derecha (para sitios donde
    /// queda pegado al texto, p. ej. títulos de secciones en Seguridad).
    var distintivoDx: CGFloat = 0
    /// false = sólo el distintivo visual, sin gesto. Útil cuando el elemento
    /// es un Button: un TapGesture DENTRO del label le bloquea la acción al
    /// botón (el miniplayer aparece pero la acción nunca corre); en ese caso
    /// la acción del botón llama ella misma a `presenter.mostrar(clave:)`.
    var conGesto: Bool = true
    @AppStorage(SeniasService.llaveModo) private var modoActivo = false
    private let presenter = SeniasPresenter.shared

    func body(content: Content) -> some View {
        if modoActivo {
            if conGesto {
                conDistintivo(content)
                    // Sólo para contenido informativo. Los botones usan
                    // conGesto: false y coordinan clave y acción explícitamente.
                    .simultaneousGesture(
                        TapGesture().onEnded { presenter.mostrar(clave: clave) }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(L.t("Muestra la traducción en lengua de señas", "Shows the sign language translation"))
                    .accessibilityAction { presenter.mostrar(clave: clave) }
            } else {
                conDistintivo(content)
            }
        } else {
            content
        }
    }

    /// El contenido con la manita anclada a su esquina superior derecha.
    private func conDistintivo(_ content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            DistintivoSenia(dx: 6 + distintivoDx)
        }
    }
}

/// Insignia flotante que marca un elemento como señable.
///
/// Decorativa: no captura toques (deja pasar al gesto del modificador) ni
/// entra en el árbol de accesibilidad.
private struct DistintivoSenia: View {

    /// Desplazamiento horizontal total (6 = posición estándar).
    var dx: CGFloat = 6

    var body: some View {
        Image(systemName: "hand.raised.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.appAccent)
            .padding(3)
            .background(
                Circle()
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            )
            .offset(x: dx, y: -6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Marca un texto como señable. Requiere que el texto use `L.signable`.
    ///
    /// - `distintivoDx`: empuje extra del distintivo hacia la derecha para
    ///   sitios donde queda pegado al texto.
    /// - `conGesto`: false = sólo el distintivo (la acción del botón
    ///   contenedor se encarga de llamar `presenter.mostrar(clave:)`).
    func seniable(_ clave: String, distintivoDx: CGFloat = 0, conGesto: Bool = true) -> some View {
        modifier(SeniableModifier(clave: clave, distintivoDx: distintivoDx, conGesto: conGesto))
    }

    /// Variante para modelos donde la clave puede no existir (nil = no señable).
    @ViewBuilder
    func seniable(_ clave: String?, distintivoDx: CGFloat = 0, conGesto: Bool = true) -> some View {
        if let clave {
            modifier(SeniableModifier(clave: clave, distintivoDx: distintivoDx, conGesto: conGesto))
        } else {
            self
        }
    }
}
