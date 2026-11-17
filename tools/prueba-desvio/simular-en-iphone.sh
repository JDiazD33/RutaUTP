#!/bin/sh
# Mueve la ubicación de un iPhone conectado por cable con el desvío de prueba
# de la línea M-34 «A», sin usar los menús de Xcode (devicectl de Xcode 26).
#
# Uso:    tools/prueba-desvio/simular-en-iphone.sh [inicio|recorrido|parar] [iphone]
#         inicio     deja el iPhone quieto en el punto de partida.
#         recorrido  reproduce el viaje con el desvío (por defecto), unos
#                    5,5 minutos a 8 m/s.
#         parar      devuelve el GPS real.
#         iphone     nombre o UDID; por defecto, el primer iPhone físico
#                    conectado.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"
ACCION="${1:-recorrido}"
IPHONE="${2:-$(xcrun devicectl list devices 2>/dev/null | grep -E ' connected .* physical' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)}"
[ -n "$IPHONE" ] || { echo "No hay un iPhone físico conectado." >&2; exit 69; }
case "$ACCION" in
  inicio)
    punto=$(sed -nE 's/.*<wpt lat="([-0-9.]+)" lon="([-0-9.]+)".*/\1 \2/p' desvio-M-34-A.gpx | head -1)
    set -- $punto
    xcrun devicectl device simulate location coordinate --device "$IPHONE" --latitude="$1" --longitude="$2"
    ;;
  recorrido)
    xcrun devicectl device simulate location route --device "$IPHONE" --route-file desvio-M-34-A.route.json
    ;;
  parar)
    xcrun devicectl device simulate location clear --device "$IPHONE"
    ;;
  *)
    echo "Uso: $0 [inicio|recorrido|parar] [iphone]" >&2
    exit 64
    ;;
esac
