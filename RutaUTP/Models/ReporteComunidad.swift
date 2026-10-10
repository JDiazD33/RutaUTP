//
//  ReporteComunidad.swift
//  RutaUTP
//

import Foundation
import SwiftUI

/// Tipo de un reporte comunitario.
///
/// El `rawValue` es un IDENTIFICADOR, no texto para mostrar: ni se persiste
/// (ni este enum ni `ReporteComunidad` son `Codable`) ni se dibuja — el texto
/// visible sale de `titulo`, que sí está localizado. Por eso va sin tilde.
enum TipoReporte: String, CaseIterable, Identifiable {
    case alerta    = "ALERTA"
    case trafico   = "TRAFICO"
    case sugerencia = "SUGERENCIA"
    case otro      = "OTRO"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .alerta:     return .errorContainer
        case .trafico:    return .secondaryContainer
        case .sugerencia: return .tertiaryContainer
        case .otro:       return .surfaceContainerHigh
        }
    }

    var foreground: Color {
        switch self {
        case .alerta:     return .onErrorContainer
        case .trafico:    return .onSecondaryContainer
        case .sugerencia: return .onTertiaryContainer
        case .otro:       return .onSurfaceVariant
        }
    }
}

/// El feed conserva un rol, no una copia del Color de la primera temática.
enum EstiloAvatarReporte: Equatable {
    case primario, secundario, terciario, neutro

    var fondo: Color {
        switch self {
        case .primario: return .primaryContainer
        case .secundario: return .secondaryContainer
        case .terciario: return .tertiaryContainer
        case .neutro: return .surfaceContainerHigh
        }
    }

    var texto: Color {
        switch self {
        case .primario: return .onPrimaryContainer
        case .secundario: return .onSecondaryContainer
        case .terciario: return .onTertiaryContainer
        case .neutro: return .onSurfaceVariant
        }
    }
}

struct ReporteComunidad: Identifiable, Equatable {
    let id: UUID
    let iniciales: String
    let nombre: String
    let hace: String
    let tipo: TipoReporte
    let cuerpo: String
    let cuerpoIngles: String?
    let foto: FotoComunidad?
    let utiles: Int
    /// Conteo base de "no me gusta". El voto del usuario se suma en vivo
    /// vía `ComunidadReacciones` (no se persiste, es demo).
    let dislikes: Int
    let comentarios: Int
    let utilMarcado: Bool
    let estiloAvatar: EstiloAvatarReporte
    var avatarColor: Color { estiloAvatar.fondo }
    var avatarForeground: Color { estiloAvatar.texto }

    var cuerpoLocalizado: String { L.esIngles ? (cuerpoIngles ?? cuerpo) : cuerpo }
    var tiempoLocalizado: String {
        guard L.esIngles else { return hace }
        let translations = ["HACE 3 MIN": "3 MIN AGO", "HACE 8 MIN": "8 MIN AGO",
                            "HACE 12 MIN": "12 MIN AGO", "HACE 20 MIN": "20 MIN AGO",
                            "HACE 35 MIN": "35 MIN AGO", "HACE 1 HORA": "1 HOUR AGO",
                            "HACE 2 HORAS": "2 HOURS AGO"]
        return translations[hace] ?? hace
    }

    init(id: UUID = UUID(),
         iniciales: String,
         nombre: String,
         hace: String,
         tipo: TipoReporte,
         cuerpo: String,
         cuerpoIngles: String? = nil,
         foto: FotoComunidad? = nil,
         utiles: Int,
         dislikes: Int = 0,
         comentarios: Int,
         utilMarcado: Bool = false,
         estiloAvatar: EstiloAvatarReporte = .neutro) {
        self.id = id
        self.iniciales = iniciales
        self.nombre = nombre
        self.hace = hace
        self.tipo = tipo
        self.cuerpo = cuerpo
        self.cuerpoIngles = cuerpoIngles
        self.foto = foto
        self.utiles = utiles
        self.dislikes = dislikes
        self.comentarios = comentarios
        self.utilMarcado = utilMarcado
        self.estiloAvatar = estiloAvatar
    }
}

