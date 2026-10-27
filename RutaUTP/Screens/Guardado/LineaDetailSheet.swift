//
//  LineaDetailSheet.swift
//  RutaUTP
//
//  Hoja de detalle de una línea GTFS real.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Linea Detail Sheet (línea GTFS real)
struct LineaDetailSheet: View {
    let linea: RutaOpcion
    var onExplorar: () -> Void
    var onQuitar: () -> Bool
    @State private var errorAlQuitar = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.self) private var entorno
    @ScaledMetric(relativeTo: .title) private var tamanoInsignia = 76

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    resumen
                    datosDelViaje
                    paraderos
                    quitarDeGuardados
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("Línea guardada", "Saved line"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .tint(acento)
                    .accessibilityLabel(L.t("Cerrar", "Close"))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                verRecorrido
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .alert(L.t("No se pudo quitar la línea", "Unable to remove line"), isPresented: $errorAlQuitar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Reintenta su lectura desde Guardado.",
                     "The original data has been preserved. Retry reading it from Saved."))
        }
    }

    private var resumen: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                insignia

                VStack(alignment: .leading, spacing: 5) {
                    Text(linea.empresa)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .accessibilityAddTraits(.isHeader)
                    Text(L.t("Línea ", "Line ") + linea.lineaConLetra)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(linea.recorridoLocalizado)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    tituloFrecuencia
                    Spacer(minLength: 8)
                    valorFrecuencia
                }
                VStack(alignment: .leading, spacing: 6) {
                    tituloFrecuencia
                    valorFrecuencia
                }
            }
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var insignia: some View {
        VStack(spacing: 2) {
            if linea.letraTransporte.isEmpty {
                Image(systemName: "bus.fill")
                    .font(.title)
            } else {
                Text(L.t("Letra", "Letter"))
                    .font(.caption2.weight(.medium))
                Text(linea.letraTransporte)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(colorTextoLetra)
        .padding(8)
        .frame(width: tamanoInsignia, height: tamanoInsignia)
        .background(linea.colorLinea, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
    }

    private var colorTextoLetra: Color {
        let color = linea.colorLinea.resolve(in: entorno)
        let luminancia = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        let contrasteNegro = (luminancia + 0.05) / 0.05
        let contrasteBlanco = 1.05 / (luminancia + 0.05)
        return contrasteNegro >= contrasteBlanco ? .black : .white
    }

    private var tituloFrecuencia: some View {
        Label(L.t("Frecuencia", "Frequency"), systemImage: "clock")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valorFrecuencia: some View {
        Text(linea.frecuenciaTexto)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.onSurface)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var datosDelViaje: some View {
        LazyVGrid(columns: columnasDatos, alignment: .leading, spacing: 20) {
            datosLinea
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var columnasDatos: [GridItem] {
        let cantidad = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), alignment: .leading), count: cantidad)
    }

    @ViewBuilder
    private var datosLinea: some View {
        dato(icono: "clock", valor: linea.tiempoTexto, etiqueta: L.t("Tiempo de viaje", "Travel time"))
        dato(icono: "banknote", valor: linea.costo, etiqueta: L.t("Pasaje", "Fare"))
        dato(icono: "mappin", valor: "\(linea.numParaderos)", etiqueta: L.t("Paraderos", "Stops"))
        dato(icono: "point.topleft.down.curvedto.point.bottomright.up",
             valor: FormatoNumero.decimal(linea.distanciaKm) + " km", etiqueta: L.t("Distancia", "Distance"))
    }

    private func dato(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(etiqueta, systemImage: icono)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(valor)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var paraderos: some View {
        VStack(spacing: 0) {
            paradero(icono: "circle.circle", titulo: L.t("Paradero inicial", "First stop"),
                     nombre: linea.paradaInicioVisible)
            Divider().padding(.leading, 68)
            paradero(icono: "flag.checkered", titulo: L.t("Paradero final", "Last stop"),
                     nombre: linea.paradaFinVisible)
        }
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func paradero(icono: String, titulo: String, nombre: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono)
                .font(.body.weight(.medium))
                .foregroundStyle(acento)
                .frame(minWidth: 36, minHeight: 36)
                .background(Color.surfaceContainerLow, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(titulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nombre)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.onSurface)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var quitarDeGuardados: some View {
        Button(role: .destructive) {
            if onQuitar() { dismiss() } else { errorAlQuitar = true }
        } label: {
            Label(L.t("Quitar de guardados", "Remove from saved"), systemImage: "trash")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: 52)
                .background(superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(uiColor: .systemRed))
    }

    private var verRecorrido: some View {
        Button {
            onExplorar()
        } label: {
            Label(L.t("Ver recorrido en el mapa", "View route on map"), systemImage: "map")
                .font(.headline)
                .foregroundStyle(Color.onPrimaryFill)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
