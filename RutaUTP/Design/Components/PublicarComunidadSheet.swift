//
//  PublicarComunidadSheet.swift
//  RutaUTP
//
//  Sheet para publicar en la Comunidad (botón AÑADIR de la sección
//  Comunidad en Seguridad). Visualmente distinto al ReportarSheet
//  (megáfono/incidente, acento primary): aquí el acento es tertiary y el
//  foco es la comunidad, pero comparte el contenido base (tipo + descripción)
//  y agrega dos adjuntos opcionales:
//    - Foto: tomada con la cámara o elegida de la galería (PHPicker, sin
//      pedir permiso de fotos).
//    - Ubicación: mapa de Apple Maps (MapKit) a pantalla completa con pin
//      fijo al centro (estilo selector tipo Uber) para marcar el lugar.
//

import SwiftUI
import PhotosUI
import MapKit
import CoreLocation

struct PublicarComunidadSheet: View {

    @Environment(\.dismiss) private var dismiss

    // Contenido base (mismos campos que ReportarSheet)
    @State private var tipo: TipoReporte = .alerta
    @State private var descripcion: String = ""

    // Foto opcional (cámara o galería)
    @State private var foto: UIImage?
    @State private var showFuenteFoto = false
    @State private var showCamara = false
    @State private var showGaleria = false

    // Ubicación opcional (Apple Maps)
    @State private var mostrarMapa = false
    @State private var ubicacion: CLLocationCoordinate2D?
    @State private var direccionUbicacion: String?
    @State private var geolocalizando = false
    private let geocoder = CLGeocoder()

    @State private var showSuccess = false

