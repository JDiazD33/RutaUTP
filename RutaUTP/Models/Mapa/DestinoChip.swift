import Foundation

// MARK: - Destino chip
struct DestinoChip: Identifiable, Equatable {
    let id: Int
    let label: String
    let icon: String
    let lat: Double
    let lon: Double
    /// Clave estable del Modo Señas (nil = el chip no es señable).
    let claveSenia: String?

    init(id: Int, label: String, icon: String, lat: Double, lon: Double, claveSenia: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.lat = lat
        self.lon = lon
        self.claveSenia = claveSenia
    }
}

