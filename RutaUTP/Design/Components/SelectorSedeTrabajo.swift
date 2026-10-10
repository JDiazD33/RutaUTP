import SwiftUI

struct SelectorSedeTrabajo: View {
    @State private var mostrarSelector = false

    var body: some View {
        let sede = TransporteApp.sedeSeleccionada
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("MI SEDE DE TRABAJO", "MY WORKPLACE"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .accessibilityAddTraits(.isHeader)
            Text(L.t("Elige la sede que aparecerá como referencia al abrir el mapa.",
                     "Choose the workplace shown as a reference when you open the map."))
                .font(.caption)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if sede?.empresa == .utp {
                Text(L.t("UTP es la opción predeterminada. Puedes elegir otra empresa y sede cuando quieras.",
                         "UTP is the default option. You can choose another company and workplace at any time."))
                    .font(.caption)
                    .foregroundStyle(.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { mostrarSelector = true } label: {
                HStack(spacing: 12) {
                    if let empresa = sede?.empresa {
                        LogoEmpresa(empresa: empresa).frame(width: 64, height: 28)
                    } else {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(Color.appPrimary).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sede?.nombre ?? L.t("Elegir empresa y sede", "Choose company and workplace"))
                            .font(.body.weight(.medium))
                        if let sede {
                            Text(sede.direccion).font(.caption).foregroundStyle(.onSurfaceVariant)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").foregroundStyle(.onSurfaceVariant)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Mi sede de trabajo", "My workplace"))
            .accessibilityValue(sede.map { $0.nombre + ", " + $0.direccion }
                ?? L.t("Sin sede elegida", "No workplace selected"))
            .accessibilityHint(L.t("Muestra las empresas y sedes disponibles", "Shows available companies and workplaces"))
        }
        .sheet(isPresented: $mostrarSelector) {
            SedeTrabajoSheet()
                .seguirTemaForzado()
                .presentationDetents([.large])
        }
    }
}

struct SedeTrabajoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var empresa: TematicaEmpresa
    @State private var mostrarEmpresas = false
    @State private var busquedaSede = ""
    @AppStorage(PreferenciasApp.busesUTP) private var busesUTPActivos = false
    private let alVolver: (() -> Void)?
    private static let opcionesEmpresa = TematicaEmpresa.todas

    init(empresaInicial: TematicaEmpresa? = nil, alVolver: (() -> Void)? = nil) {
        let inicial = empresaInicial ?? TransporteApp.sedeSeleccionada?.empresa ?? .utp
        _empresa = State(initialValue: inicial)
        self.alVolver = alVolver
    }

    private var sedes: [SedeTrabajo] { CatalogoSedesTrabajo.sedes(de: empresa) }
    private var sedesFiltradas: [SedeTrabajo] {
        let consulta = busquedaSede.trimmingCharacters(in: .whitespacesAndNewlines)
        return sedes.filter {
            consulta.isEmpty || $0.nombre.localizedStandardContains(consulta)
                || $0.direccion.localizedStandardContains(consulta)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L.t("Elige la sede a la que perteneces. El mapa y los colores usarán esa empresa al confirmar.",
                             "Choose the workplace you belong to. The map and colors will use that company when you confirm."))
                        .font(.body)
                        .foregroundStyle(.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    if busesUTPActivos, empresa != .utp {
                        Text(L.t("Al elegir una sede volverás al transporte urbano y terminará el viaje en curso.",
                                 "Choosing a workplace returns to city transport and ends the current trip."))
                            .font(.caption).foregroundStyle(.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 12) {
                        LogoEmpresa(empresa: empresa).frame(width: 80, height: 28)
                        Text(empresa.nombre).font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    DisclosureGroup(L.t("Cambiar empresa", "Change company"), isExpanded: $mostrarEmpresas) {
                        ForEach(Self.opcionesEmpresa) { marca in
                            botonEmpresa(marca)
                        }
                    }

                    Text(L.t("SEDES EN TRUJILLO", "WORKPLACES IN TRUJILLO"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.onSurfaceVariant)
                        .accessibilityAddTraits(.isHeader)
                    if sedes.isEmpty {
                        Text(empresa == .popeyes
                             ? L.t("Próximamente. Aún no hay sedes de Popeyes disponibles para elegir en Trujillo.",
                                   "Coming soon. There are no Popeyes workplaces available to select in Trujillo yet.")
                             : L.t("No hay sedes verificadas de \(empresa.nombre) disponibles para elegir en Trujillo por ahora.",
                                   "There are no verified \(empresa.nombre) workplaces available to select in Trujillo at present."))
                            .font(.body).foregroundStyle(.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L.t("Tu referencia actual del mapa se conserva hasta que elijas una sede disponible.",
                                 "Your current map reference is kept until you choose an available workplace."))
                            .font(.caption).foregroundStyle(.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        if TematicaEmpresaStore.shared.seleccion != empresa {
                            Button(L.t("Aplicar colores de \(empresa.nombre)", "Apply \(empresa.nombre) colors")) {
                                TransporteApp.seleccionarEmpresa(empresa)
                                dismiss()
                            }
                            .font(.body.weight(.medium))
                            .frame(minHeight: 44)
                            .accessibilityHint(L.t("Aplica la temática sin asignar una sede y desactiva los buses UTP",
                                                      "Applies the theme without assigning a workplace and turns off UTP buses"))
                        }
                    } else if sedesFiltradas.isEmpty {
                        ContentUnavailableView.search(text: busquedaSede)
                    } else {
                        ForEach(sedesFiltradas) { sede in
                            fila(sede)
                        }
                    }

                    if TransporteApp.sedeSeleccionada?.empresa != .utp {
                        Button(L.t("Usar UTP como sede predeterminada", "Use UTP as the default workplace")) {
                            TransporteApp.usarSedeTrabajo(CatalogoSedesTrabajo.campusUTP)
                            dismiss()
                        }
                        .font(.body.weight(.medium))
                        .padding(.vertical, 12)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Mi sede de trabajo", "My workplace"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $busquedaSede, prompt: L.t("Buscar sede o dirección", "Search workplace or address"))
            .onChange(of: empresa) { _, _ in busquedaSede = "" }
            .toolbar {
                if let alVolver {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.t("Temáticas", "Themes"), action: alVolver)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(.appPrimary)
    }

    private func botonEmpresa(_ marca: TematicaEmpresa) -> some View {
        Button {
            empresa = marca
            mostrarEmpresas = false
        } label: {
            HStack(spacing: 12) {
                LogoEmpresa(empresa: marca).frame(width: 80, height: 24)
                Text(marca.nombre).font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if marca == .popeyes {
                    Text(L.t("Próximamente", "Coming soon"))
                        .font(.caption).foregroundStyle(.onSurfaceVariant)
                } else if marca == .utp {
                    Text(L.t("Predeterminado", "Default"))
                        .font(.caption).foregroundStyle(.onSurfaceVariant)
                } else if CatalogoSedesTrabajo.sedes(de: marca).isEmpty {
                    Text(L.t("Sin sedes verificadas", "No verified workplaces"))
                        .font(.caption).foregroundStyle(.onSurfaceVariant)
                }
                Image(systemName: empresa == marca ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(empresa == marca ? Color.appPrimary : Color.outline)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marca.nombre)
        .accessibilityValue(marca == .utp ? L.t("Predeterminado", "Default")
            : marca == .popeyes ? L.t("Próximamente", "Coming soon")
            : CatalogoSedesTrabajo.sedes(de: marca).isEmpty
                ? L.t("Sin sedes verificadas", "No verified workplaces") : "")
        .accessibilityHint(L.t("Muestra las sedes de esta empresa", "Shows this company's workplaces"))
        .accessibilityAddTraits(empresa == marca ? .isSelected : [])
    }

    private func fila(_ sede: SedeTrabajo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                TransporteApp.usarSedeTrabajo(sede)
                dismiss()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sede.nombre).font(.body.weight(.medium))
                        Text(sede.direccion).font(.caption).foregroundStyle(.onSurfaceVariant)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: TransporteApp.sedeSeleccionada?.id == sede.id ? "checkmark.circle.fill" : "mappin.circle")
                        .foregroundStyle(Color.appPrimary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sede.nombre)
            .accessibilityValue(sede.direccion)
            .accessibilityAddTraits(TransporteApp.sedeSeleccionada?.id == sede.id ? .isSelected : [])
            .accessibilityHint(L.t("Usar esta sede al abrir el mapa", "Use this workplace when opening the map"))
            if let url = sede.googleMapsURL {
                Link(L.t("Ver en Google Maps", "View in Google Maps"), destination: url)
                    .font(.caption)
                    .frame(minHeight: 44)
                    .accessibilityLabel(L.t("Ver ", "View ") + sede.nombre + L.t(" en Google Maps", " in Google Maps"))
            }
        }
        .padding(14)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