/// Fotos de archivo para publicaciones ficticias, con procedencia verificable.
struct FotoComunidad: Equatable {
    let asset: String
    let lugar: String
    let autor: String
    let fecha: String
    let fuente: String
    // Solo se indica una licencia cuando la fuente la declara expresamente.
    let licencia: String?
    let licenciaURL: String?
    var fechaEsPublicacion = false
    var descripcion: String = ""
    var descripcionIngles: String = ""
    var descripcionLocalizada: String { L.esIngles ? descripcionIngles : descripcion }
    var atribucion: String {
        let fechaVisible = fechaEsPublicacion ? L.t("Publicada: ", "Published: ") + fecha : fecha
        return [autor, fechaVisible, licencia].compactMap { $0 }.joined(separator: " · ")
    }

    static let pizarro = FotoComunidad(asset: "comunidad-pizarro", lugar: "Jirón Pizarro · Trujillo",
        autor: "EACC", fecha: "2012", fuente: "https://commons.wikimedia.org/wiki/File:Jir%C3%B3n_Pizarro.jpg",
        licencia: "CC BY-SA 3.0", licenciaURL: "https://creativecommons.org/licenses/by-sa/3.0/")
    static let centro = FotoComunidad(asset: "comunidad-centro", lugar: "Centro de Trujillo",
        autor: "Pitxiquin", fecha: "2017", fuente: "https://commons.wikimedia.org/wiki/File:Carrers_del_centre_de_Trujillo.jpg",
        licencia: "CC BY-SA 4.0", licenciaURL: "https://creativecommons.org/licenses/by-sa/4.0/")
    static let papal = FotoComunidad(asset: "comunidad-papal", lugar: "Óvalo Papal · Trujillo",
        autor: "Latimax", fecha: "2011", fuente: "https://commons.wikimedia.org/wiki/File:Ovalo_papal_-_Trujillo_,Per%C3%BA.jpg",
        licencia: "CC BY-SA 3.0", licenciaURL: "https://creativecommons.org/licenses/by-sa/3.0/")
}

