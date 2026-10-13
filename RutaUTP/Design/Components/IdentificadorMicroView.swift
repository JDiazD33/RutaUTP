import SwiftUI

struct IdentificadorMicroView: View {
    let referencia: ReferenciaMicroGTFS
    var subida: ParaderoGTFS? = nil
    var bajada: ParaderoGTFS? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var revision = 0
    @State private var ficha: FichaMicroVerificada?
    @State private var referenciaFoto: FichaReferenciaMicro?
    @State private var consultaCargada: Consulta?

    private struct Consulta: Hashable {
        let referencia: ReferenciaMicroGTFS
        let subida: String?
        let bajada: String?
        let diaUTC: Int
        let revision: Int
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { contexto in
            let consulta = Consulta(referencia: referencia, subida: subida?.id, bajada: bajada?.id,
                                    diaUTC: Int(floor(contexto.date.timeIntervalSince1970 / 86_400)), revision: revision)
            let actual = consultaCargada == consulta ? ficha : nil
            let fotoActual = consultaCargada == consulta ? referenciaFoto : nil
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bus.fill")
                        .font(.title3)
                        .foregroundStyle(Color.onPrimaryContainer)
                        .frame(width: 44, height: 44)
                        .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Identifica tu micro", "Identify your bus"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(actual != nil ? L.t("Identificación verificada", "Verified identification")
                             : fotoActual != nil ? L.t("Foto de referencia", "Reference photo")
                             : L.t("Por verificar", "Not yet verified"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let actual {
                    identidadVerificada(actual)
                } else if let fotoActual {
                    fotografiaReferencia(fotoActual)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(referencia.lineaVisible).font(.title3.weight(.bold))
                        Text(referencia.empresa).font(.subheadline)
                        Label(L.t("Foto y colores pendientes", "Photo and colors pending"), systemImage: "photo")
                            .font(.footnote)
                            .foregroundStyle(Color.onSurfaceVariant)
                        Text(L.t("Referencia del GTFS. Aún no confirma la apariencia ni el cartel del micro.",
                                 "GTFS reference. It does not yet confirm the bus appearance or destination sign."))
                            .font(.caption)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let subida, let bajada {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Tu tramo planeado", "Your planned segment"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.onSurfaceVariant)
                        Text(subida.nombre + " → " + bajada.nombre)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(L.t("Confirma el destino con el conductor antes de subir.",
                         "Confirm the destination with the driver before boarding."))
                    .font(.footnote)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.onSurface)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.outlineVariant.opacity(0.25), lineWidth: 0.5)
            }
            .task(id: consulta) {
                let resultado = await CatalogoMicrosService.shared.ficha(
                    para: referencia, subida: subida?.id, bajada: bajada?.id, ahora: contexto.date)
                guard !Task.isCancelled else { return }
                let foto = resultado == nil
                    ? await CatalogoMicrosService.shared.fotoReferencia(para: referencia, ahora: contexto.date) : nil
                guard !Task.isCancelled else { return }
                ficha = resultado
                referenciaFoto = foto
                consultaCargada = consulta
            }
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { revision += 1 }
        }
    }

    private func fotografiaReferencia(_ ficha: FichaReferenciaMicro) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(referencia.lineaVisible).font(.title3.weight(.bold))
            Text(referencia.empresa).font(.subheadline)
            Image(ficha.foto, scale: 1,
                  label: Text(L.f("Foto de referencia de {0}, letra {1}", "Reference photo of {0}, letter {1}",
                                  [referencia.empresa, GTFSNombreParser.identificacionTransporte(
                                    linea: referencia.linea, variante: referencia.variante).letra])))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(L.t("Sentido y aspecto actual por confirmar.", "Direction and current appearance need confirmation."))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.onSurfaceVariant)
            Text(L.f("Foto: {0}", "Photo: {0}", [ficha.referencia.foto.credito]))
                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if let fecha = ficha.referencia.fechaFoto {
                Text(L.f("Fecha de la foto: {0}", "Photo date: {0}", [fecha]))
                    .font(.caption).foregroundStyle(Color.onSurfaceVariant)
            } else {
                Text(L.t("Fecha de la foto no indicada", "Photo date not provided"))
                    .font(.caption).foregroundStyle(Color.onSurfaceVariant)
            }
            if let url = URL(string: ficha.referencia.fuenteURL) {
                Link(destination: url) {
                    Label(L.t("Ver publicación original", "View original publication"), systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .tint(.appPrimary)
            }
        }
    }

    private func identidadVerificada(_ ficha: FichaMicroVerificada) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Text(ficha.identidad.letra)
                    .font(.largeTitle.weight(.heavy))
                    .padding(12)
                    .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(L.t("Letra del transporte: ", "Transport letter: ") + ficha.identidad.letra)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ficha.identidad.empresa).font(.headline)
                    Text(referencia.lineaVisible).font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Image(ficha.foto, scale: 1,
                  label: Text(L.f("Foto de referencia de {0}, letra {1}", "Reference photo of {0}, letter {1}",
                                  [ficha.identidad.empresa, ficha.identidad.letra])))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(L.t("Colores de la carrocería", "Body colors"))
                .font(.caption.weight(.semibold)).foregroundStyle(Color.onSurfaceVariant)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(Array(ficha.identidad.colores.enumerated()), id: \.offset) { _, color in
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: color.hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.outline, lineWidth: 0.5))
                            .accessibilityHidden(true)
                        Text(color.nombre.texto).font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Cartel de destino verificado", "Verified destination sign"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.onSurfaceVariant)
                Text(ficha.vinculo.cartelDestino).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L.t("Foto de referencia de la línea; no es una unidad en vivo.",
                     "Reference photo of the line; it is not a live vehicle."))
                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
            Text(L.f("Foto: {0}", "Photo: {0}", [ficha.identidad.foto.credito]))
                .font(.caption2).foregroundStyle(Color.onSurfaceVariant)
            DisclosureGroup(L.t("Fuente y verificación", "Source and verification")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ficha.vinculo.verificacion.fuente)
                    Text(L.f("Revisado: {0}", "Reviewed: {0}", [ficha.vinculo.verificacion.fecha]))
                    Text(L.f("Vigente hasta: {0}", "Valid until: {0}", [ficha.vinculo.verificacion.vigenteHasta]))
                }
                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            }
            .font(.footnote).tint(.appPrimary)
        }
    }
}

struct IdentificacionViajeSheet: View {
    let plan: TransitItinerary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(plan.transfer == nil ? L.t("Micro para tu viaje", "Bus for your trip")
                                              : L.t("Primer micro", "First bus"))
                        .font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                    IdentificadorMicroView(referencia: ReferenciaMicroGTFS(plan.route),
                                           subida: plan.board, bajada: plan.firstAlight)
                    if let transfer = plan.transfer {
                        Text(L.t("Segundo micro", "Second bus"))
                            .font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                        IdentificadorMicroView(referencia: ReferenciaMicroGTFS(transfer.route),
                                               subida: transfer.board, bajada: transfer.alight)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Identificar micro", "Identify bus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
        }
    }
}
