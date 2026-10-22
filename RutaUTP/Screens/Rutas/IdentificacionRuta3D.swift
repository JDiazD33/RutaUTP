import SwiftUI

enum ColorTransporteReferencia: String {
    case verde, verdeAgua, verdeClaro, verdeOscuro, turquesa, blanco, negro, azul, azulOscuro, azulRey, amarillo, rojo, rosado, fucsia, guinda, naranja, marron, marronOscuro, crema, marfil, gris, plomo, verdeLima, celeste, morado

    var color: Color {
        switch self {
        case .verde: return Color(hex: "#27B579")
        case .verdeAgua: return Color(hex: "#5AAFA0")
        case .verdeClaro: return Color(hex: "#91CB7C")
        case .verdeOscuro: return Color(hex: "#195A52")
        case .verdeLima: return Color(hex: "#86BE39")
        case .turquesa: return Color(hex: "#4DB5B0")
        case .blanco: return Color(hex: "#F4F4F4")
        case .negro: return Color(hex: "#1C1F21")
        case .azul: return Color(hex: "#187FB8")
        case .celeste: return Color(hex: "#6DC9E0")
        case .azulOscuro: return Color(hex: "#1E304D")
        case .azulRey: return Color(hex: "#2D4FAA")
        case .amarillo: return Color(hex: "#F5C928")
        case .rojo: return Color(hex: "#DE3039")
        case .rosado: return Color(hex: "#E6A0B8")
        case .fucsia: return Color(hex: "#C13E83")
        case .guinda: return Color(hex: "#7E304A")
        case .morado: return Color(hex: "#884680")
        case .naranja: return Color(hex: "#D3913E")
        case .marron: return Color(hex: "#956B4B")
        case .marronOscuro: return Color(hex: "#4D322F")
        case .crema: return Color(hex: "#EADDBB")
        case .marfil: return Color(hex: "#F0E4C2")
        case .gris: return Color(hex: "#979795")
        case .plomo: return Color(hex: "#6F7477")
        }
    }

    var nombre: String {
        switch self {
        case .verde: return L.t("Verde", "Green")
        case .verdeAgua: return L.t("Verde agua", "Mint green")
        case .verdeClaro: return L.t("Verde claro", "Light green")
        case .verdeOscuro: return L.t("Verde oscuro", "Dark green")
        case .verdeLima: return L.t("Verde lima", "Lime green")
        case .turquesa: return L.t("Turquesa", "Turquoise")
        case .blanco: return L.t("Blanco", "White")
        case .negro: return L.t("Negro", "Black")
        case .azul: return L.t("Azul", "Blue")
        case .celeste: return L.t("Celeste", "Light blue")
        case .azulOscuro: return L.t("Azul oscuro", "Dark blue")
        case .azulRey: return L.t("Azul rey", "Royal blue")
        case .amarillo: return L.t("Amarillo", "Yellow")
        case .rojo: return L.t("Rojo", "Red")
        case .rosado: return L.t("Rosado", "Pink")
        case .fucsia: return L.t("Fucsia", "Fuchsia")
        case .guinda: return L.t("Guinda", "Burgundy")
        case .morado: return L.t("Morado", "Purple")
        case .naranja: return L.t("Naranja", "Orange")
        case .marron: return L.t("Marrón", "Brown")
        case .marronOscuro: return L.t("Marrón oscuro", "Dark brown")
        case .crema: return L.t("Crema", "Cream")
        case .marfil: return L.t("Marfil", "Ivory")
        case .gris: return L.t("Gris", "Gray")
        case .plomo: return L.t("Plomo", "Lead gray")
        }
    }
}

/// Paletas de referencias visuales o descripciones; no certifican toda la flota.
struct ColoresTransporteReferencia {
    let linea: String
    let letra: String
    let empresa: String
    let colores: [ColorTransporteReferencia]
    let fuente: URL?
    let modelo: TipoTransporte3D?
    let esOrientativa: Bool

    init(linea: String, letra: String, empresa: String, colores: [ColorTransporteReferencia],
         fuente: URL?, modelo: TipoTransporte3D? = nil, esOrientativa: Bool = false) {
        self.linea = linea
        self.letra = letra
        self.empresa = empresa
        self.colores = colores
        self.fuente = fuente
        self.modelo = modelo
        self.esOrientativa = esOrientativa
    }
}

