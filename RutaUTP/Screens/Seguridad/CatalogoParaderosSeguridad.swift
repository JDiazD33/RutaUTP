//
//  CatalogoParaderosSeguridad.swift
//  RutaUTP
//
//  Prepara los paraderos de la sección Seguridad fuera del actor principal y
//  reutiliza el resultado mientras sigan vigentes el catálogo y la referencia.
//

import CoreLocation

/// Prepara la sección de Seguridad fuera del actor principal y reutiliza el
/// resultado mientras sigan vigentes el catálogo y la referencia de cercanía.
/// Al cambiar de modo, sede o catálogo nunca devuelve los paraderos anteriores.
actor CatalogoParaderosSeguridad {
    static let shared = CatalogoParaderosSeguridad()

    struct Resultado {
        let muestra: [ParaderoGTFS]
        let paraderos: [ParaderoGTFS]
    }

    private var catalogoAnterior: GTFSRouteCatalog?
    private var referenciaAnterior: CLLocationCoordinate2D?
    private var resultadoAnterior: Resultado?

    func preparar(_ catalogo: GTFSRouteCatalog,
                  cercaDe referencia: CLLocationCoordinate2D) -> Resultado {
        if let catalogoAnterior, catalogoAnterior.sharesRevision(with: catalogo),
           let referenciaAnterior,
           referenciaAnterior.latitude == referencia.latitude,
           referenciaAnterior.longitude == referencia.longitude,
           let resultadoAnterior { return resultadoAnterior }

        let resultado = Resultado(
            muestra: ParaderosIluminados.seleccionar(catalogo.routes, cercaDe: referencia),
            paraderos: catalogo.routes.flatMap(\.paraderos))
        catalogoAnterior = catalogo
        referenciaAnterior = referencia
        resultadoAnterior = resultado
        return resultado
    }
}