    private var puedeEnviar: Bool {
        !descripcion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    encabezado
                    // Selector, detalle y descripción: compartidos con Reportar.
                    SelectorTipoReporte(tipo: $tipo)
                    DetalleTipoReporte(tipo: tipo)
                    CampoDescripcionReporte(descripcion: $descripcion, tipo: tipo)
                    seccionFoto
                    seccionUbicacion
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { botonPublicar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .confirmationDialog(L.t("Foto del aporte", "Post photo"),
                            isPresented: $showFuenteFoto,
                            titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(L.t("Tomar foto", "Take photo")) { showCamara = true }
            }
            Button(L.t("Elegir de la galería / biblioteca de fotos", "Choose from photo library")) {
                showGaleria = true
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        }
        .sheet(isPresented: $showCamara) {
            ImagePicker(sourceType: .camera) { foto = $0 }
        }
        .sheet(isPresented: $showGaleria) {
            GaleriaPicker { foto = $0 }
        }
        .fullScreenCover(isPresented: $mostrarMapa) {
            MapaUbicacionPicker(inicial: ubicacion) { coord in
                ubicacion = coord
                geocodificar(coord)
            }
        }
        // Mismo criterio que ReportarSheet: la publicación no llega a ningún
        // servidor todavía, así que la confirmación lo dice en lugar de
        // prometer un envío que no ocurre.
        .alert(L.t("Publicación registrada", "Post recorded"),
               isPresented: $showSuccess) {
            Button(L.t("Listo", "Done")) { dismiss() }
        } message: {
            Text(L.t("Gracias por aportar a la comunidad UTP. En esta versión de prueba la publicación no se comparte con otros usuarios.",
                     "Thanks for contributing to the UTP community. In this trial version the post isn't shared with other users."))
        }
    }

    // MARK: - Encabezado (acento comunidad: tertiary, distinto al reporte)

    private var encabezado: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.tertiary.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Publicar en la comunidad", "Post to the community"))
                    .font(.headlineMd)
                    .foregroundStyle(.onSurface)
                Text(L.t("Comparte algo útil con otros estudiantes",
                         "Share something helpful with other students"))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
        }
    }

    // MARK: - Foto (cámara o galería)

    private var seccionFoto: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("FOTO (OPCIONAL)", "PHOTO (OPTIONAL)"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            if let foto {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: foto)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                        )
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) { self.foto = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel(L.t("Quitar foto", "Remove photo"))
                }
            } else {
                Button {
                    AppHaptics.selection()
                    showFuenteFoto = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.tertiary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.t("Añadir foto", "Add photo"))
                                .font(.bodyMdMedium)
                                .foregroundStyle(.onSurface)
                            Text(L.t("Toma una foto o elige de tu galería",
                                     "Take a photo or pick from your library"))
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.surfaceContainerLow)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.35), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Ubicación (Apple Maps)

    private var seccionUbicacion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("UBICACIÓN (OPCIONAL)", "LOCATION (OPTIONAL)"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            if let ubi = ubicacion {
                // Mini-mapa con el pin marcado; tocar vuelve a abrir el selector.
                Button {
                    AppHaptics.selection()
                    mostrarMapa = true
                } label: {
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: ubi, distance: 600))) {
                        Marker(L.t("Lugar del incidente", "Incident location"), coordinate: ubi)
                    }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Editar ubicación en el mapa", "Edit location on map"))

                HStack(spacing: 6) {
                    if geolocalizando {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(geolocalizando
                         ? L.t("Buscando dirección…", "Looking up address…")
                         : (direccionUbicacion ?? coordenadasTexto(ubi)))
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            ubicacion = nil
                            direccionUbicacion = nil
                        }
                        geocoder.cancelGeocode()
                    } label: {
                        Text(L.t("Quitar", "Remove"))
                            .font(.bodySmMedium)
                            .foregroundStyle(.appError)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    AppHaptics.selection()
                    mostrarMapa = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.appPrimary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.appPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.t("Marcar en el mapa", "Mark on the map"))
                                .font(.bodyMdMedium)
                                .foregroundStyle(.onSurface)
                            Text(L.t("Abre Apple Maps y señala el lugar del incidente",
                                     "Open Apple Maps and point to the incident location"))
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.surfaceContainerLow)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.outline.opacity(0.4),
                                          style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func coordenadasTexto(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
    }

    private func geocodificar(_ coord: CLLocationCoordinate2D) {
        geocoder.cancelGeocode()
        geolocalizando = true
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            DispatchQueue.main.async {
                geolocalizando = false
                if let pm = placemarks?.first {
                    let partes = [pm.thoroughfare, pm.subThoroughfare, pm.locality]
                        .compactMap { $0 }
                    if !partes.isEmpty {
                        direccionUbicacion = partes.joined(separator: " ")
                        return
                    }
                }
                direccionUbicacion = nil
            }
        }
    }

    // MARK: - Publicar

    private var botonPublicar: some View {
        Button {
            AppHaptics.success()
            showSuccess = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(L.t("Publicar en la comunidad", "Post to the community"))
                    .font(.headlineSm)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: puedeEnviar
                                ? [.tertiary, .tertiary.opacity(0.78)]
                                : [Color.onSurfaceVariant.opacity(0.35), Color.onSurfaceVariant.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: puedeEnviar ? .tertiary.opacity(0.35) : .clear,
                            radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
        .disabled(!puedeEnviar)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: puedeEnviar)
    }
}

// MARK: - Selector de ubicación a pantalla completa (Apple Maps)