struct IdentificacionRuta3D {
    let routeID: String
    let codigo: String
    let letra: String
    let empresa: String
    let colores: ColoresTransporteReferencia?

    init(ruta: RutaOpcion) {
        let identificacion = GTFSNombreParser.identificacionTransporte(linea: ruta.linea, variante: ruta.variante)
        routeID = ruta.id
        codigo = identificacion.codigo
        letra = identificacion.letra
        empresa = ruta.empresa
        let referencia = Self.referencias[ruta.id]
        // El mismo "A" existe en varias empresas. Nunca enlazar solo por letra.
        if let referencia, referencia.linea == identificacion.codigo,
           referencia.letra == identificacion.letra, referencia.empresa == ruta.empresa {
            colores = referencia
        } else {
            colores = nil
        }
    }

    /// Modelos esquematicos por categoria del catalogo urbano, no por route_type 3.
    var tipoModelo: TipoTransporte3D? {
        guard !routeID.hasPrefix("utp:") else { return nil }
        // La referencia ya comprobo ID, codigo, letra y empresa en el inicializador.
        if let modelo = colores?.modelo { return modelo }
        // El Excel asigna el minibus de Miramar a esta referencia concreta.
        // La otra T2 conserva su referencia de combi; no se generaliza a la flota.
        if routeID == "17522705", codigo == "C-44",
           letra == "T2", empresa == "Miramar" { return .micro }
        if codigo.hasPrefix("M-") { return .micro }
        if codigo.hasPrefix("C-") { return .combi }
        return nil
    }
    var claveModelo: String { [routeID, codigo, letra, empresa].joined(separator: "|") }

    var letraPrincipal: String { distintivoLetra == nil ? letra : "C2" }

    // La variante verificada lleva C2 y un VR pequeno; su identidad sigue siendo C2VR.
    var distintivoLetra: String? {
        guard routeID == "17554634", codigo == "M-15",
              letra == "C2VR", empresa == "El Cortijo" else { return nil }
        return "VR"
    }

