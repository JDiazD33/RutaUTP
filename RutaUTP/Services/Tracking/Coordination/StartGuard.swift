//
//  StartGuard.swift
//  RutaUTP
//
//  Controla que un arranque asíncrono siga siendo válido cuando termina.
//
//  Por qué existe: `start()` del coordinador suspende varias veces —pide
//  permiso de ubicación y luego carga el feed GTFS—, y el consentimiento puede
//  revocarse en cualquiera de esas esperas. Sin un testigo, la continuación del
//  arranque reanudaba el trabajo y dejaba la detección y la publicación
//  activas con el consentimiento ya deshabilitado.
//
//  Se mantiene como tipo puro (solo Foundation) a propósito: así la lógica de
//  cancelación se puede probar sin simulador, sin UIKit y sin esperar a que
//  venza un permiso real. El coordinador no aporta nada a esta decisión.
//

import Foundation

/// Emite un testigo por arranque e invalida los anteriores.
///
/// Uso:
///
/// ```swift
/// let token = guard.begin()
/// await algoQueSuspende()
/// guard isCurrent(token) else { return }   // se revocó mientras esperaba
/// ```
///
/// Cada llamada a `begin()` invalida los testigos previos, así que dos
/// arranques solapados nunca pueden completarse los dos: el primero que
/// reanude encontrará su testigo caducado.
struct StartGuard: Equatable {

    /// Testigo del arranque vigente. Empieza en cero y nunca se reutiliza.
    private(set) var generation: Int = 0

    /// Abre un arranque nuevo y devuelve su testigo.
    @discardableResult
    mutating func begin() -> Int {
        generation += 1

        return generation
    }

    /// Invalida el arranque en curso sin abrir otro.
    ///
    /// Es lo que se llama al revocar el consentimiento: cualquier continuación
    /// pendiente comprobará que su testigo ya no vale y se detendrá.
    mutating func invalidate() {
        generation += 1
    }

    /// Indica si el testigo sigue siendo el vigente.
    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }
}
