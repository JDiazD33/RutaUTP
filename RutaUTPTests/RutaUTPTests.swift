//
//  RutaUTPTests.swift
//  RutaUTPTests
//
//  Pruebas del NÚCLEO PURO del proyecto: las piezas que no dependen de la
//  interfaz ni de la red y que, por tanto, se pueden comprobar sin simulador
//  interactivo. Son las que el Informe 4 (M-38) señalaba como objetivo:
//
//    - GTFSCSV ............ el parser del feed (comillas, comas, columnas)
//    - GTFSNombreParser ... línea/variante y "ramal circular"
//    - PolylineMatching ... proyección sobre el recorrido, decimación, longitudes
//    - TransitItinerary ... búsqueda de línea directa entre dos puntos
//    - CuponNegocio ....... vigencia de un cupón
//    - ParaderosIluminados  selección estable y sin duplicados
//    - SeguridadLugaresModel  regla de orden de los tiles de Seguridad
//
//  `SeguridadLugaresModel` sí lee `UserDefaults` (vía `LugaresStore`), pero se
//  prueba porque la regla que contiene —UTP fijo primero, luego el orden que
//  eligió el usuario— era justo la que no se podía comprobar mientras vivía
//  dentro de la vista. Las pruebas limpian las llaves antes y después.
//

import XCTest
import CoreLocation
import SwiftUI
@testable import RutaUTP

final class GTFSCSVTests: XCTestCase {

    func testParserCuentaFilasYColumnas() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c\n1,2,3\n4,5,6\n")
        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("a"), ["1", "4"])
        XCTAssertEqual(tabla.columna("b"), ["2", "5"])
        XCTAssertEqual(tabla.columna("c"), ["3", "6"])
    }

    func testParserRespetaComasDentroDeComillas() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c\n1,\"x,y\",3\n")
        XCTAssertEqual(tabla.columna("a"), ["1"])
        XCTAssertEqual(tabla.columna("b"), ["x,y"], "la coma entrecomillada no debe partir el campo")
        XCTAssertEqual(tabla.columna("c"), ["3"])
    }

    func testParserTrataLaComillaEmbebidaComoTexto() {
        // Los short names del feed real son del tipo `C-01 "B"`. La comilla no
        // abre un campo entrecomillado porque el valor ya tiene contenido: si
        // el parser la interpretara como delimitador, la variante se perdería.
        let tabla = GTFSCSV.parsear(texto: "route_id,route_short_name\n1,C-01 \"B\"\n")
        XCTAssertEqual(tabla.columna("route_short_name"), ["C-01 \"B\""])
    }

    func testColumnaInexistenteDevuelveVacios() {
        let tabla = GTFSCSV.parsear(texto: "a\n1\n2\n")
        XCTAssertEqual(tabla.columna("no_existe"), ["", ""])
    }

    func testNombreParserSeparaLineaYVariante() {
        let (linea, variante) = GTFSNombreParser.lineaYVariante(shortName: "C-01 \"B\"")
        XCTAssertEqual(linea, "C-01")
        XCTAssertEqual(variante, "B")
    }

    func testNombreParserSinVariante() {
        let (linea, variante) = GTFSNombreParser.lineaYVariante(shortName: "M-07")
        XCTAssertEqual(linea, "M-07")
        XCTAssertEqual(variante, "")
    }

    func testRecorridoMarcaRamalCircular() {
        // Origen == destino: el feed lo publica como un recorrido que vuelve.
        let texto = GTFSNombreParser.recorrido(longName: "C-01 \"B\" : Av. Grau → Av. Grau",
                                               shortName: "C-01 \"B\"")
        XCTAssertEqual(texto, "Av. Grau (ramal circular)")
    }

    func testRecorridoNormalNoSeAltera() {
        let texto = GTFSNombreParser.recorrido(longName: "C-01 \"B\" : Av. Grau → Av. Libertad",
                                               shortName: "C-01 \"B\"")
        XCTAssertEqual(texto, "Av. Grau → Av. Libertad")
    }
}

final class PolylineMatchingTests: XCTestCase {