/// Publicaciones ficticias con fotos de archivo y textos de ejemplo.
extension ReporteComunidad {
    static let publicacionesDemo: [ReporteComunidad] = {
        let nombres: [(String, String)] = [
            ("Jorge D.", "JD"), ("Maria A.", "MA"), ("Rosa C.", "RC"),
            ("Luis F.", "LF"), ("Ana P.", "AP"), ("Carlos M.", "CM"),
            ("Gabriela S.", "GS"), ("Pedro L.", "PL"), ("Fernanda R.", "FR"),
            ("Diego V.", "DV"), ("Lucía T.", "LT"), ("Marco E.", "ME"),
            ("Karla B.", "KB"), ("Renzo Q.", "RQ"), ("Valeria H.", "VH"),
            ("Oscar N.", "ON"), ("Pamela G.", "PG"), ("Julio C.", "JC"),
            ("Andrea M.", "AM"), ("Victor S.", "VS"), ("Rocío F.", "RF"),
            ("Héctor Z.", "HZ"), ("Natalia O.", "NO"), ("Iván P.", "IP"),
            ("Silvia R.", "SR"), ("Bruno A.", "BA"), ("Katia L.", "KL"),
            ("Ricardo T.", "RT"), ("Elena V.", "EV"), ("Fausto M.", "FM")
        ]
        let cuerpos: [(String, TipoReporte)] = [
            ("Micro lleno en Av. Larco. Pasaron 3 sin parar hacia la UTP.", .alerta),
            ("Demora en Óvalo Papal por obras. Considerar 10 min adicionales.", .trafico),
            ("Tomar Av. Miraflores a las 7:30 AM evita el tráfico de España.", .sugerencia),
            ("El chofer de la C-01 muy amable, esperó a una señora mayor que corría.", .otro),
            ("Cuidado con los carteristas en el paradero del Mercado Mayorista, hora punta.", .alerta),
            ("Colapso total en Av. América Sur desde las 6 PM, mejor ir por Mansiche.", .trafico),
            ("La línea C-07 va despejada sábados por la mañana, casi siempre hay asiento.", .sugerencia),
            ("Paradero frente a la UTP sin luz desde el lunes, Reporté al 105.", .alerta),
            ("Tráfico lento en Av. César Vallejo por desfile, tomar La Ribera.", .trafico),
            ("Tip: bajarse 1 cuadra antes de la UTP por Piérola ahorra 5 min de embotellamiento.", .sugerencia),
            ("Moto-taxista se pasó el semáforo en España con Mansiche. Suerte que frenó a tiempo.", .alerta),
            ("En el centro de Trujillo, revisen el paradero de su línea antes de salir los domingos.", .trafico),
            ("El micro de las 6:20 AM llega vacío al paradero de Urb. El Recreo.", .sugerencia),
            ("Se accidentó un combi cerca del Óvalo Faustino Sánchez, colapso 40 min.", .alerta),
            ("Ruta M-05 toma caminos raros para evitar tráfico, pero llega rápido.", .otro),
            ("Tarifa S/ 2.50 en la C-01 confirmado. Algunos intentan cobrar más de noche.", .alerta),
            ("Si Av. Larco está congestionada al mediodía, revisen el recorrido antes de ir al paradero.", .trafico),
            ("Los paraderos nuevos de Av. España tienen techo y cámaras, bien ahí.", .otro)
        ]
        let englishPosts = [
            "Buses are full on Av. Larco. Three passed without stopping on the way to UTP.",
            "Roadworks are causing delays at Óvalo Papal. Allow an extra 10 minutes.",
            "Taking Av. Miraflores at 7:30 AM avoids traffic on España.",
            "The C-01 driver was very kind and waited for an older woman running to the stop.",
            "Watch out for pickpockets at the Mercado Mayorista stop during rush hour.",
            "Av. América Sur is gridlocked after 6 PM. Mansiche may be a better option.",
            "The C-07 is quiet on Saturday mornings; seats are usually available.",
            "The stop across from UTP has had no lighting since Monday. I reported it to 105.",
            "A parade is slowing traffic on Av. César Vallejo. Try La Ribera.",
            "Tip: getting off one block before UTP on Piérola avoids about 5 minutes of traffic.",
            "A mototaxi ran a red light at España and Mansiche. Luckily it stopped in time.",
            "In downtown Trujillo, check your line's stop before heading out on Sundays.",
            "The 6:20 AM bus reaches the Urb. El Recreo stop nearly empty.",
            "A combi crashed near Óvalo Faustino Sánchez. Traffic has been blocked for 40 minutes.",
            "The M-05 takes unusual detours to avoid traffic, but arrives quickly.",
            "The C-01 fare is S/ 2.50. Some drivers try to charge more at night.",
            "If Av. Larco is busy at midday, check the route before heading to the stop.",
            "The new stops on Av. España have roofs and cameras. Great improvement."
        ]
        let tiempos = ["HACE 3 MIN", "HACE 8 MIN", "HACE 12 MIN", "HACE 20 MIN",
                       "HACE 35 MIN", "HACE 1 HORA", "HACE 2 HORAS"]
        let avatares: [EstiloAvatarReporte] = [
            .primario, .secundario, .terciario
        ]

        let originales = cuerpos.enumerated().map { i, par in
            let persona = nombres[i % nombres.count]
            let avatar = avatares[i % avatares.count]
            return ReporteComunidad(
                iniciales: persona.1,
                nombre: persona.0,
                hace: tiempos[(i * 3 + 1) % tiempos.count],
                tipo: par.1,
                cuerpo: par.0,
                cuerpoIngles: englishPosts[i],
                utiles: 6 + (i * 13) % 78,
                dislikes: 1 + (i * 7) % 9,
                comentarios: (i * 5) % 11,
                utilMarcado: i % 6 == 0,
                estiloAvatar: avatar
            )
        }
        var ilustrados: [(String, String, TipoReporte, FotoComunidad, String, String)] = [
            ("Andrea M.", "AM", .alerta, .centro,
             "Ojo al esperar el micro en el centro: hay vehículos junto a la vereda. Busquen un punto de subida que deje libre el paso peatonal.",
             "Take care while waiting for a bus downtown: vehicles are next to the sidewalk. Choose a boarding point that keeps pedestrian access clear."),
            ("Víctor S.", "VS", .trafico, .papal,
             "Los accesos al Óvalo Papal pueden demorar el viaje. Salgan con tiempo y revisen su línea antes de ir al paradero.",
             "The approaches to Óvalo Papal can delay your trip. Leave with time to spare and check your line before heading to the stop."),
            ("Rocío F.", "RF", .sugerencia, .pizarro,
             "Para moverme a pie por el centro prefiero el paseo Pizarro. Al buscar un micro, reviso en el mapa el paradero de subida fuera del tramo peatonal.",
             "I prefer the Pizarro pedestrian street when walking downtown. To catch a bus, I check the map for a boarding stop outside the pedestrian section."),
            ("Héctor Z.", "HZ", .otro, .papal,
             "Comparto esta referencia del Óvalo Papal para quienes recién conocen Trujillo. Confirmen el sentido de su línea antes de abordar.",
             "Sharing this reference of Óvalo Papal for newcomers to Trujillo. Check your line's direction before boarding."),
            ("Natalia O.", "NO", .alerta, .pizarro,
             "Al salir del paseo Pizarro, atentos a los cruces con calles vehiculares. Antes de seguir hacia el paradero, miren ambos lados.",
             "Watch for crossings with vehicle traffic when leaving Pizarro street. Look both ways before continuing to your stop."),
            ("Iván P.", "IP", .trafico, .centro,
             "En las calles del centro se comparte espacio con taxis y vehículos de reparto. Evitemos pedir al micro que se detenga en una esquina.",
             "Downtown streets share space with taxis and delivery vehicles. Avoid asking the bus to stop at a corner.")
        ]
        let fotosViales: [(FotoComunidad, TipoReporte, String, String)] = [
            (.cierre_centro, .alerta,
             "Si encuentras una calle cerrada en el centro de Trujillo, reporta la esquina y explica por dónde continúa tu micro.",
             "If you find a closed street in downtown Trujillo, report the junction and explain where your bus continues."),
            (.inundacion_calles, .alerta,
             "Una calle inundada puede impedir llegar al paradero. En Reportar, marca el tramo afectado y menciona si tu línea cambia de recorrido.",
             "A flooded street can block access to a stop. In Report, mark the affected section and mention whether your line changes its route."),
            (.pista_liverpool, .alerta,
             "Los huecos en la pista pueden obligar al micro a cambiar de carril. Reporta el daño con una referencia de la calle y el sentido del recorrido.",
             "Potholes can force a bus to change lanes. Report the damage with a street landmark and direction of travel."),
            (.obra_teheran, .trafico,
             "Cuando una obra deja un tramo sin pavimento, confirma tu punto de subida. Si el transporte se desvía, indica dónde comienza el cambio.",
             "When roadworks leave a section without pavement, check your boarding point. If the bus takes a detour, indicate where the change starts."),
            (.pista_salaverry, .sugerencia,
             "En Salaverry, un reporte de pavimento deteriorado será más útil si incluye la cuadra, el cruce y cómo afecta al paso del transporte.",
             "On Salaverry, a damaged-pavement report is more useful when it includes the block, junction and effect on transit."),
            (.asfalto_larco, .trafico,
             "Si hay trabajos de asfaltado en Larco, señala el carril afectado y la línea que toma otra calle. La foto es una referencia de archivo.",
             "If asphalt works affect Larco, identify the affected lane and line taking another street. This is an archive reference photo."),
            (.aniegos_trujillo, .alerta,
             "Agua junto al paradero: describe si afecta el paso peatonal o el carril del micro. Marca el punto sin acercarte al agua acumulada.",
             "Water beside a stop: describe whether it affects pedestrian access or the bus lane. Mark the location without approaching the standing water."),
            (.concreto_america, .trafico,
             "Una intersección en reparación puede cambiar el recorrido nocturno. Reporta el cruce, tu línea y la calle por la que sigue el micro.",
             "Junction repairs can change a nighttime route. Report the junction, your line and the street the bus continues along."),
            (.parcha_fatima, .sugerencia,
             "Las reparaciones pequeñas también pueden mover el punto de subida. En Fátima, toma como referencia la esquina y mantén libre el área de trabajo.",
             "Small repairs can also move the boarding point. On Fátima, use a junction as a landmark and keep the work area clear."),
            (.drenaje_trujillo, .alerta,
             "Una excavación de drenaje puede dificultar el acceso al paradero. Reporta si afecta la vereda, el carril o ambos.",
             "Drainage excavations can make a stop harder to reach. Report whether they affect the sidewalk, lane or both."),
            (.parchado_espana, .trafico,
             "Si una reparación en España obliga a cambiar de paradero, marca el tramo desde Reportar y describe dónde está parando tu transporte.",
             "If repairs on España require a different stop, mark the section in Report and describe where your bus is stopping."),
            (.reparacion_calles, .trafico,
             "El retiro de pavimento puede cerrar una cuadra por etapas. Para reportarlo, distingue entre cierre total y paso por un solo carril.",
             "Pavement removal can close a block in stages. When reporting it, distinguish between a full closure and traffic using one lane."),
            (.excavacion_larco, .alerta,
             "Si el Óvalo Larco está cerrado por una obra, señala el acceso bloqueado y la referencia del paradero alternativo que usa tu línea.",
             "If Óvalo Larco is closed for roadworks, identify the blocked approach and the alternative stop used by your line."),
            (.pavimentacion_larco, .trafico,
             "Durante el asfaltado, los accesos al óvalo pueden variar. Un reporte ayuda más si indica por dónde se está desviando el transporte.",
             "During paving, access to the roundabout may change. A report is more helpful when it explains where transit is being diverted."),
            (.maquinaria_trujillo, .trafico,
             "Material y maquinaria pueden reducir el espacio de circulación. Describe el tramo ocupado y si el micro necesita pasar por otra calle.",
             "Material and machinery can reduce road space. Describe the occupied section and whether the bus needs to use another street."),
            (.reparacion_espana, .sugerencia,
             "Una barrera temporal puede bloquear el lugar habitual de subida. Antes de abordar en España, revisa el punto y reporta el cambio si afecta tu ruta.",
             "A temporary barrier can block the usual boarding point. Before boarding on España, check the location and report a change affecting your route."),
            (.obra_san_nicolas, .trafico,
             "En una calle en obras de San Nicolás, anota la cuadra y el sentido afectado. Eso permite ubicar mejor el desvío de tu línea.",
             "On a street under repair in San Nicolás, note the block and affected direction. This helps locate your line's detour."),
            (.obra_gonzalez_prada, .trafico,
             "Conos y excavadoras pueden indicar un cierre por etapas. Si cambia tu recorrido en González Prada, reporta dónde empieza y termina el tramo.",
             "Cones and excavators may indicate a staged closure. If your route changes on González Prada, report where the affected section begins and ends."),
            (.asfalto_roma, .trafico,
             "Si hay pavimentación en Roma, verifica el acceso a tu paradero. En Reportar, indica si la línea mantiene su recorrido o toma un desvío.",
             "If paving affects Roma, check access to your stop. In Report, indicate whether the line keeps its route or takes a detour."),
            (.mantenimiento_trujillo, .sugerencia,
             "Para reportar mantenimiento de pistas en Trujillo, incluye una esquina cercana, el carril afectado y cualquier cambio de parada.",
             "To report road maintenance in Trujillo, include a nearby junction, the affected lane and any stop changes."),
        ]
        let nuevos = fotosViales.enumerated().map { index, dato in
            let persona = nombres[(index + 18) % nombres.count]
            return (persona.0, persona.1, dato.1, dato.0, dato.2, dato.3)
        }
        ilustrados.insert(contentsOf: nuevos, at: 0)

        // Intercalar fotos y textos; todas las publicaciones se pueden leer al deslizar.
        var resultado: [ReporteComunidad] = []
        var restantes = originales[...]
        for (index, dato) in ilustrados.enumerated() {
            let nuevo = ReporteComunidad(iniciales: dato.1, nombre: dato.0,
                hace: "HACE 3 MIN", tipo: dato.2, cuerpo: dato.4, cuerpoIngles: dato.5,
                foto: dato.3, utiles: 8 + index * 3, comentarios: 2,
                estiloAvatar: .secundario)
            resultado.append(nuevo)
            let grupo = restantes.prefix(1)
            resultado.append(contentsOf: grupo)
            restantes = restantes.dropFirst(grupo.count)
        }
        resultado.append(contentsOf: restantes)
        return resultado
    }()

}
