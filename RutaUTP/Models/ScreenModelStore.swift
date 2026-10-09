import Combine

/// Conserva la creación diferida de StateObject y una sola instancia por pantalla.
/// La UI observa las propiedades del modelo; este contenedor no reenvía cambios.
final class ScreenModelStore<Model: AnyObject>: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let model: Model

    init(_ model: Model) {
        self.model = model
    }
}
