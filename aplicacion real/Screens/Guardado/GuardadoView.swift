//
//  GuardadoView.swift
//  RutaUTP
//
//  Lugares y líneas guardadas. Tabs + sheets de detalle + sheet para añadir lugar.
//

import SwiftUI
import MapKit

struct GuardadoView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedTab: Tab = .lugares
    @State private var lugares: [LugarGuardado]
    @State private var showAddSheet = false
    @State private var selectedLugar: LugarGuardado?
    @State private var selectedLinea: LineaGuardada?

    init() {
        _lugares = State(initialValue: Self.sampleLugares())
    }

    enum Tab: String, CaseIterable, Identifiable {
        case lugares = "Lugares"
        case lineas  = "Líneas"
        var id: String { rawValue }
    }

    private let lineas: [LineaGuardada] = [
        LineaGuardada(id: "B", letra: "B", nombre: "Línea B — Empresa Salaverry",
                      recorrido: "Salaverry → UTP → Centro", tiempoEstimado: "~4 min", color: .tertiary),
        LineaGuardada(id: "7", letra: "7", nombre: "Línea 7 — El Esfuerzo",
                      recorrido: "Huanchaco → Centro → La Esperanza", tiempoEstimado: "~12 min", color: .tertiary),
        LineaGuardada(id: "C", letra: "C", nombre: "Línea C — Trans Moche",
                      recorrido: "Moche → Av. España → Plaza Mayor", tiempoEstimado: "~20 min", color: .onSurfaceVariant)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabs
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case .lugares: lugaresSection
                        case .lineas:  lineasSection
                        }
                    }
                    .padding(.bottom, 90)
                }
            }
            .padding(.bottom, 64)

            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showAddSheet) {
            AddLugarSheet { nuevo in
                lugares.insert(nuevo, at: 0)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $selectedLugar) { lugar in
            LugarDetailSheet(lugar: lugar) {
                lugares.removeAll { $0.id == lugar.id }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedLinea) { linea in
            LineaDetailSheet(linea: linea)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text("Guardado")
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Añadir")
                        .font(.labelCapsMd)
                        .appTracking(AppTracking.wideLabel)
                }
                .foregroundStyle(.onPrimaryContainer)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primaryContainer))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Añadir lugar guardado")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Tabs
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = t }
                } label: {
                    VStack(spacing: 6) {
                        Text(t.rawValue)
                            .font(.bodyMdMedium)
                            .foregroundStyle(selectedTab == t ? Color.appPrimary : Color.onSurfaceVariant)
                        Rectangle()
                            .fill(selectedTab == t ? Color.appPrimary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Lugares section
    private var lugaresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Toca un lugar para ver más opciones.")
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if lugares.isEmpty {
                emptyState
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(lugares) { lugar in
                        lugarRow(lugar)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func lugarRow(_ lugar: LugarGuardado) -> some View {
        Button {
            selectedLugar = lugar
        } label: {
            HStack(spacing: 14) {
                iconCircle(lugar: lugar)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(lugar.nombre)
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurface)
                        if lugar.esFrecuente {
                            Text("FRECUENTE")
                                .font(.labelCapsMd)
                                .foregroundStyle(.onTertiary)
                                .appTracking(AppTracking.wideLabel)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.tertiary))
                        }
                    }
                    Text(lugar.direccion)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func iconCircle(lugar: LugarGuardado) -> some View {
        let isPrimary = (lugar.nombre == "UTP")
        let bg: Color = isPrimary ? .appPrimary : .primaryContainer.opacity(0.15)
        let fg: Color = isPrimary ? .white : .appPrimary
        return ZStack {
            Circle().fill(bg).frame(width: 48, height: 48)
            Image(systemName: lugar.categoria.icono)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(fg)
        }
    }

    // MARK: - Lineas section
    private var lineasSection: some View {
        VStack(spacing: 12) {
            ForEach(lineas) { linea in
                lineaRow(linea)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func lineaRow(_ linea: LineaGuardada) -> some View {
        Button {
            selectedLinea = linea
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.primaryContainer).frame(width: 40, height: 40)
                    Text(linea.letra)
                        .font(.headlineSm)
                        .foregroundStyle(.onPrimaryContainer)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(linea.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(linea.recorrido)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                Text(linea.tiempoEstimado)
                    .font(.labelCapsMd)
                    .foregroundStyle(.white)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.tertiary))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.onSurfaceVariant)
            Text("Aún no tienes lugares guardados")
                .font(.bodyMdMedium)
                .foregroundStyle(.onSurface)
            Text("Toca + Añadir para guardar tu primer lugar.")
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sample data
    private static func sampleLugares() -> [LugarGuardado] {
        [
            LugarGuardado(nombre: "UTP", direccion: "Av. España 123, Trujillo",
                          categoria: .universidad, esFrecuente: true, colorBadge: .appPrimary),
            LugarGuardado(nombre: "Casa", direccion: "Urb. El Recreo, Trujillo",
                          categoria: .hogar, esFrecuente: false, colorBadge: .appPrimary),
            LugarGuardado(nombre: "Centro Comercial", direccion: "Mall Plaza Trujillo",
                          categoria: .tienda, esFrecuente: false, colorBadge: .appPrimary),
            LugarGuardado(nombre: "Pastelería Dulce Lima", direccion: "Av. Larco 456",
                          categoria: .restaurante, esFrecuente: false, colorBadge: .appPrimary),
            LugarGuardado(nombre: "Plaza de Armas", direccion: "Centro Histórico",
                          categoria: .plaza, esFrecuente: false, colorBadge: .appPrimary),
            LugarGuardado(nombre: "Playa Huanchaco", direccion: "Malecón Huanchaco",
                          categoria: .playa, esFrecuente: false, colorBadge: .appPrimary)
        ]
    }
}

// MARK: - Lugar Detail Sheet
private struct LugarDetailSheet: View {
    let lugar: LugarGuardado
    var onEliminar: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0289),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )

    private var lugarCenter: CLLocationCoordinate2D {
        cameraPosition.region?.center
            ?? CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0289)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mapa preview
            Map(position: $cameraPosition) {
                Annotation(lugar.nombre, coordinate: lugarCenter) {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Image(systemName: lugar.categoria.icono)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 180)
            .clipped()

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(lugar.nombre == "UTP" ? Color.appPrimary : Color.primaryContainer.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: lugar.categoria.icono)
                            .font(.system(size: 28))
                            .foregroundStyle(lugar.nombre == "UTP" ? .white : .appPrimary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(lugar.nombre)
                                .font(.headlineMd)
                            if lugar.esFrecuente {
                                Text("FRECUENTE")
                                    .font(.labelCapsSm)
                                    .foregroundStyle(.onTertiary)
                                    .appTracking(AppTracking.wideLabel)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.tertiary))
                            }
                        }
                        Text(lugar.direccion)
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    Spacer()
                }

                Divider()

                // Botones de acción
                VStack(spacing: 10) {
                    Button {
                        router.navigate(to: .mapaPrincipal)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("Ver ruta desde mi posición")
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                        .foregroundStyle(.white)
                        .font(.bodyMdMedium)
                    }
                    .buttonStyle(.plain)

                                        Button {
                        router.navigate(to: .rutas)
                        dismiss()


                    } label: {
                        HStack {
                            Image(systemName: "bus.fill")
                            Text("Buscar transporte cercano")
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primaryContainer))
                        .foregroundStyle(.onPrimaryContainer)
                        .font(.bodyMdMedium)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onEliminar()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Eliminar de guardados")
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.errorContainer))
                        .foregroundStyle(.onErrorContainer)
                        .font(.bodyMdMedium)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

// MARK: - Linea Detail Sheet
private struct LineaDetailSheet: View {
    let linea: LineaGuardada
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.primaryContainer).frame(width: 64, height: 64)
                    Text(linea.letra)
                        .font(.displayNumberMd)
                        .foregroundStyle(.onPrimaryContainer)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(linea.nombre)
                        .font(.headlineSm)
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                        Text(linea.tiempoEstimado)
                            .font(.labelCapsMd)
                            .appTracking(AppTracking.wideLabel)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.tertiaryContainer))
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("RECORRIDO")
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(linea.recorrido)
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("PARADAS PRINCIPALES")
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                VStack(alignment: .leading, spacing: 8) {
                    paradaRow("Av. España")
                    paradaRow("Óvalo Papal")
                    paradaRow("Plaza de Armas")
                    paradaRow("UTP Trujillo")
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    router.navigate(to: .rutas)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Ver ruta completa")
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                    .foregroundStyle(.white)
                    .font(.headlineSm)
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text("Cerrar")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.onSurfaceVariant)
                        .font(.bodyMdMedium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private func paradaRow(_ nombre: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.appPrimary)
                .frame(width: 8, height: 8)
            Text(nombre)
                .font(.bodyMd)
                .foregroundStyle(.onSurface)
            Spacer()
        }
    }
}

// MARK: - Add Lugar sheet
private struct AddLugarSheet: View {
    var onSave: (LugarGuardado) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nombre: String = ""
    @State private var direccion: String = ""
    @State private var categoria: CategoriaLugar = .otro

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Guardar lugar")
                    .font(.headlineMd)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NOMBRE")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    TextField("Ej. Mi trabajo", text: $nombre)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("DIRECCIÓN")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    TextField("Ej. Av. España 123", text: $direccion)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("CATEGORÍA")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Picker("Categoría", selection: $categoria) {
                        ForEach(CategoriaLugar.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }

                Spacer()

                Button {
                    let nuevo = LugarGuardado(
                        nombre: nombre.isEmpty ? "Nuevo lugar" : nombre,
                        direccion: direccion.isEmpty ? "Sin dirección" : direccion,
                        categoria: categoria
                    )
                    onSave(nuevo)
                    dismiss()
                } label: {
                    Text("Guardar")
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }
}

#Preview {
    GuardadoView().environmentObject(AppRouter())
}
