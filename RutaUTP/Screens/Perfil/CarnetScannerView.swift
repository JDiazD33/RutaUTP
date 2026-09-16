import SwiftUI
import AVFoundation
import UIKit

/// Foto del carné físico, independiente de la foto de perfil.
enum CarnetImageStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("utp-card.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    static func save(_ image: UIImage) throws -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Normaliza la orientación y limita el peso sin recortar el documento.
        let factor = min(1, 2400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.9),
              let stored = UIImage(data: data) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return stored
    }
}

struct CarnetScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onCapture: () -> Void
    @State private var foto: UIImage?
    @State private var picker: Fuente?
    @State private var guardando = false
    @State private var errorGuardado = false
    @State private var permisoDenegado = false
    @State private var verFoto = false
    @State private var fotoPorEditar: UIImage?
    @State private var editor: FotoParaEncuadrar?
    @State private var selectorCerrado = true

    private enum Fuente: String, Identifiable {
        case camara, galeria
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let foto {
                        Button { verFoto = true } label: {
                            Image(uiImage: foto)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Ver foto del carné ampliada", "Enlarge card photo"))
                        Label(L.t("Foto guardada en este dispositivo", "Photo saved on this device"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.appPrimary)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(Color.appPrimary)
                            Text(L.t("Tu carné, siempre a mano", "Your card, always handy"))
                                .font(.title3.bold())
                            Text(L.t("Añade una foto donde se vea completo y el texto sea legible.", "Add a photo showing the entire card with readable text."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 16)
                        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if guardando {
                        ProgressView(L.t("Guardando foto…", "Saving photo…"))
                    }
                    VStack(spacing: 12) {
                        Button(action: abrirCamara) {
                            Label(L.t("Tomar foto", "Take photo"), systemImage: "camera")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Button { selectorCerrado = false; picker = .galeria } label: {
                            Label(L.t("Elegir de la galería", "Choose from photo library"), systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        if let foto {
                            Button {
                                editor = FotoParaEncuadrar(image: foto)
                            } label: {
                                Label(L.t("Ajustar encuadre", "Adjust framing"), systemImage: "crop")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .tint(Color.appPrimary)
                    .disabled(guardando)
                    Text(L.t("Puedes cambiar la foto cuando quieras. Se conserva al cerrar la app. Guardarla no verifica tu identidad universitaria.", "You can replace the photo anytime. It stays saved after closing the app. Saving it does not verify your university identity."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(Color.appSurface)
            .navigationTitle(L.t("Carnet Universitario", "University Card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }.disabled(guardando)
                }
            }
        }
        .onAppear { if foto == nil { foto = CarnetImageStore.load() } }
        .fullScreenCover(item: $picker, onDismiss: {
            selectorCerrado = true
            presentarEditor()
        }) { fuente in
            if fuente == .camara {
                ImagePicker(sourceType: .camera, allowsEditing: false, onImagePicked: prepararEdicion)
                    .ignoresSafeArea()
            } else {
                GaleriaPicker(onImagePicked: prepararEdicion).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $editor) { seleccion in
            EncuadreFotoView(image: seleccion.image) { ajustada in
                editor = nil
                guardar(ajustada)
            }
        }
        .sheet(isPresented: $verFoto) {
            NavigationStack {
                if let foto {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: foto)
                            .resizable()
                            .scaledToFit()
                            .frame(width: max(UIScreen.main.bounds.width, 900))
                    }
                    .navigationTitle(L.t("Foto del carné", "Card photo"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L.t("Cerrar", "Close")) { verFoto = false }
                        }
                    }
                }
            }
        }
        .alert(L.t("No se pudo guardar la foto", "Couldn't save photo"), isPresented: $errorGuardado) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("La foto anterior se conserva. Comprueba el espacio disponible e inténtalo de nuevo.", "Your previous photo is preserved. Check available storage and try again."))
        }
        .alert(L.t("Permiso de cámara", "Camera permission"), isPresented: $permisoDenegado) {
            Button(L.t("Abrir Ajustes", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L.t("Activa el acceso a la cámara o elige una foto de la galería.", "Enable camera access or choose a photo from your library."))
        }
    }

    private func abrirCamara() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: selectorCerrado = false; picker = .camara
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                DispatchQueue.main.async {
                    if allowed { selectorCerrado = false; picker = .camara } else { permisoDenegado = true }
                }
            }
        default: permisoDenegado = true
        }
    }

    private func prepararEdicion(_ image: UIImage) {
        fotoPorEditar = image
        if selectorCerrado { presentarEditor() }
    }

    private func presentarEditor() {
        guard let image = fotoPorEditar else { return }
        fotoPorEditar = nil
        editor = FotoParaEncuadrar(image: image)
    }

    private func guardar(_ image: UIImage) {
        guard !guardando else { return }
        guardando = true
        Task { @MainActor in
            // El guardado normaliza la orientación y escribe el JPEG: trabajo
            // de disco que no debe bloquear la interfaz. Antes se hacía con
            // GCD + Result, mezclado con el async/await del resto del módulo.
            let guardada = await Task.detached(priority: .userInitiated) {
                try? CarnetImageStore.save(image)
            }.value

            guardando = false
            if let guardada {
                foto = guardada
                onCapture()
                AppHaptics.success()
            } else {
                errorGuardado = true
            }
        }
    }
}

#Preview {
    CarnetScannerView(onCapture: {})
}

struct FotoParaEncuadrar: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// El mismo rectángulo y transformación se usan para la vista previa y el archivo.
struct EncuadreFotoView: View {
    let image: UIImage
    var esPerfil = false
    let onGuardar: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var desplazamiento: CGSize = .zero
    @GestureState private var arrastre: CGSize = .zero
    @GestureState private var aumento: CGFloat = 1

    private var proporcion: CGFloat { esPerfil ? 1 : 1.586 }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let ancho = max(1, min(geo.size.width - 32, 600))
                let marco = CGSize(width: ancho, height: ancho / proporcion)
                let escala = escalaBase(marco) * min(6, max(1, zoom * aumento))
                let posicion = limitar(CGSize(width: desplazamiento.width + arrastre.width,
                                               height: desplazamiento.height + arrastre.height), marco: marco, escala: escala)
                ScrollView {
                    VStack(spacing: 24) {
                        Text(esPerfil ? L.t("Mueve la foto y ajusta el zoom para centrar tu rostro en el círculo.", "Drag and zoom to center your face in the circle.") : L.t("Mueve la foto y pellizca para acercarla. Deja el carné completo dentro del marco.", "Drag and pinch to zoom. Keep the entire card inside the frame."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: image.size.width * escala, height: image.size.height * escala)
                                .offset(posicion)
                        }
                        .frame(width: marco.width, height: marco.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: esPerfil ? marco.width / 2 : 0))
                        .overlay(RoundedRectangle(cornerRadius: esPerfil ? marco.width / 2 : 0).stroke(Color.appPrimary, lineWidth: 2).allowsHitTesting(false))
                        .contentShape(Rectangle())
                        .gesture(DragGesture()
                            .updating($arrastre) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                desplazamiento = limitar(CGSize(width: desplazamiento.width + value.translation.width,
                                                                height: desplazamiento.height + value.translation.height),
                                                         marco: marco, escala: escalaBase(marco) * zoom)
                            }
                            // MagnifyGesture sustituye a MagnificationGesture,
                            // obsoleta en iOS 17 (el mínimo del proyecto).
                            .simultaneously(with: MagnifyGesture()
                                .updating($aumento) { value, state, _ in
                                    state = value.magnification
                                }
                                .onEnded { value in
                                    zoom = min(6, max(1, zoom * value.magnification))
                                    desplazamiento = limitar(desplazamiento, marco: marco, escala: escalaBase(marco) * zoom)
                                }))
                        .accessibilityLabel(L.t("Vista previa del recorte", "Crop preview"))
                        VStack {
                            Label(L.t("Ampliación", "Zoom"), systemImage: "plus.magnifyingglass")
                            Slider(value: $zoom, in: 1...6)
                                .accessibilityLabel(L.t("Ampliación", "Zoom"))
                        }
                        Button(L.t("Restablecer encuadre", "Reset framing")) {
                            zoom = 1
                            desplazamiento = .zero
                        }
                        Button {
                            let escalaFinal = escalaBase(marco) * zoom
                            let offset = limitar(desplazamiento, marco: marco, escala: escalaFinal)
                            let factor = min(2400 / marco.width, 1 / escalaFinal)
                            let salida = CGSize(width: marco.width * factor, height: marco.height * factor)
                            let formato = UIGraphicsImageRendererFormat()
                            formato.scale = 1
                            formato.opaque = true
                            let recorte = UIGraphicsImageRenderer(size: salida, format: formato).image { _ in
                                image.draw(in: CGRect(
                                    x: ((marco.width - image.size.width * escalaFinal) / 2 + offset.width) * factor,
                                    y: ((marco.height - image.size.height * escalaFinal) / 2 + offset.height) * factor,
                                    width: image.size.width * escalaFinal * factor,
                                    height: image.size.height * escalaFinal * factor))
                            }
                            onGuardar(recorte)
                        } label: {
                            Text(L.t("Guardar encuadre", "Save framing"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(esPerfil ? L.t("Encuadrar foto de perfil", "Frame profile photo") : L.t("Encuadrar carné", "Frame card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .tint(Color.appPrimary)
    }

    private func escalaBase(_ marco: CGSize) -> CGFloat {
        max(marco.width / image.size.width, marco.height / image.size.height)
    }

    private func limitar(_ offset: CGSize, marco: CGSize, escala: CGFloat) -> CGSize {
        let x = max(0, (image.size.width * escala - marco.width) / 2)
        let y = max(0, (image.size.height * escala - marco.height) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
}


/// Flujo común para la foto que comparten Perfil, menú y carné digital.
struct EditorFotoPerfilModifier: ViewModifier {
    @Binding var camara: Bool
    @Binding var galeria: Bool
    @Binding var ajustar: Bool
    let onGuardar: (UIImage) -> Void
    @State private var pendiente: UIImage?
    @State private var editor: FotoParaEncuadrar?
    @State private var selectorCerrado = true
    @State private var errorGuardado = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $camara, onDismiss: cerrarSelector) {
                ImagePicker(sourceType: .camera, allowsEditing: false, onImagePicked: recibir)
                    .onAppear { selectorCerrado = false }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $galeria, onDismiss: cerrarSelector) {
                GaleriaPicker(onImagePicked: recibir)
                    .onAppear { selectorCerrado = false }
            }
            .onChange(of: ajustar) { _, valor in
                guard valor else { return }
                ajustar = false
                if let foto = ProfileImageStore.load() { editor = FotoParaEncuadrar(image: foto) }
            }
            .fullScreenCover(item: $editor) { seleccion in
                EncuadreFotoView(image: seleccion.image, esPerfil: true) { imagen in
                    if ProfileImageStore.save(imagen) {
                        onGuardar(imagen)
                        editor = nil
                    } else {
                        errorGuardado = true
                    }
                }
                .alert(L.t("No se pudo guardar la foto", "Couldn't save photo"), isPresented: $errorGuardado) {
                    Button(L.t("Aceptar", "OK"), role: .cancel) {}
                } message: {
                    Text(L.t("Comprueba el espacio disponible e inténtalo de nuevo. Tu foto anterior se conserva.", "Check available storage and try again. Your previous photo is preserved."))
                }
            }
    }

    private func recibir(_ imagen: UIImage) {
        pendiente = imagen
        if selectorCerrado { presentar() }
    }

    private func cerrarSelector() {
        selectorCerrado = true
        presentar()
    }

    private func presentar() {
        guard let imagen = pendiente else { return }
        pendiente = nil
        editor = FotoParaEncuadrar(image: imagen)
    }
}
