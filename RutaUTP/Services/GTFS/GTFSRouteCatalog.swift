//
//  GTFSRouteCatalog.swift
//  RutaUTP
//
//  Snapshot inmutable con identidad propia para reutilizar geometría.
//

import Foundation

struct GTFSRouteCatalog {
    let routes: [RutaGTFS]
    private let revision: UUID

    /// Una identidad nueva pertenece a este array inmutable completo.
    /// No se acepta una revisión externa que pueda acompañar otros datos.
    init(routes: [RutaGTFS]) {
        self.routes = routes
        revision = UUID()
    }

    func sharesRevision(with other: GTFSRouteCatalog) -> Bool {
        revision == other.revision
    }
}
