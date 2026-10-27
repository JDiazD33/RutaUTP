//
//  MapaViewModel+Destinos.swift
//  RutaUTP
//
//  Chips de destino: referencias fijas y lugares guardados.
//  La lista se calcula en cada lectura para respetar el idioma activo.
//

import Foundation

extension MapaViewModel {
    /// Reconstruye los chips: fijos + lugares guardados por el usuario.
    ///
    /// Llamar al aparecer la pantalla (onAppear): si el usuario guardó o
    /// eliminó un lugar en la pestaña Guardado, el chip aparece/desaparece
    /// aquí sin reiniciar la app. LugaresStore es la misma fuente que
    /// GuardadoView, así ambos siempre ven lo mismo.
    func refrescarDestinos() {
        lugaresParaChips = LugaresStore.cargar()

        // Si el destino seleccionado era un chip guardado que ya no existe,
        // limpiarlo para no mostrar una ruta hacia un lugar eliminado.
        if let seleccionado = destinoSeleccionado,
           seleccionado.id >= 100,
           !destinos.contains(where: { $0.id == seleccionado.id && $0.label == seleccionado.label }) {
            destinoSeleccionado = nil
            busquedaResultado = nil
            invalidarSeleccionAnterior()
        }
    }

    // Máximo de chips visibles en el panel del mapa (fijos + guardados).
    static let maxDestinos = 6

    /// Nombres en español de los chips fijos, para no duplicar un lugar
    /// guardado que ya es un chip. Se derivan de `DestinosFijos` (fuente única).
    private static let nombresFijosEstables: Set<String> = DestinosFijos.nombresEstables

    /// Chips de inicio: la sede elegida y referencias conocidas de Trujillo.
    /// Casa/Trabajo ya no son fijos: si el usuario los guarda, aparecen solos.
    ///
    /// El dato (coordenadas, icono y clave señable) vive en `DestinosFijos`,
    /// compartido con el módulo de tracking: antes estaba escrito literalmente
    /// en los dos sitios. Aquí solo se adapta al tipo de esta pantalla.
    ///
    /// Calculada y no almacenada: el `label` sale en el idioma activo en cada
    /// lectura. Con el texto congelado en un `let`, cambiar de idioma dejaría
    /// los chips en el idioma anterior (una lista pequeña de referencias).
    private var destinosFijos: [DestinoChip] {
        let referencias = DestinosFijos.todos.filter { utpComoReferencia || $0.id != 1 }.map {
            DestinoChip(id: $0.id, label: $0.label, icon: $0.icono,
                        lat: $0.lat, lon: $0.lon, claveSenia: $0.claveSenia)
        }
        guard let sedeTrabajo else { return referencias }
        let sede = DestinoChip(id: CatalogoSedesTrabajo.idChipSede,
                               label: sedeTrabajo.nombre, icon: "building.2.fill",
                               lat: sedeTrabajo.lat, lon: sedeTrabajo.lon)
        return [sede] + referencias
    }

    /// Chips visibles: fijos primero, luego los lugares que el usuario guardó
    /// en la pestaña Guardado (vía LugaresStore), hasta un total de 6.
    ///
    /// CALCULADA, no almacenada: la etiqueta de los chips fijos se resuelve en
    /// el idioma activo en cada lectura. Antes era un `@Published` que se
    /// construía una sola vez, así que al cambiar de idioma los chips se
    /// quedaban en el idioma anterior («Centro» en vez de «Downtown»).
    var destinos: [DestinoChip] {
        let guardados = lugaresParaChips
            .filter { lugar in
                // Solo lugares con coordenadas y que no dupliquen un chip fijo.
                guard lugar.coordinate != nil else { return false }
                return !Self.nombresFijosEstables.contains(lugar.nombre.lowercased())
            }
            .prefix(Self.maxDestinos - destinosFijos.count)
            .enumerated()
            .map { indice, lugar in
                DestinoChip(id: 100 + indice,
                            label: lugar.nombre,
                            icon: lugar.icono,
                            lat: lugar.lat ?? 0,
                            lon: lugar.lon ?? 0)
            }
        return destinosFijos + guardados
    }
}