    /// Línea recta de ~1.1 km sobre el paralelo -8.10.
    private let inicio = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)
    private let fin    = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.03)
    private var recta: [CLLocationCoordinate2D] { [inicio, fin] }

    func testMatchProyectaSobreLaLinea() {
        // Punto a ~55 m al norte del punto medio.
        let punto = CLLocationCoordinate2D(latitude: -8.0995, longitude: -79.035)
        guard let match = PolylineMatching.match(point: punto, on: recta, thresholdMeters: 100) else {
            return XCTFail("debería proyectar sobre la recta")
        }
        XCTAssertTrue(match.isOnRoute)
        XCTAssertEqual(match.progressFraction, 0.5, accuracy: 0.05)
        XCTAssertLessThan(match.distanceToRoute, 100)
    }

    func testMatchDetectaFueraDeRuta() {
        let punto = CLLocationCoordinate2D(latitude: -8.105, longitude: -79.035)
        guard let match = PolylineMatching.match(point: punto, on: recta, thresholdMeters: 20) else {
            return XCTFail("debería proyectar igualmente")
        }
        XCTAssertFalse(match.isOnRoute, "a ~550 m de la recta no puede considerarse en ruta")
        XCTAssertGreaterThan(match.distanceToRoute, 400)
    }

    func testMatchNecesitaAlMenosDosPuntos() {
        XCTAssertNil(PolylineMatching.match(point: inicio, on: [inicio]))
    }

    func testDecimateConservaExtremosYCuenta() {
        let puntos = (0..<100).map {
            CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04 + Double($0) * 0.0001)
        }
        let reducidos = PolylineMatching.decimate(puntos, maxPoints: 10)
        XCTAssertEqual(reducidos.count, 10)
        XCTAssertEqual(reducidos.first!.longitude, puntos.first!.longitude, accuracy: 1e-9)
        XCTAssertEqual(reducidos.last!.longitude, puntos.last!.longitude, accuracy: 1e-9)
    }

    func testDecimateNoAmpliaListasCortas() {
        let puntos = [inicio, fin]
        XCTAssertEqual(PolylineMatching.decimate(puntos, maxPoints: 10).count, 2)
    }

    func testLongitudTotalDeLaRecta() {
        // 0.01° de longitud a latitud -8.10 ≈ 1.10 km.
        let metros = PolylineMatching.totalLengthMeters(recta)
        XCTAssertEqual(metros, 1100, accuracy: 80)
    }

    func testRecalculoTrasTresMuestrasFueraDeRuta() {
        XCTAssertTrue(PolylineMatching.shouldRecalculate(lastMatch: nil, consecutiveOffRouteCount: 0),
                      "sin match previo hay que recalcular")
        let match = PolylineMatching.match(point: inicio, on: recta, thresholdMeters: 20)
        XCTAssertFalse(PolylineMatching.shouldRecalculate(lastMatch: match, consecutiveOffRouteCount: 2,
                                                          thresholdCount: 3),
                       "dos muestras fuera no bastan: el ruido de GPS no debe provocar recálculo")
        XCTAssertTrue(PolylineMatching.shouldRecalculate(lastMatch: match, consecutiveOffRouteCount: 3,
                                                         thresholdCount: 3))
    }
}

final class TransitItineraryTests: XCTestCase {

