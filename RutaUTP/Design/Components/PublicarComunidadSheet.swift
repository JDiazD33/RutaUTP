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
import MapKit
import CoreLocation

struct PublicarComunidadSheet: View {

    let locationService: LocationServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

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
    @StateObject private var geocodificacion = GeocodificacionComunidadModel()

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
        .onDisappear { geocodificacion.cancelar() }
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
            MapaUbicacionPicker(inicial: ubicacion, locationService: locationService) { coord in
                ubicacion = coord
                geocodificacion.buscar(coord)
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
                        .accessibilityLabel(L.t("Foto del aporte", "Post photo"))
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) { self.foto = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.t("Añadir foto", "Add photo"))
                .accessibilityHint(L.t("Toma una foto o elige de tu galería", "Take a photo or pick from your library"))
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

                (textSize >= .xxxLarge
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 6))) {
                    HStack(alignment: .top, spacing: 6) {
                        if geocodificacion.buscando {
                            ProgressView().controlSize(.small)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 13, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(geocodificacion.buscando
                             ? L.t("Buscando dirección…", "Looking up address…")
                             : (geocodificacion.direccion ?? coordenadasTexto(ubi)))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            ubicacion = nil
                        }
                        geocodificacion.cancelar(limpiar: true)
                    } label: {
                        Text(L.t("Quitar", "Remove"))
                            .font(.bodySmMedium)
                            .foregroundStyle(.appError)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Quitar ubicación", "Remove location"))
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
                                .foregroundStyle(.appAccent)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.t("Marcar ubicación en el mapa", "Mark location on the map"))
            }
        }
    }

    private func coordenadasTexto(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
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
                    .fixedSize(horizontal: false, vertical: true)
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

#Preview {
    PublicarComunidadSheet(locationService: LocationService())
}
