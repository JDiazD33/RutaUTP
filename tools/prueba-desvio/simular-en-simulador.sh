#!/bin/sh
# Reproduce en el Simulador de iOS el desvío de prueba de la línea M-34 «A»:
# sale de su recorrido en Av. Nicolás de Piérola y Calle los Diamantes, va por
# calles que usa la CT-29 TA y lo retoma en Av. Gerónimo de la Torre.
#
# Uso:    tools/prueba-desvio/simular-en-simulador.sh [inicio|recorrido] [simulador]
#         inicio     deja el Simulador quieto en el punto de partida, para
#                    declarar «Estoy en un micro» en la línea M-34 «A».
#         recorrido  reproduce el viaje con el desvío (por defecto), unos
#                    5,5 minutos a 8 m/s.
#         simulador  nombre o UDID; por defecto, el que esté encendido.
# Parar:  xcrun simctl location booted clear
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"
ACCION="${1:-recorrido}"
SIMULADOR="${2:-booted}"
puntos() {
  sed -nE 's/.*<wpt lat="([-0-9.]+)" lon="([-0-9.]+)".*/\1,\2/p' desvio-M-34-A.gpx
}
case "$ACCION" in
  inicio)
    xcrun simctl location "$SIMULADOR" set "$(puntos | head -1)"
    echo "Simulador en el punto de partida. Declara «Estoy en un micro» en la M-34 «A» y luego ejecuta: $0 recorrido"
    ;;
  recorrido)
    puntos | xcrun simctl location "$SIMULADOR" start --speed=8 --interval=1 -
    echo "Recorrido en marcha (unos 5,5 minutos). Para detenerlo: xcrun simctl location $SIMULADOR clear"
    ;;
  *)
    echo "Uso: $0 [inicio|recorrido] [simulador]" >&2
    exit 64
    ;;
esac