    /// Ruta sintética recta de 11 puntos (~1.1 km) con tres paraderos.
    private func rutaSintetica() -> RutaGTFS {
        let shape = (0...10).map {
            CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04 + Double($0) * 0.001)
        }
        let paraderos = [
            ParaderoGTFS(id: "p0", nombre: "Inicio", lat: shape[0].latitude, lon: shape[0].longitude),
            ParaderoGTFS(id: "p1", nombre: "Medio", lat: shape[5].latitude, lon: shape[5].longitude),
            ParaderoGTFS(id: "p2", nombre: "Fin", lat: shape[10].latitude, lon: shape[10].longitude)
        ]
        return RutaGTFS(id: "R1", linea: "C-01", variante: "B",
                        recorrido: "Inicio → Fin", empresa: "Agencia de prueba",
                        colorHex: "00CC00", color: .green,
                        shape: shape, paraderos: paraderos,
                        duracionMin: 10, headwayMin: 5, precio: 2.5,
                        distanciaKm: 1.1, distanciaUTPMetros: 100)
    }

    func testEncuentraLineaDirectaEntreExtremos() {
        let ruta = rutaSintetica()
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: ruta.shape.first!,
                                                     destination: ruta.shape.last!,
                                                     radius: 300)
        guard let plan = candidatos.first else {
            return XCTFail("debería encontrar la línea directa")
        }
        XCTAssertEqual(plan.board.id, "p0")
        XCTAssertEqual(plan.alight.id, "p2")
        XCTAssertGreaterThan(plan.busMeters, 50, "un tramo en bus de menos de 50 m no es un viaje")
        XCTAssertEqual(plan.coordinates.count,
                       plan.walkToBoard.count + plan.bus.count + plan.walkToDestination.count)
    }

    func testRespetaElSentidoDelRecorrido() {
        // Destino en el paradero inicial y origen en el final: no hay viaje
        // posible, porque el feed describe un solo sentido.
        let ruta = rutaSintetica()
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: ruta.shape.last!,
                                                     destination: ruta.shape.first!,
                                                     radius: 300)
        XCTAssertTrue(candidatos.isEmpty, "no debe invertirse el sentido del recorrido")
    }

    func testSinParaderosCercaNoHayCandidatos() {
        // Origen y destino LEJOS de todos los paraderos: el radio es la
        // caminata máxima admitida hasta un paradero, así que sin paraderos
        // dentro del radio no hay subida posible.
        let ruta = rutaSintetica()
        let lejos = CLLocationCoordinate2D(latitude: -8.20, longitude: -79.20)
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: lejos,
                                                     destination: lejos,
                                                     radius: 300)
        XCTAssertTrue(candidatos.isEmpty)
    }

    func testSubirSobreElParaderoValeConRadioMinimo() {
        // Documenta la semántica real del radio: mide la caminata hasta el
        // paradero, no el trayecto. Si el usuario está parado SOBRE el
        // paradero de subida y su destino cae sobre otro paradero de la misma
        // línea, el viaje es válido aunque el radio sea diminuto.
        let ruta = rutaSintetica()
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: ruta.shape.first!,
                                                     destination: ruta.shape.last!,
                                                     radius: 1)
        XCTAssertEqual(candidatos.first?.board.id, "p0")
        XCTAssertEqual(candidatos.first?.alight.id, "p2")
    }

    func testRutaSinGeometriaSeIgnora() {
        let ruta = RutaGTFS(id: "R0", linea: "X", variante: "", recorrido: "—",
                            empresa: "—", colorHex: "000000", color: .black,
                            shape: [], paraderos: [],
                            duracionMin: 0, headwayMin: 0, precio: 0,
                            distanciaKm: 0, distanciaUTPMetros: .infinity)
        XCTAssertTrue(TransitItinerary.candidates(in: [ruta], origin: inicioCualquiera,
                                                  destination: inicioCualquiera, radius: 500).isEmpty)
    }

    private var inicioCualquiera: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)
    }
}

final class CuponNegocioTests: XCTestCase {

    private func cupon(vence: String?) -> CuponNegocio {
        CuponNegocio(codigo: "RUTA-TEST",
                     detalle: TextoBilingue(es: "2x1", en: "2x1"),
                     condiciones: TextoBilingue(es: "Mostrar en el local", en: "Show in store"),
                     vence: vence)
    }

    func testSinVencimientoEstaVigente() {
        XCTAssertTrue(cupon(vence: nil).vigente)
    }

    func testFechaPasadaNoEstaVigente() {
        XCTAssertFalse(cupon(vence: "2020-01-01").vigente)
    }

    func testFechaFuturaEstaVigente() {
        XCTAssertTrue(cupon(vence: "2099-12-31").vigente)
    }

    func testFechaInvalidaNoSeInterpretaComoVencida() {
        // Un formato inesperado no debe retirar el cupón: `fechaVencimiento`
        // devuelve nil y sin fecha límite el cupón sigue vigente.
        let c = cupon(vence: "no-es-una-fecha")
        XCTAssertNil(c.fechaVencimiento)
        XCTAssertTrue(c.vigente)
    }
}

final class ParaderosIluminadosTests: XCTestCase {

    private func ruta(_ id: String, stops: [ParaderoGTFS]) -> RutaGTFS {
        RutaGTFS(id: id, linea: "C-01", variante: "", recorrido: "—", empresa: "—",
                 colorHex: "00CC00", color: .green,
                 shape: stops.map(\.coordinate), paraderos: stops,
                 duracionMin: 10, headwayMin: 5, precio: 2.5,
                 distanciaKm: 1, distanciaUTPMetros: 100)
    }

