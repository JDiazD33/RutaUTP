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
import MapKit
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

    private func line(_ id: String, _ points: [CLLocationCoordinate2D], headway: Int = 6) -> RutaGTFS {
        RutaGTFS(id: id, linea: id, variante: "", recorrido: id, empresa: "Test",
                 colorHex: "00CC00", color: .green, shape: points,
                 paraderos: points.enumerated().map {
                     ParaderoGTFS(id: "\(id)-\($0.offset)", nombre: "\(id)-\($0.offset)",
                                  lat: $0.element.latitude, lon: $0.element.longitude)
                 }, duracionMin: 10, headwayMin: headway, precio: 2,
                 distanciaKm: PolylineMatching.totalLengthMeters(points) / 1000, distanciaUTPMetros: 0)
    }
    private var transferNetwork: (RutaGTFS, RutaGTFS) {
        let start = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)
        let exit = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.03)
        let enter = CLLocationCoordinate2D(latitude: -8.099, longitude: -79.03)
        let end = CLLocationCoordinate2D(latitude: -8.09, longitude: -79.03)
        return (line("A", [start, exit]), line("B", [enter, end]))
    }

    func testEncuentraDosMicrosSinLineaDirecta() throws {
        let (a, b) = transferNetwork
        let plans = TransitItinerary.candidates(in: [a, b], origin: a.shape[0], destination: b.shape[1], radius: 50)
        let plan = try XCTUnwrap(plans.first)
        let transfer = try XCTUnwrap(plan.transfer)
        XCTAssertEqual(plan.route.id, "A")
        XCTAssertEqual(transfer.route.id, "B")
        XCTAssertEqual(plan.firstAlight.id, "A-1")
        XCTAssertEqual(transfer.board.id, "B-0")
        XCTAssertEqual(plan.alight.id, "B-1")
        XCTAssertGreaterThan(plan.transferWalkMeters, 100)
        XCTAssertLessThan(plan.transferWalkMeters, 120)
        XCTAssertEqual(plan.busMeters, plan.firstBusMeters + transfer.busMeters, accuracy: 0.001)
        XCTAssertEqual(plan.coordinates.count, plan.walkToBoard.count + plan.bus.count + transfer.walk.count
                       + transfer.bus.count + plan.walkToDestination.count)
        XCTAssertEqual(plan.remainingSeconds(after: 0), plan.totalSeconds, accuracy: 0.001)
        XCTAssertEqual(plan.remainingSeconds(after: 100_000), 0)
        XCTAssertEqual(plan.transferWaitSeconds, 300)
    }

    func testTransbordoNoInvierteSegundoMicro() {
        let (a, b) = transferNetwork
        let reversed = line("B", b.shape.reversed())
        XCTAssertTrue(TransitItinerary.candidates(in: [a, reversed], origin: a.shape[0],
                                                 destination: b.shape[1], radius: 50).isEmpty)
    }

    func testTransbordoNoInviertePrimerMicro() {
        let (a, b) = transferNetwork
        let reversed = line("A", a.shape.reversed())
        XCTAssertTrue(TransitItinerary.candidates(in: [reversed, b], origin: a.shape[0],
                                                 destination: b.shape[1], radius: 50).isEmpty)
    }

    func testRechazaConexionDemasiadoLejana() {
        let (a, b) = transferNetwork
        let far = line("B", [CLLocationCoordinate2D(latitude: -8.095, longitude: -79.03), b.shape[1]])
        XCTAssertTrue(TransitItinerary.candidates(in: [a, far], origin: a.shape[0],
                                                 destination: b.shape[1], radius: 50).isEmpty)
    }

    func testNoProponeCambiarAlMismoRecorrido() {
        let a = rutaSintetica()
        let plans = TransitItinerary.candidates(in: [a], origin: a.shape[0], destination: a.shape.last!, radius: 50)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { $0.transfer == nil })
    }

    func testPrefiereDirectoCuandoLosTiemposSonParecidos() throws {
        let (a, b) = transferNetwork
        let direct = line("Direct", [a.shape[0], a.shape[1], b.shape[0], b.shape[1]])
        let plans = TransitItinerary.candidates(in: [a, b, direct], origin: a.shape[0], destination: b.shape[1], radius: 50)
        XCTAssertNil(try XCTUnwrap(plans.first).transfer)
        XCTAssertTrue(plans.contains { $0.route.id == "A" && $0.transfer?.route.id == "B" })
    }

    func testPrefiereTransbordoAnteUnDesvioDirectoLargo() throws {
        let (a, b) = transferNetwork
        let direct = line("Detour", [a.shape[0], CLLocationCoordinate2D(latitude: -8.30, longitude: -79.20), b.shape[1]])
        let plans = TransitItinerary.candidates(in: [a, b, direct], origin: a.shape[0], destination: b.shape[1], radius: 50)
        XCTAssertNotNil(try XCTUnwrap(plans.first).transfer)
    }

    func testRechazaCaminataRealDeConexionSuperiorAlLimite() throws {
        let (a, b) = transferNetwork
        var plan = try XCTUnwrap(TransitItinerary.candidates(in: [a, b], origin: a.shape[0],
                                                           destination: b.shape[1], radius: 50).first)
        plan.transfer?.walk = [a.shape[1], CLLocationCoordinate2D(latitude: -8.11, longitude: -79.03), b.shape[0]]
        XCTAssertFalse(plan.walkingWithinTransferLimit)
    }

    func testPlanificaConElFeedIncluido() async throws {
        let routes = await GTFSRepository.shared.rutas()
        let route = try XCTUnwrap(routes.first { $0.paraderos.count > 3 })
        let start = Date()
        let plans = await TransitPlanner.shared.candidates(in: routes, origin: route.paraderos.first!.coordinate,
                                                           destination: route.paraderos.last!.coordinate, radius: 800)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { $0.walkingWithinTransferLimit && $0.busMeters > 50 })
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "La búsqueda local no debe tardar decenas de segundos")
        print("[TransitPlanner] \(routes.count) rutas: \(plans.count) candidatos en \(Date().timeIntervalSince(start)) s")
    }

    @MainActor
    func testRendimientoRadio1600() async throws {
        let routes = await GTFSRepository.shared.rutas()
        let route = try XCTUnwrap(routes.first { $0.paraderos.count > 3 })
        let planner = TransitPlanner()
        for iteration in 0..<2 {
            let start = Date()
            let plans = await planner.candidates(in: routes,
                origin: route.paraderos.first!.coordinate, destination: route.paraderos.last!.coordinate, radius: 1600)
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 8, "La consulta local de 1600 m no debe volver al barrido lento")
            XCTAssertFalse(plans.isEmpty)
            let signatures = plans.prefix(4).map {
                "\($0.route.id):\($0.board.id):\($0.firstAlight.id):\($0.transfer?.route.id ?? "-"):\($0.transfer?.board.id ?? "-"):\($0.alight.id) ETA=\($0.totalSeconds)"
            }
            XCTContext.runActivity(named: "BENCH1600 pass=\(iteration) seconds=\(elapsed) count=\(plans.count)") { activity in
                let attachment = XCTAttachment(string: signatures.joined(separator: "\n"))
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }

    func testCacheInvalidaGeometriaModificadaConMismoID() async throws {
        let planner = TransitPlanner()
        let route = rutaSintetica()
        let original = await planner.candidates(in: [route], origin: route.shape.first!,
                                                destination: route.shape.last!, radius: 300)
        XCTAssertFalse(original.isEmpty)
        let changed = RutaGTFS(id: route.id, linea: route.linea, variante: route.variante,
            recorrido: route.recorrido, empresa: route.empresa, colorHex: route.colorHex, color: route.color,
            shape: route.shape.map { CLLocationCoordinate2D(latitude: $0.latitude + 0.1, longitude: $0.longitude) },
            paraderos: route.paraderos, duracionMin: route.duracionMin, headwayMin: route.headwayMin,
            precio: route.precio, distanciaKm: route.distanciaKm, distanciaUTPMetros: route.distanciaUTPMetros)
        let invalid = await planner.candidates(in: [changed], origin: route.shape.first!,
                                               destination: route.shape.last!, radius: 300)
        XCTAssertTrue(invalid.isEmpty, "No reutilizar paraderos proyectados sobre un shape anterior")
    }

    func testOrdenOptimizadoCoincideConEnumeracionDirecta() throws {
        let route = line("Oracle", rutaSintetica().shape)
        let origin = CLLocationCoordinate2D(latitude: -8.1003, longitude: -79.0401)
        let destination = CLLocationCoordinate2D(latitude: -8.0997, longitude: -79.0299)
        let radius = 500.0
        var reference: [TransitItinerary] = []
        for board in route.paraderos.indices {
            for alight in route.paraderos.indices where alight > board {
                let plan = TransitItinerary(route: route, board: route.paraderos[board], alight: route.paraderos[alight],
                    walkToBoard: [origin, route.shape[board]], bus: Array(route.shape[board...alight]),
                    walkToDestination: [route.shape[alight], destination])
                if plan.walkToBoardMeters <= radius && plan.walkToDestinationMeters <= radius && plan.busMeters > 50 {
                    reference.append(plan)
                }
            }
        }
        reference.sort { $0.totalSeconds < $1.totalSeconds }
        let optimized = TransitItinerary.candidates(in: [route], origin: origin, destination: destination, radius: radius)
        XCTAssertEqual(optimized.count, min(32, reference.count))
        for (actual, expected) in zip(optimized, reference) {
            XCTAssertEqual(actual.board.id, expected.board.id)
            XCTAssertEqual(actual.alight.id, expected.alight.id)
            XCTAssertEqual(actual.totalSeconds, expected.totalSeconds, accuracy: 0.001)
        }
    }

    func testCaminatasSeConsultanEnParaleloYRespaldoSeIdentifica() async throws {
        let (a, b) = transferNetwork
        let plan = try XCTUnwrap(TransitItinerary.candidates(in: [a, b], origin: a.shape[0],
                                                           destination: b.shape[1], radius: 50).first)
        let probe = DirectionsProbe()
        let service = RouteCalculationService(loader: { request in try await probe.load(request, fail: false) })
        let resolved = await plan.withWalkingDirections(using: service)
        let concurrency = await probe.maximumConcurrent
        XCTAssertEqual(concurrency, 3, "Las tres caminatas del mismo viaje no deben esperarse en serie")
        XCTAssertFalse(resolved.walkingApproximate)
        let failing = RouteCalculationService(loader: { _ in throw RouteCalculationError.timedOut })
        let approximate = await plan.withWalkingDirections(using: failing)
        XCTAssertTrue(approximate.walkingApproximate)
        XCTAssertEqual(approximate.route.id, plan.route.id)
        XCTAssertEqual(approximate.transfer?.route.id, plan.transfer?.route.id)
    }

    func testCacheDeCaminataRespetaExtremosModoYCancelacion() async throws {
        let probe = DirectionsProbe()
        let service = RouteCalculationService(loader: { request in try await probe.load(request, fail: false) })
        let points = rutaSintetica().shape
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        let firstCount = await probe.calls
        XCTAssertEqual(firstCount, 1)
        _ = try await service.calculateRoute(from: points[0], to: points[6], transportType: .walking)
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .automobile)
        let secondCount = await probe.calls
        XCTAssertEqual(secondCount, 3)
        let pending = Task { try await service.calculateRoute(from: points[1], to: points[8], transportType: .walking) }
        try await Task.sleep(for: .milliseconds(10))
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("La cancelación debe llegar a la petición de caminata")
        } catch is CancellationError {} catch { XCTFail("Cancelación inesperada: \(error)") }
        let cancelled = await probe.cancelled
        XCTAssertEqual(cancelled, 1)
    }

    func testTransbordoOptimizadoCoincideConBusquedaExhaustiva() throws {
        let a = line("A", [-79.06, -79.05, -79.04, -79.03].map { CLLocationCoordinate2D(latitude: -8.1, longitude: $0) })
        let b = line("B", [-8.1, -8.098, -8.096, -8.092, -8.085].map { CLLocationCoordinate2D(latitude: $0, longitude: -79.029) })
        let origin = a.shape.first!, destination = b.shape.last!, radius = 1400.0
        var reference: [TransitItinerary] = []
        for board in a.paraderos.indices {
            for exit in a.paraderos.indices where exit > board {
                for enter in b.paraderos.indices {
                    for alight in b.paraderos.indices where alight > enter {
                        var plan = TransitItinerary(route: a, board: a.paraderos[board], alight: a.paraderos[exit],
                            walkToBoard: [origin, a.shape[board]], bus: Array(a.shape[board...exit]),
                            walkToDestination: [b.shape[alight], destination])
                        let bus = Array(b.shape[enter...alight])
                        plan.transfer = TransitTransfer(route: b, board: b.paraderos[enter], alight: b.paraderos[alight],
                            walk: [a.shape[exit], b.shape[enter]], bus: bus, busDibujo: bus,
                            busMeters: PolylineMatching.totalLengthMeters(bus),
                            busSpeed: min(14, max(3, b.distanciaKm * 1000 / Double(b.duracionMin * 60))))
                        if plan.walkToBoardMeters <= radius && plan.walkToDestinationMeters <= radius && plan.walkingWithinTransferLimit {
                            reference.append(plan)
                        }
                    }
                }
            }
        }
        let expected = try XCTUnwrap(reference.min { $0.totalSeconds < $1.totalSeconds })
        let actual = try XCTUnwrap(TransitItinerary.candidates(in: [a, b], origin: origin,
                                                              destination: destination, radius: radius).first)
        XCTAssertEqual(actual.board.id, expected.board.id)
        XCTAssertEqual(actual.firstAlight.id, expected.firstAlight.id)
        XCTAssertEqual(actual.transfer?.board.id, expected.transfer?.board.id)
        XCTAssertEqual(actual.alight.id, expected.alight.id)
        XCTAssertEqual(actual.totalSeconds, expected.totalSeconds, accuracy: 0.01)
    }

    @MainActor
    func testPlazoDeDirectionsCancelaYDescartaRespuestaTardia() async throws {
        var callback: PendingDirections.Completion?
        var cancellations = 0
        let pending = PendingDirections(start: { callback = $0 }, cancel: { cancellations += 1 })
        let start = Date()
        do {
            _ = try await pending.run(timeout: 0.02)
            XCTFail("No debe esperar indefinidamente una respuesta que no llega")
        } catch {
            XCTAssertEqual(error as? RouteCalculationError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(cancellations, 1)
        callback?(.failure(RouteCalculationError.noRoutesAvailable))
        await Task.yield()
        XCTAssertEqual(cancellations, 1, "El callback tardío no debe finalizar dos veces")
    }

    @MainActor
    func testCancelarDirectionsNoEsperaElTimeout() async throws {
        let started = expectation(description: "request started")
        var cancellations = 0
        let pending = PendingDirections(start: { _ in started.fulfill() }, cancel: { cancellations += 1 })
        let task = Task { try await pending.run(timeout: 10) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Se esperaba cancelación")
        } catch is CancellationError {} catch { XCTFail("Error inesperado: \(error)") }
        XCTAssertEqual(cancellations, 1)
    }

    func testCacheDeCaminatasExpiraYNoGuardaFallos() async throws {
        let clock = DirectionsTestClock()
        let probe = DirectionsProbe()
        let service = RouteCalculationService(loader: { request in try await probe.load(request, fail: false) },
                                              now: { clock.date() })
        let points = rutaSintetica().shape
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        clock.advance(301)
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
        let failedProbe = DirectionsProbe()
        let failing = RouteCalculationService(loader: { request in try await failedProbe.load(request, fail: true) })
        for _ in 0..<2 {
            do {
                _ = try await failing.calculateRoute(from: points[0], to: points[5], transportType: .walking)
                XCTFail("Se esperaba fallo")
            } catch { XCTAssertEqual(error as? RouteCalculationError, .noRoutesAvailable) }
        }
        let failures = await failedProbe.calls
        XCTAssertEqual(failures, 2)
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

    func testParaderoGuardadoConservaIdentidadAlRecargar() throws {
        let saved = LugarGuardado(nombre: "Paradero de prueba", direccion: "Trujillo",
                                 categoria: .otro, lat: -8.1, lon: -79.03, paraderoID: "stop-test")
        LugaresStore.guardar([LugaresStore.lugarUTP(), saved])
        LugaresStore.invalidarCache()
        let restored = try XCTUnwrap(LugaresStore.cargar().first { $0.id == saved.id })
        XCTAssertEqual(restored.paraderoID, "stop-test")
        let model = SeguridadLugaresModel()
        model.cargar()
        model.eliminar(restored)
        LugaresStore.invalidarCache()
        XCTAssertFalse(LugaresStore.cargar().contains { $0.id == saved.id })
    }

    func testParaderoAnteriorSinIdentificadorSigueSiendoLegible() throws {
        let saved = LugarGuardado(nombre: "Paradero anterior", direccion: "Trujillo",
                                 categoria: .otro, lat: -8.1, lon: -79.03)
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        body.removeValue(forKey: "paraderoID")
        let restored = try JSONDecoder().decode(LugarGuardado.self, from: JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(restored.nombre, saved.nombre)
        XCTAssertNil(restored.paraderoID)
        let stop = ParaderoGTFS(id: "legacy-stop", nombre: "Paradero anterior", lat: -8.1, lon: -79.03)
        XCTAssertTrue(restored.corresponde(al: stop))
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

private actor DirectionsProbe {
    var calls = 0
    var active = 0
    var maximumConcurrent = 0
    var cancelled = 0
    func load(_ request: MKDirections.Request, fail: Bool) async throws -> CalculatedRoute {
        calls += 1
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        defer { active -= 1 }
        do { try await Task.sleep(for: .milliseconds(100)) }
        catch { cancelled += 1; throw error }
        if fail { throw RouteCalculationError.noRoutesAvailable }
        let points = [request.source!.placemark.coordinate, request.destination!.placemark.coordinate]
        return CalculatedRoute(polyline: MKPolyline(coordinates: points, count: 2),
                               expectedTravelTime: 1, distance: PolylineMatching.totalLengthMeters(points), steps: [])
    }
}

private final class DirectionsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func date() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}
