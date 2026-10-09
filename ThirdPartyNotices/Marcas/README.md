# Temáticas de empresa — fuentes de logos y colores

Referencias consultadas el **8 de octubre de 2026**. Entrega PV-05 y selector
manual PV-06 de RutaUTP. Este documento conserva la procedencia de los recursos;
queda fuera de los recursos empaquetados de la app.

## Logos utilizados

| Marca | Fuente oficial | Recurso local y tratamiento |
| --- | --- | --- |
| Interbank | [Logo publicado por Intercorp](https://www.intercorp.com.pe/img/logos/interbank.svg) | [logo.png](/Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP/RutaUTP/Assets.xcassets/Marcas/interbank-logo.imageset/logo.png). El SVG contiene un PNG blanco con transparencia de 702 × 128 px; se extrajo el PNG original por decodificación de base64, sin redibujarlo ni editar sus píxeles. |
| Popeyes | [Logo del sitio oficial de Perú](https://www.popeyes.com.pe/static/version1791283172/frontend/Ngr/popeyes/es_PE/images/logo.svg), referenciado por [popeyes.com.pe](https://www.popeyes.com.pe/) | [logo.svg](/Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP/RutaUTP/Assets.xcassets/Marcas/popeyes-logo.imageset/logo.svg). SVG original de 160 × 40, sin cambiar trazados ni colores del archivo. |
| Plaza Vea | [Logo del CDN enlazado por la tienda](https://plazavea.vteximg.com.br/arquivos/LogoPlazaVeaV2.svg?v=123), referenciado por [plazavea.com.pe](https://www.plazavea.com.pe/) | [logo.svg](/Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP/RutaUTP/Assets.xcassets/Marcas/plazavea-logo.imageset/logo.svg). SVG original de 103 × 32, sin cambiar trazados ni colores del archivo. |

Los tres imagesets declaran `template-rendering-intent: template`. El selector
utiliza también `.renderingMode(.template)` y elige **negro en modo claro y
blanco en modo oscuro**, sobre un fondo neutro. El color original del SVG queda
conservado en el archivo; la tinta monocromática corresponde a su presentación
en SwiftUI. Popeyes y Plaza Vea conservan representación vectorial.

No se descargan logos al abrir Ajustes. La muestra pequeña de color de cada
opción pertenece a la paleta; el logo continúa siendo monocromático.

### Integridad de las copias incorporadas

| Marca | Bytes | SHA-256 del archivo local |
| --- | ---: | --- |
| Interbank, PNG contenido en el SVG oficial | 6.487 | `25b5dea23b2db7753db3d32a329c9abf1fe17f81da6ab69a41ef9f8917746709` |
| Popeyes, SVG | 10.387 | `a1aa5a503adedfc278b20d9219c4f790230e1c136c125373e6955adba80ca8ef` |
| Plaza Vea, SVG | 4.298 | `e94b973b05d27189c5e39d1bf2aae9a70551a5ea25d8fcf3db2300a2a7e054ba` |

## Referencias de color

| Marca | Colores observados | Fuente y método |
| --- | --- | --- |
| Interbank | Verde `#05BE50`, azul `#0039A6` | [Interbank APP publicada por Banco Internacional del Perú en App Store](https://apps.apple.com/pe/app/interbank-app/id378649517). Se consultó la [API pública de Apple](https://itunes.apple.com/search?term=interbank&entity=software&country=pe&limit=5) y se inspeccionó el [icono PNG publicado](https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/a1/73/89/a17389ab-64a3-cb73-0304-0a496a5b1f56/AppIcon-1x_U007emarketing-0-11-0-sRGB-85-220-0.png/512x512bb.png). Son los dos colores dominantes exactos de esa imagen (207.810 y 49.225 píxeles); el icono no se incorpora a la app. |
| Popeyes | Naranja `#FF7D00`; naranja oscuro `#B54000`, marrón `#3E342F` | El naranja está en los rellenos del SVG oficial enlazado arriba. Los otros dos valores aparecen en el [CSS del sitio oficial de Perú](https://www.popeyes.com.pe/static/version1791283172/frontend/Ngr/popeyes/es_PE/css/styles-m.min.css). |
| Plaza Vea | Rojo `#CC292E`, amarillo `#FEC600`; rojo oscuro `#9D1E23` | Rojo y amarillo están en los dos trazados del SVG oficial. El rojo oscuro también aparece en el [CSS de la cabecera de su tienda oficial](https://www.plazavea.com.pe/files/ssr-header.min.css). |

Estos valores se contrastaron con recursos publicados por cada marca/grupo.
No se encontró ni se atribuye aquí un manual corporativo de paletas. Los códigos
medidos en el icono Interbank describen ese recurso, no todos sus materiales.

## Adaptación a los roles de la interfaz

La implementación completa está en
[PaletaEmpresa.swift](/Users/joaquindiaz05/Documents/RU-IOQT/RutaUTP/RutaUTP/Design/Themes/PaletaEmpresa.swift).
Los tonos de contenedores, bordes y textos claros/oscuros son adaptaciones de
la app; no se presentan como códigos oficiales de marca.

| Temática | Acento de botones | Otros roles |
| --- | --- | --- |
| Interbank | Verde derivado `#007D36`, contenedor `#00853A` | Azul de referencia `#0039A6`; tintes verdes/azules para contenedores y bordes. La muestra mantiene `#05BE50`. |
| Popeyes | Naranja oscuro observado `#B54000` | Marrón observado `#3E342F`; tintes cálidos derivados. La muestra mantiene `#FF7D00`. |
| Plaza Vea | Rojo observado `#CC292E`, contenedor `#9D1E23` | Amarillo observado `#FEC600` con texto oscuro; oro derivado `#7D6100` para roles que llevan texto blanco. |
| UTP | Valores anteriores del proyecto | Los 16 tokens trasladados conservan exactamente la paleta previa. |

Se evitaron verde/naranja/amarillo brillantes como fondo de botones con texto
blanco pequeño. Las superficies neutras, errores y colores que identifican
líneas de transporte/billeteras conservan sus responsabilidades anteriores.
La selección tiene nombre e indicador accesible además del color.

La compilación y la revisión estática no sustituyen comprobar el aspecto real,
contraste en cada contexto, VoiceOver y tamaños de texto. Esas verificaciones
en ejecución quedan pendientes, de acuerdo con la preferencia de solo compilar.