    // Fotografias, publicaciones y descripciones aportadas por el usuario.
    // Los tonos son aproximaciones visuales. No se reutilizan fotos ni graficos.
    // Las variantes con corazon quedan separadas y no heredan una foto de la base.
    private static let referencias: [String: ColoresTransporteReferencia] = [
        // Primeras tres filas del Excel. La foto de Huanchaco muestra H con corazon.
        "17522670": .init(linea: "M-01", letra: "A", empresa: "California",
                           colores: [.verdeAgua, .blanco],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122155313780117228/")),
        "17527405": .init(linea: "M-02", letra: "C", empresa: "California",
                           colores: [.verdeAgua, .blanco],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/617378354147208/")),
        "17550302": .init(linea: "M-05", letra: "H ♥", empresa: "Huanchaco",
                           colores: [.rojo, .amarillo, .blanco],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122158210784117228/")),
        // Segundo lote del Excel, con una foto propia para cada linea.
        "17551463": .init(linea: "M-06", letra: "B", empresa: "Huanchaco",
                           colores: [.amarillo, .rojo],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/858004373417937/")),
        "17554401": .init(linea: "M-08", letra: "A", empresa: "Nuevo California",
                           colores: [.verde, .blanco],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122153598188117228/")),
        "17554410": .init(linea: "M-09", letra: "BC", empresa: "Nuevo California",
                           colores: [.verdeAgua, .blanco],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122155274684117228/")),
        // Tercer lote del Excel, con referencias separadas para C1 y C2.
        "17554571": .init(linea: "M-10", letra: "B1", empresa: "Nuevo California",
                           colores: [.verdeAgua, .blanco],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/769200352298340/")),
        "17554576": .init(linea: "M-13", letra: "C1", empresa: "El Cortijo",
                           colores: [.blanco, .amarillo, .rojo],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/1086688363882869/")),
        "17554620": .init(linea: "M-15", letra: "C2", empresa: "El Cortijo",
                           colores: [.blanco, .amarillo, .rojo],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/734366072448435/")),
        // Cuarto lote del Excel: C2VR no hereda la referencia de C2.
        "17554634": .init(linea: "M-15", letra: "C2VR", empresa: "El Cortijo",
                           colores: [.blanco, .amarillo, .rojo],
                           fuente: URL(string: "https://www.facebook.com/photo/?fbid=122163725132117228&set=a.122103536606117228")),
        "17554640": .init(linea: "M-17", letra: "C2", empresa: "La Libertad",
                           colores: [.turquesa, .blanco, .verdeOscuro],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/858002120084829/")),
        "17554644": .init(linea: "M-18", letra: "C1", empresa: "La Libertad",
                           colores: [.turquesa, .blanco, .verdeOscuro],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/photos/per%C3%BA-trujillo-trujillo-en-ruta-por-la-av-espa%C3%B1a-se-visualiza-uno-de-los-dos-nuev/958140823404291/")),
        "17554645": .init(linea: "M-19", letra: "A", empresa: "La Libertad",
                           colores: [.blanco, .turquesa, .verdeOscuro],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122167443062117228/")),
        // Sexto lote del Excel, con una referencia propia por ruta.
        "17554649": .init(linea: "M-31", letra: "A", empresa: "Señor de los Milagros",
                           colores: [.fucsia, .blanco, .guinda],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122178411368117228/")),
        "17554667": .init(linea: "M-32", letra: "A1", empresa: "Señor de los Milagros",
                           colores: [.blanco, .fucsia, .guinda],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122154363692117228/")),
        "17554683": .init(linea: "M-33", letra: "B", empresa: "Esperanza Express",
                           colores: [.blanco, .rojo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122154365306117228/")),
        // Septimo lote del Excel; los corazones se comprueban en cada foto.
        "17521284": .init(linea: "M-33", letra: "B ♥", empresa: "Esperanza Express",
                           colores: [.rojo, .blanco, .azulOscuro],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122175218060117228/")),
        "17434457": .init(linea: "M-34", letra: "A", empresa: "Esperanza Express",
                           colores: [.rojo, .blanco, .azulOscuro],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/573321755219535/")),
        "17554691": .init(linea: "M-34", letra: "A ♥", empresa: "Esperanza Express",
                           colores: [.blanco, .rojo, .azulOscuro],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122174545508117228/")),
        // Octavo lote del Excel; D y D con corazon tienen fuentes separadas.
        "17581560": .init(linea: "M-35", letra: "D", empresa: "El Icaro",
                           colores: [.rojo, .blanco, .rosado],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/483386054213106/")),
        "17612564": .init(linea: "M-35", letra: "D ♥", empresa: "El Icaro",
                           colores: [.blanco, .rojo, .rosado],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122169372704117228/")),
        "17554694": .init(linea: "M-36", letra: "LV", empresa: "Nuevo California",
                           colores: [.verde, .blanco],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122159317292117228/")),
        // Noveno lote del Excel. La K usa la foto local aportada por el usuario.
        "17492018": .init(linea: "C-05", letra: "B1", empresa: "Moderno Girasoles",
                           colores: [.blanco, .amarillo, .rojo],
                           fuente: URL(string: "https://www.etmogesa.com/")),
        "17419574": .init(linea: "C-06", letra: "K", empresa: "Titanic Express",
                           colores: [.blanco, .azulRey], fuente: nil),
        "17434307": .init(linea: "C-07", letra: "Z1", empresa: "Titanic Express",
                           colores: [.blanco, .azulRey],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122142345380117228/")),
        // Decimo lote del Excel. La D de Nuevo Diamante sigue sin foto verificada.
        "17434313": .init(linea: "C-09", letra: "E", empresa: "Arco Iris Express",
                           colores: [.blanco, .azulOscuro, .rojo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122158205408117228/")),
        "17508499": .init(linea: "C-11", letra: "T1", empresa: "San Isidro Labrador",
                           colores: [.rojo, .amarillo, .blanco],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122164671182117228/")),
        // Undecimo lote del Excel. I y P comparten colores segun las notas del usuario.
        // La publicacion dice C-16 P; los codigos y letras se conservan segun GTFS.
        "17463348": .init(linea: "C-14", letra: "S", empresa: "Sol y Luna",
                           colores: [.blanco, .naranja, .marronOscuro],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122161072670117228/")),
        "17508507": .init(linea: "C-16", letra: "I", empresa: "Virgen del Arco",
                           colores: [.blanco, .rojo, .amarillo, .gris],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122156427338117228/")),
        "17520994": .init(linea: "C-18", letra: "P", empresa: "Virgen del Arco",
                           colores: [.blanco, .rojo, .amarillo, .gris],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122156427338117228/")),
        // Duodecimo lote: el usuario asigna la foto de carroceria de la M a ambas UI.
        // La R usa su propia foto local, sin incluirla como recurso de la app.
        "17434332": .init(linea: "C-20", letra: "UI", empresa: "Luz Divina",
                           colores: [.blanco, .verdeOscuro, .verde, .verdeLima],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122164350842117228/")),
        "17463362": .init(linea: "C-20", letra: "UI", empresa: "Luz Divina",
                           colores: [.blanco, .verdeOscuro, .verde, .verdeLima],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122164350842117228/")),
        "17463369": .init(linea: "C-21", letra: "R", empresa: "Luz Divina",
                           colores: [.blanco, .verdeOscuro, .verde, .verdeLima], fuente: nil),
        // Decimotercer lote del Excel: fotos locales propias para M y S1.
        // La referencia de Santa Catalina muestra H; el usuario la asigna a H1.
        "17521119": .init(linea: "C-22", letra: "M", empresa: "Luz Divina",
                           colores: [.blanco, .verdeOscuro, .verde, .verdeLima],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122164350842117228/")),
        "17520880": .init(linea: "C-23", letra: "S1", empresa: "Santa Catalina",
                           colores: [.azulOscuro, .blanco, .amarillo], fuente: nil),
        "17521008": .init(linea: "C-24", letra: "H1", empresa: "Santa Catalina",
                           colores: [.azulOscuro, .blanco, .amarillo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122140662668117228/")),
        // Fila 47: el usuario confirma los colores de H1, conservando la letra H2.
        "17521004": .init(linea: "C-24", letra: "H2", empresa: "Santa Catalina",
                           colores: [.azulOscuro, .blanco, .amarillo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122140662668117228/")),
        // Fila 48: la foto local muestra C-27 B con carroceria blanca y negra.
        "17521112": .init(linea: "C-27", letra: "B", empresa: "Caballito de Totora",
                           colores: [.blanco, .negro], fuente: nil),
        // Decimosexto lote del Excel, con una referencia propia por ruta.
        // La foto de C muestra uno de sus minibuses; solo se toma su paleta.
        "17521114": .init(linea: "C-28", letra: "C", empresa: "Caballito de Totora",
                           colores: [.blanco, .azul, .celeste, .azulOscuro],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/1003574282194278/")),
        "17521145": .init(linea: "C-35", letra: "S3", empresa: "Señor de la Misericordia",
                           colores: [.blanco, .morado], fuente: nil),
        "17521283": .init(linea: "C-38", letra: "S4", empresa: "Corazon de Jesus",
                           colores: [.blanco, .azul, .rojo, .negro], fuente: nil),
        // Decimoseptimo lote: publicaciones propias de Z2, B2 y A.
        // El capo de B2 identifica Los Girasoles Service; se conserva el nombre GTFS.
        "17612352": .init(linea: "C-41", letra: "Z2", empresa: "Arco Iris Express",
                           colores: [.blanco, .azulOscuro, .rojo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122160449456117228/")),
        "17522621": .init(linea: "C-42", letra: "B2", empresa: "Los Girasoles",
                           colores: [.blanco, .amarillo, .naranja],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122161714856117228/")),
        "17612420": .init(linea: "C-43", letra: "A", empresa: "Los Diamantes",
                           colores: [.blanco, .verdeOscuro, .rojo, .fucsia],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122160482732117228/")),
        // Decimoctavo lote: cada T2 tiene su propia foto de micro o combi.
        // CT-01 A conserva su estado pendiente hasta su propio lote.
        "17522705": .init(linea: "C-44", letra: "T2", empresa: "Miramar",
                           colores: [.azul, .blanco, .rojo],
                           fuente: URL(string: "https://www.facebook.com/bcurbanofficial/posts/638387222046321/")),
        "17522730": .init(linea: "C-44", letra: "T2", empresa: "Miramar",
                           colores: [.azul, .blanco, .rojo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122163245618117228/")),
        // Primer lote de colores CT verificados en web.
        "17573616": .init(linea: "CT-02", letra: "A", empresa: "Larco Express S.A.",
                           colores: [.verde, .blanco],
                           fuente: URL(string: "https://seguridadciudadanadetrujillo.blogspot.com/2016/03/"),
                           modelo: .colectivo),
        // Vigesimo lote: automoviles colectivos segun las fuentes de su categoria.
        // Las referencias sin enlace mantienen las paletas orientativas del Excel.
        "17581709": .init(linea: "CT-05", letra: "V-A", empresa: "COVISA S.A.C.",
                           colores: [.blanco, .verde, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17669816": .init(linea: "CT-06", letra: "V-A", empresa: "Nuestra Señora de Guadalupe S.A.",
                           colores: [.blanco, .verde, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17669832": .init(linea: "CT-07", letra: "V-A", empresa: "Serv. e industria Vista Alegre S.A.",
                           colores: [.blanco, .verde, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Vigesimoprimer lote: AM y A mantienen sus letras y empresas del GTFS.
        // Descripciones de Gemini: Huracan lleva azul y rojo, no verde y azul.
        "17595670": .init(linea: "CT-08", letra: "AM", empresa: "Turismo Dios es mi guia S.R.L.",
                           colores: [.blanco, .verde, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581512": .init(linea: "CT-09", letra: "A", empresa: "Serv. Generales nuevo Gran Chimu",
                           colores: [.blanco, .verde, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581515": .init(linea: "CT-10", letra: "A", empresa: "Huracan S.A.C.",
                           colores: [.blanco, .azul, .rojo],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Vigesimosegundo lote: paletas principales de cada descripcion de Gemini.
        // Los tonos alternativos de B y SL quedan anotados en el Excel por confirmar.
        "17595839": .init(linea: "CT-10", letra: "B", empresa: "Huracan S.A.C.",
                           colores: [.blanco, .azul, .rojo],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17595870": .init(linea: "CT-11", letra: "E", empresa: "Rio Seco S.A.",
                           colores: [.rojo, .marfil],
                           fuente: URL(string: "https://es.scribd.com/document/920471306/CONTRATO-DE-USO-Y-AFECTACION-DE-SERVICIOS-DE-RECORRIDO"),
                           modelo: .colectivo),
        "17595748": .init(linea: "CT-12", letra: "SL", empresa: "Los Halcones S.A.",
                           colores: [.blanco, .naranja, .negro],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Vigesimotercer lote: colores orientativos de las descripciones de Gemini.
        // SL de Los Pinos no hereda la paleta de SL de Los Halcones.
        "17595746": .init(linea: "CT-14", letra: "SL", empresa: "Turismo y serv. Los Pinos S.A.C.",
                           colores: [.blanco, .verdeClaro, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17580756": .init(linea: "CT-15", letra: "A", empresa: "Alfa y Omega S.A.C.",
                           colores: [.blanco, .celeste, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17605269": .init(linea: "CT-16", letra: "F", empresa: "Hermelinda Express S.R.L.",
                           colores: [.blanco, .verdeClaro, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Vigesimocuarto lote: paletas de Gemini, sin foto verificada.
        // Las dos H y la F se enlazan solo a su ID y empresa del GTFS.
        "17670295": .init(linea: "CT-17", letra: "H", empresa: "Nueva Hermelinda S.A.C.",
                           colores: [.blanco, .verdeClaro, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17580790": .init(linea: "CT-19", letra: "H", empresa: "Serv. Generales Lider Express S.A.",
                           colores: [.blanco, .amarillo, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581631": .init(linea: "CT-21", letra: "F", empresa: "N° 1 Florencia Express S.A.",
                           colores: [.blanco, .marron, .crema],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Vigesimoquinto lote: cada letra de San Pedro del Amor mantiene su propio ID.
        // El rojo esta verificado a nivel empresa; la fuente no separa unidades A, B, C y D.
        "17669993": .init(linea: "CT-22", letra: "A", empresa: "San Pedro del Amor S.A.",
                           colores: [.rojo],
                           fuente: URL(string: "https://seguridadciudadanadetrujillo.blogspot.com/2016/05/auxiliado-un-motociclista-lesionado-en.html"),
                           modelo: .colectivo),
        "17581635": .init(linea: "CT-22", letra: "B", empresa: "San Pedro del Amor S.A.",
                           colores: [.rojo],
                           fuente: URL(string: "https://seguridadciudadanadetrujillo.blogspot.com/2016/05/auxiliado-un-motociclista-lesionado-en.html"),
                           modelo: .colectivo),
        "17581639": .init(linea: "CT-22", letra: "C", empresa: "San Pedro del Amor S.A.",
                           colores: [.rojo],
                           fuente: URL(string: "https://seguridadciudadanadetrujillo.blogspot.com/2016/05/auxiliado-un-motociclista-lesionado-en.html"),
                           modelo: .colectivo),
        // Vigesimosexto lote: D completa las variantes verificadas de CT-22.
        "17581646": .init(linea: "CT-22", letra: "D", empresa: "San Pedro del Amor S.A.",
                           colores: [.rojo],
                           fuente: URL(string: "https://seguridadciudadanadetrujillo.blogspot.com/2016/05/auxiliado-un-motociclista-lesionado-en.html"),
                           modelo: .colectivo),
        // Moderno Express usa la evidencia web como referencia para A, AC, B y BC.
        // La fuente verifica plomo con verde en una unidad, sin separar variantes.
        "17549691": .init(linea: "CT-23", letra: "A", empresa: "Serv. Multiples Moderno Express S.A.",
                           colores: [.plomo, .verde],
                           fuente: URL(string: "https://enfoquesperu.com/un-hombre-que-habia-sufrido-un-infarto-fallecio-pese-al-auxilio-de-los-agentes-de-seguridad-ciudadana-de-trujillo/"),
                           modelo: .colectivo),
        "17527168": .init(linea: "CT-23", letra: "AC", empresa: "Serv. Multiples Moderno Express S.A.",
                           colores: [.plomo, .verde],
                           fuente: URL(string: "https://enfoquesperu.com/un-hombre-que-habia-sufrido-un-infarto-fallecio-pese-al-auxilio-de-los-agentes-de-seguridad-ciudadana-de-trujillo/"),
                           modelo: .colectivo),
        // Vigesimoseptimo lote: B y BC conservan la empresa del GTFS, no el alias Girasoles.
        "17549744": .init(linea: "CT-23", letra: "B", empresa: "Serv. Multiples Moderno Express S.A.",
                           colores: [.plomo, .verde],
                           fuente: URL(string: "https://enfoquesperu.com/un-hombre-que-habia-sufrido-un-infarto-fallecio-pese-al-auxilio-de-los-agentes-de-seguridad-ciudadana-de-trujillo/"),
                           modelo: .colectivo),
        "17527200": .init(linea: "CT-23", letra: "BC", empresa: "Serv. Multiples Moderno Express S.A.",
                           colores: [.plomo, .verde],
                           fuente: URL(string: "https://enfoquesperu.com/un-hombre-que-habia-sufrido-un-infarto-fallecio-pese-al-auxilio-de-los-agentes-de-seguridad-ciudadana-de-trujillo/"),
                           modelo: .colectivo),
        // Esperanza Tours: negro documentado en una unidad, sin distinguir A, AU o B.
        "17527270": .init(linea: "CT-24", letra: "A", empresa: "Esperanza Tours S.R.L.",
                           colores: [.negro],
                           fuente: URL(string: "https://seguridadciudadanadetrujillo.blogspot.com/2017/12/socorrida-mujer-lesionada-tras-ser.html"),
                           modelo: .colectivo),
        // Vigesimooctavo lote: AU, B y A mantienen su propio ID y empresa del GTFS.
        // Las tres paletas proceden de las descripciones de Gemini, sin foto verificada.
        "17670129": .init(linea: "CT-24", letra: "AU", empresa: "Esperanza Tours S.R.L.",
                           colores: [.blanco, .naranja, .negro],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17527397": .init(linea: "CT-24", letra: "B", empresa: "Esperanza Tours S.R.L.",
                           colores: [.blanco, .naranja, .negro],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17670001": .init(linea: "CT-25", letra: "A", empresa: "Emp. Transp. Wichanzao S.A.",
                           colores: [.blanco, .celeste, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Vigesimonoveno lote: B de Wichanzao y A/AU de Horizonte tienen referencias propias.
        // Las tres paletas son orientativas, segun sus descripciones de Gemini sin foto.
        "17670087": .init(linea: "CT-25", letra: "B", empresa: "Emp. Transp. Wichanzao S.A.",
                           colores: [.blanco, .celeste, .azul],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17670006": .init(linea: "CT-26", letra: "A", empresa: "Empresa de Transportes Horizonte Ecologico S.A.",
                           colores: [.blanco, .verdeClaro, .marron],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581730": .init(linea: "CT-26", letra: "AU", empresa: "Empresa de Transportes Horizonte Ecologico S.A.",
                           colores: [.blanco, .verdeClaro, .marron],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Trigesimo lote: B y BU de Horizonte y L de Jose Emilio tienen referencias propias.
        // Las tres paletas son orientativas, segun sus descripciones de Gemini sin foto.
        "17670089": .init(linea: "CT-26", letra: "B", empresa: "Empresa de Transportes Horizonte Ecologico S.A.",
                           colores: [.blanco, .verdeClaro, .marron],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581473": .init(linea: "CT-26", letra: "BU", empresa: "Empresa de Transportes Horizonte Ecologico S.A.",
                           colores: [.blanco, .verdeClaro, .marron],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581475": .init(linea: "CT-27", letra: "L", empresa: "Jose Emilio Lefebvre S.A.",
                           colores: [.blanco, .verdeClaro, .naranja],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        // Ultimas dos filas: el directorio registra estos operadores como auto colectivos.
        // Se usa sedan de referencia y solo los colores orientativos de las notas de Gemini.
        "17581474": .init(linea: "CT-28", letra: "T.S.", empresa: "Serv. Generales Salaverry S.R.L.",
                           colores: [.blanco, .azulOscuro, .rojo],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17581510": .init(linea: "CT-29", letra: "TA", empresa: "Amigos Unidos S.A.C.",
                           colores: [.blanco, .verdeOscuro, .naranja],
                           fuente: nil, modelo: .colectivo, esOrientativa: true),
        "17434299": .init(linea: "M-07", letra: "V", empresa: "Nuevo California",
                           colores: [.verde, .blanco],
                           fuente: URL(string: "https://onibusbrasil.com/MiguelBusologoTrujillo/14432887")),
        "17522721": .init(linea: "M-05", letra: "H", empresa: "Huanchaco",
                           colores: [.amarillo, .rojo, .blanco],
                           fuente: URL(string: "https://onibusbrasil.com/MiguelBusologoTrujillo/14487628")),
        "17554572": .init(linea: "M-12", letra: "C", empresa: "Nuevo California",
                           colores: [.verde, .blanco], fuente: nil),
        // La publicacion describe expresamente los buses azules A, C y F.
        "17434314": .init(linea: "M-21", letra: "A", empresa: "Salaverry Express",
                           colores: [.azul, .blanco], fuente: fuenteSalaverry),
        "17434472": .init(linea: "M-20", letra: "C", empresa: "Salaverry Express",
                           colores: [.azul], fuente: fuenteSalaverry),
        "17434330": .init(linea: "M-22", letra: "F", empresa: "Salaverry Express",
                           colores: [.azul], fuente: fuenteSalaverry),
        // Referencias fotograficas por route_id; no se transfieren a variantes.
        "17350695": .init(linea: "C-01", letra: "B", empresa: "Nuevos Girasoles",
                           colores: [.verde, .blanco, .rojo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122142360590117228/")),
        "17491518": .init(linea: "C-03", letra: "JJ", empresa: "Nuevos Girasoles",
                           colores: [.verde, .blanco, .rojo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122140658732117228/")),
        "17434339": .init(linea: "C-11", letra: "T1", empresa: "San Isidro Labrador",
                           colores: [.rojo, .amarillo, .azul],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122166200408117228/")),
        "17463346": .init(linea: "C-10", letra: "M", empresa: "Mochica Chimu",
                           colores: [.azul, .blanco, .amarillo],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122161071242117228/")),
        "17463385": .init(linea: "C-22", letra: "M", empresa: "Luz Divina",
                           colores: [.blanco, .verde],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122161713404117228/")),
        "17508289": .init(linea: "C-12", letra: "B", empresa: "Santa Lucia de Moche",
                           colores: [.blanco, .rojo, .verde],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122156437472117228/")),
        "17508501": .init(linea: "C-13", letra: "D", empresa: "Mochica",
                           colores: [.blanco, .rojo, .verde, .azul],
                           fuente: URL(string: "https://www.facebook.com/61553516860919/posts/122160478976117228/")),
        // Foto aportada en el chat: C-25 S2 de El Aguila, no la Z1 de Titanic.
        "17521009": .init(linea: "C-25", letra: "S2", empresa: "El Aguila",
                           colores: [.blanco, .azul], fuente: nil)
    ]

    private static let fuenteSalaverry = URL(string: "https://trujilloexperiencefreewt.blogspot.com/p/como-llegar-puerto-salaverry.html")
}

/// Micros, combis y colectivos comparten controles, con su propia geometria.
struct IdentificacionRuta3DView: View {
    let identificacion: IdentificacionRuta3D
    var activo = true
    @State private var ampliar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L.t("Reconoce tu transporte", "Recognize your vehicle"))
                    .font(.headlineSm)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if identificacion.tipoModelo != nil {
                    Button { ampliar = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimary)
                    .accessibilityLabel(L.t("Ampliar modelo 3D", "Expand 3D model"))
                }
            }
            datos
            if let tipo = identificacion.tipoModelo {
                PanelTransporte3D(tipo: tipo, identificacion: identificacion, activo: activo && !ampliar)
                    .id(identificacion.claveModelo)
            } else {
                Label(L.t("Modelo de esta categoría próximamente", "Model for this category coming soon"), systemImage: "cube.transparent")
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .padding(.vertical, 12)
            }
        }
        .foregroundStyle(Color.onSurface)
        .padding(16)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("ruta.identificacion3d")
        .sheet(isPresented: $ampliar) {
            Transportes3DView(identificacion: identificacion)
        }
    }

    private var datos: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 2) {
                    Text(L.t("Letra", "Letter"))
                        .font(.caption)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(identificacion.letraPrincipal.isEmpty ? "—" : identificacion.letraPrincipal)
                        if let distintivo = identificacion.distintivoLetra {
                            Text(distintivo)
                                .font(.system(size: 14, weight: .black, design: .rounded))
                        }
                    }
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(identificacion.letra.isEmpty ? "—" : identificacion.letra))
                }
                .foregroundStyle(Color.onPrimaryContainer)
                .frame(width: 88, height: 78)
                .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(identificacion.codigo).font(.headlineSm)
                    Text(identificacion.empresa)
                        .font(.bodySm)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            ColoresReferenciaRutaView(referencia: identificacion.colores)
        }
    }
}

struct ColoresReferenciaRutaView: View {
    let referencia: ColoresTransporteReferencia?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let referencia {
                Text(L.t("Colores de referencia", "Reference colors"))
                    .font(.bodySm.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { muestras(referencia) }
                    VStack(alignment: .leading, spacing: 8) { muestras(referencia) }
                }
                Text(referencia.esOrientativa
                     ? L.t("Colores orientativos, pendientes de confirmar.", "Indicative colors, awaiting confirmation.")
                     : L.t("Los colores pueden variar entre unidades.", "Colors may vary between vehicles."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                if let fuente = referencia.fuente {
                    Link(L.t("Ver fuente", "View source"), destination: fuente)
                        .font(.bodySm)
                        .foregroundStyle(Color.appPrimary)
                        .frame(minHeight: 44)
                }
            } else {
                Label(L.t("Color por confirmar", "Color to be confirmed"), systemImage: "paintpalette")
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
    }

    @ViewBuilder
    private func muestras(_ referencia: ColoresTransporteReferencia) -> some View {
        ForEach(referencia.colores, id: \.rawValue) { color in
            HStack(spacing: 6) {
                Circle()
                    .fill(color.color)
                    .overlay(Circle().stroke(Color.outline, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(color.nombre).font(.bodySm)
            }
        }
    }
}