/// Mapa de Apple Maps (MapKit) con pin fijo al centro: el usuario mueve el
/// mapa debajo del pin para señalar el lugar y confirma. Centra en la
/// ubicación actual del GPS (botón blanco circular para volver a ella, igual
/// al de la pestaña Mapa); si el GPS no responde, en el campus UTP.
private struct MapaUbicacionPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirmar: (CLLocationCoordinate2D) -> Void
    /// Si el usuario venía a editar un pin ya marcado, el primer fix del GPS
    /// NO mueve la cámara (no le quitamos la vista de su lugar elegido).
    private let teniaUbicacionPrevia: Bool

    /// Campus UTP (Trujillo) como centro por defecto.
    private static let centroDefault = CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287)
    @State private var centro: CLLocationCoordinate2D
    @State private var posicion: MapCameraPosition

    // GPS real (mismo servicio que la pestaña Mapa)
    @State private var userRealCoordinate: CLLocationCoordinate2D?
    @State private var locationTask: Task<Void, Never>?
    @StateObject private var locationService = LocationService()

    init(inicial: CLLocationCoordinate2D?, onConfirmar: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onConfirmar = onConfirmar
        self.teniaUbicacionPrevia = (inicial != nil)
        let centroInicial = inicial ?? Self.centroDefault
        _centro = State(initialValue: centroInicial)
        _posicion = State(initialValue: .camera(MapCamera(centerCoordinate: centroInicial, distance: 900)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $posicion)
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .onEnd) { context in
                    centro = context.camera.centerCoordinate
                }

            // Pin fijo al centro (la punta apunta al centro del mapa).
            Image(systemName: "mappin")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.appPrimary)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                .frame(width: 44, height: 44)
                .offset(y: -22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Volver a mi ubicación (abajo a la derecha, flotando sobre el
            // panel de confirmar y sin pegarse al marco del teléfono).
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    botonMiUbicacion
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { barraSuperior }
        .safeAreaInset(edge: .bottom, spacing: 0) { panelConfirmar }
        .task { iniciarGPS(autoCentrar: !teniaUbicacionPrevia) }
        .onDisappear {
            locationTask?.cancel()
            locationService.stopUpdating()
        }
    }

    // MARK: - Botón Mi Ubicación (idéntico al de la pestaña Mapa)
    private var botonMiUbicacion: some View {
        BotonMiUbicacion(tieneUbicacion: userRealCoordinate != nil) {
            if let userCoord = userRealCoordinate {
                withAnimation(.spring(response: 0.5)) {
                    posicion = .region(MKCoordinateRegion(
                        center: userCoord,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    ))
                }
                centro = userCoord
            } else {
                iniciarGPS(autoCentrar: true)
            }
        }
    }

    // MARK: - GPS (mismo flujo que MapaViewModel.iniciarGPS)
    private func iniciarGPS(autoCentrar: Bool) {
        locationTask?.cancel()
        locationTask = Task { @MainActor in
            let status = await locationService.requestPermission()
            guard status.isAuthorized else { return }
            locationService.startUpdating()
            for await location in locationService.currentLocation() {
                let esPrimerFix = (userRealCoordinate == nil)
                userRealCoordinate = location.coordinate
                if esPrimerFix && autoCentrar {
                    withAnimation(.spring(response: 0.5)) {
                        posicion = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                        ))
                    }
                    centro = location.coordinate
                }
            }
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))

            Text(L.t("Arrastra el mapa para marcar el lugar", "Drag the map to mark the location"))
                .font(.bodySmMedium)
                .foregroundStyle(.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var panelConfirmar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(String(format: "%.4f, %.4f", centro.latitude, centro.longitude))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Spacer()
            }
            .foregroundStyle(.onSurfaceVariant)

            Button {
                AppHaptics.success()
                onConfirmar(centro)
                dismiss()
            } label: {
                Text(L.t("Confirmar ubicación", "Confirm location"))
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.appPrimary))
            }
            .buttonStyle(PressableCapsuleStyle())
        }
        .padding(16)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.appBackground)
                .shadow(color: .black.opacity(0.18), radius: 14, y: -4)
        )
    }
}

// MARK: - Galería (PHPicker, sin permiso de fotos)

struct GaleriaPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GaleriaPicker
        init(_ parent: GaleriaPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Conservar el callback antes de cerrar el sheet: el coordinador
            // puede liberarse mientras Fotos carga la imagen seleccionada.
            let onImagePicked = parent.onImagePicked
            parent.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { objeto, _ in
                guard let imagen = objeto as? UIImage else { return }
                DispatchQueue.main.async { onImagePicked(imagen) }
            }
        }
    }
}

#Preview {
    PublicarComunidadSheet()
}