    func testSeleccionNoDuplicaParaderos() {
        let stops = [
            ParaderoGTFS(id: "s1", nombre: "A", lat: -8.10, lon: -79.04),
            ParaderoGTFS(id: "s2", nombre: "B", lat: -8.11, lon: -79.05),
            ParaderoGTFS(id: "s3", nombre: "C", lat: -8.12, lon: -79.06)
        ]
        // Dos rutas que comparten los MISMOS paraderos: la deduplicación por
        // coordenada debe dejar tres, no seis.
        let seleccion = ParaderosIluminados.seleccionar([ruta("R1", stops: stops),
                                                         ruta("R2", stops: stops)],
                                                        cantidad: 24)
        XCTAssertEqual(seleccion.count, 3)
        let claves = Set(seleccion.map { "\(Int(($0.lat * 1e6).rounded())):\(Int(($0.lon * 1e6).rounded()))" })
        XCTAssertEqual(claves.count, seleccion.count, "no puede haber dos paraderos en el mismo punto")
    }

    func testSeleccionRespetaElTope() {
        let stops = (0..<20).map {
            ParaderoGTFS(id: "s\($0)", nombre: "P\($0)",
                         lat: -8.10 - Double($0) * 0.001, lon: -79.04)
        }
        XCTAssertLessThanOrEqual(ParaderosIluminados.seleccionar([ruta("R1", stops: stops)],
                                                                 cantidad: 8).count, 8)
    }

    func testFeedVacioDevuelveVacio() {
        XCTAssertTrue(ParaderosIluminados.seleccionar([], cantidad: 24).isEmpty)
    }

    func testCantidadCeroDevuelveVacio() {
        let stops = [ParaderoGTFS(id: "s1", nombre: "A", lat: -8.10, lon: -79.04)]
        XCTAssertTrue(ParaderosIluminados.seleccionar([ruta("R1", stops: stops)], cantidad: 0).isEmpty)
    }
}

/// Regla de orden de los tiles de Seguridad.
///
/// Es la razón de haber extraído `SeguridadLugaresModel`: mientras la regla
/// vivía dentro de la vista no había forma de comprobarla sin levantarla.
/// Estas pruebas tocan `UserDefaults` porque `LugaresStore` es el almacén real
/// del proyecto; se limpian las tres llaves antes y después de cada una.
@MainActor
final class SeguridadLugaresModelTests: XCTestCase {

    private let llaves = [LugaresStore.key, "seguridad.tiles.v1", "seguridad.tiles.orden.v1"]

    override func setUp() {
        super.setUp()
        limpiar()
    }

    override func tearDown() {
        limpiar()
        super.tearDown()
    }

