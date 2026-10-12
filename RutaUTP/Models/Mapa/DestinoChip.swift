import Foundation

// MARK: - Destino chip
struct DestinoChip: Identifiable, Equatable {
    let id: Int
    private let etiquetaOriginal: String
    var label: String {
        if let fijo = DestinosFijos.todos.first(where: { $0.claveSenia == claveSenia && $0.lat == lat && $0.lon == lon }) {
            return fijo.label
        }
        return etiquetaOriginal
    }
    let icon: String
    let lat: Double
    let lon: Double
    /// Clave estable del Modo Señas (nil = el chip no es señable).
    let claveSenia: String?

    init(id: Int, label: String, icon: String, lat: Double, lon: Double, claveSenia: String? = nil) {
        self.id = id
        self.etiquetaOriginal = label
        self.icon = icon
        self.lat = lat
        self.lon = lon
        self.claveSenia = claveSenia
    }
}