    /// Borra las llaves **y** la caché en memoria de `LugaresStore`. Sin lo
    /// segundo, cada prueba vería la lista que dejó la anterior: el almacén
    /// decodifica una sola vez por proceso.
    private func limpiar() {
        LugaresStore.invalidarCache()
        llaves.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func lugar(_ nombre: String, fijo: Bool = false) -> LugarGuardado {
        LugarGuardado(nombre: nombre, direccion: "—",
                      categoria: fijo ? .universidad : .otro, esFijo: fijo)
    }

    func testElFijoSiempreVaPrimero() {
        // El fijo se guarda al FINAL a propósito: el modelo debe subirlo.
        let utp = lugar("UTP", fijo: true)
        LugaresStore.guardar([lugar("Plaza"), utp])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()

        XCTAssertEqual(modelo.tilesActuales.first?.nombre, "UTP")
    }

    func testSinSeleccionPreviaSeEligenDosNoFijos() {
        LugaresStore.guardar([lugar("UTP", fijo: true),
                              lugar("A"), lugar("B"), lugar("C")])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()

        XCTAssertEqual(modelo.tilesActuales.map(\.nombre), ["UTP", "A", "B"])
    }

    func testLaSeleccionExplicitaSeRespeta() {
        let b = lugar("B"), c = lugar("C")
        LugaresStore.guardar([lugar("UTP", fijo: true), lugar("A"), b, c])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()
        modelo.reconstruirTiles(seleccion: [b.id, c.id])

        XCTAssertEqual(modelo.tilesActuales.map(\.nombre), ["UTP", "B", "C"])
    }

    func testLaSeleccionSobreviveAUnaRecarga() {
        let b = lugar("B"), c = lugar("C")
        LugaresStore.guardar([lugar("UTP", fijo: true), lugar("A"), b, c])

        let primero = SeguridadLugaresModel()
        primero.cargar()
        primero.reconstruirTiles(seleccion: [b.id, c.id])

        // Un modelo nuevo (equivale a volver a entrar a la pantalla) debe
        // reconstruir la misma selección desde lo persistido.
        let segundo = SeguridadLugaresModel()
        segundo.cargar()

        XCTAssertEqual(segundo.tilesActuales.map(\.nombre), ["UTP", "B", "C"])
    }

    func testEliminarSacaElLugarDeLosTilesYDeGuardados() {
        let a = lugar("A")
        LugaresStore.guardar([lugar("UTP", fijo: true), a])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()
        XCTAssertTrue(modelo.tilesActuales.contains { $0.id == a.id })

        modelo.eliminar(a)

        XCTAssertFalse(modelo.tilesActuales.contains { $0.id == a.id })
        XCTAssertFalse(modelo.lugares.contains { $0.id == a.id })
        XCTAssertFalse(LugaresStore.cargar().contains { $0.id == a.id })
    }
}

final class RejillaEspacialTests: XCTestCase {

    /// Nube determinista de puntos alrededor de Trujillo.
    private func nube() -> [CLLocationCoordinate2D] {
        (0..<400).map { i in
            CLLocationCoordinate2D(latitude: -8.10 + Double(i % 20) * 0.001,
                                   longitude: -79.04 + Double(i / 20) * 0.001)
        }
    }

    private func clave(_ c: CLLocationCoordinate2D) -> String { "\(c.latitude),\(c.longitude)" }

    func testDevuelveLoMismoQueElBarridoLineal() {
        let puntos = nube()
        let radio = 150.0
        let rejilla = RejillaEspacial(puntos, radioMetros: radio, coordenada: { $0 })

        for consulta in puntos.prefix(40) {
            let porRejilla = Set(rejilla.cerca(de: consulta, radioMetros: radio).map(clave))
            let porFuerzaBruta = Set(puntos.filter {
                PolylineMatching.distanceMeters($0, consulta) <= radio
            }.map(clave))
            XCTAssertEqual(porRejilla, porFuerzaBruta,
                           "la rejilla y el barrido difieren en \(consulta)")
        }
    }

    func testSinVecinosDevuelveVacio() {
        let rejilla = RejillaEspacial([CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)],
                                      radioMetros: 100, coordenada: { $0 })
        let lejos = CLLocationCoordinate2D(latitude: -8.20, longitude: -79.20)
        XCTAssertTrue(rejilla.cerca(de: lejos, radioMetros: 100).isEmpty)
    }
}

/// La rejilla cambia CÓMO se busca, no QUÉ se encuentra.
///
/// Es la verificación que el informe pedía para este cambio: se compara el
/// resultado nuevo contra la lógica original escrita a mano, sobre el feed
/// real completo.
@MainActor
final class LineasPorParaderoTests: XCTestCase {

    func testLaRejillaDaElMismoResultadoQueElBarridoLineal() async {
        let feed = await GTFSRepository.shared.rutas()
        XCTAssertFalse(feed.isEmpty, "el feed embebido debe cargar")

        let visibles = ParaderosIluminados.seleccionar(feed)
        XCTAssertFalse(visibles.isEmpty)
        let porRejilla = ParaderosIluminadosView.lineasQueSirven(visibles, en: feed)

        for paradero in visibles {
            // Referencia: el criterio original, sin rejilla.
            let esperado = feed.filter { ruta in
                ruta.paraderos.contains {
                    $0.id == paradero.id
                        || PolylineMatching.distanceMeters($0.coordinate, paradero.coordinate) < 20
                }
            }.map(\.id)

            XCTAssertEqual(porRejilla[paradero.id]?.map(\.id), esperado,
                           "difiere en el paradero \(paradero.nombre)")
        }
    }
}
