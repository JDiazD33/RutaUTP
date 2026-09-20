#!/usr/bin/env bash
#
# Comprueba que la app y el backend deriven la MISMA `linea` de cada ruta.
#
# Por qué existe
# --------------
# El backend rechaza una observación con LINE_MISMATCH si la `linea` que
# declara el cliente no coincide con la que él calcula del feed:
#
#     if claimed_line != route.linea:  -> LINE_MISMATCH
#
# La app obtiene esa `linea` con `GTFSNombreParser.lineaYVariante`
# (GTFSModels.swift) y el backend con `parse_short_name` (gtfs.py), que se
# documenta como su port. Si las dos implementaciones se separan, el fallo no
# es parcial: **todas** las observaciones de esa línea se descartan, el vehículo
# nunca aparece en el mapa y no hay ningún error visible en la app.
#
# Ninguna prueba lo cubría. `tests/test_contract.py` compara los dos structs de
# payload, y `tests/test_topics.py` los filtros de tópicos, pero nadie ejecutaba
# los dos parsers de nombres sobre el feed real. Esto lo hace: compila el
# `GTFSNombreParser` de verdad y lo contrasta ruta a ruta con el del backend.
#
# Requisitos: un toolchain de Swift (Xcode) y el entorno de Python del backend.
#
# Uso:
#   ./tools/parity_linea.sh
#   PYTHON=/ruta/al/python ./tools/parity_linea.sh
#
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
PYTHON="${PYTHON:-python3}"
SWIFT_MODELS="$REPO_DIR/RutaUTP/Services/GTFS/GTFSModels.swift"

if [ ! -f "$SWIFT_MODELS" ]; then
    echo "FALLO: no se encontró $SWIFT_MODELS" >&2
    echo "La comprobación no se salta: sin el parser de la app no comprueba nada." >&2
    exit 1
fi

SWIFTC=""
if [ -n "${DEVELOPER_DIR:-}" ] && [ -x "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
    SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
elif command -v swiftc >/dev/null 2>&1; then
    SWIFTC="$(command -v swiftc)"
fi

if [ -z "$SWIFTC" ]; then
    echo "FALLO: no hay swiftc. Hace falta Xcode para compilar el parser de la app." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

echo "== 1. exportando route_id y route_short_name del feed =="
"$PYTHON" - "$REPO_DIR/gtfs" "$WORK_DIR/routes.tsv" <<'PY'
import csv, sys
from pathlib import Path

gtfs_dir, destino = Path(sys.argv[1]), sys.argv[2]

with (gtfs_dir / "routes.txt").open(encoding="utf-8-sig", newline="") as fh:
    filas = list(csv.DictReader(fh))

with open(destino, "w", encoding="utf-8") as out:
    for fila in filas:
        out.write(f"{fila['route_id']}\t{fila['route_short_name']}\n")

print(f"   {len(filas)} rutas")
PY

echo "== 2. compilando el GTFSNombreParser real de la app =="
cat > "$WORK_DIR/main.swift" <<'SWIFT'
import Foundation

// Usa el parser REAL: GTFSModels.swift se compila junto a este archivo.
let texto = try! String(
    contentsOfFile: CommandLine.arguments[1], encoding: .utf8
)

for lineaFichero in texto.split(separator: "\n", omittingEmptySubsequences: true) {
    let campos = lineaFichero
        .split(separator: "\t", omittingEmptySubsequences: false)
        .map(String.init)

    guard campos.count == 2 else { continue }

    let (linea, variante) = GTFSNombreParser.lineaYVariante(shortName: campos[1])

    print("\(campos[0])\t\(linea)\t\(variante)")
}
SWIFT

SDK=""
if [ -n "${DEVELOPER_DIR:-}" ]; then
    SDK="$(ls -d "$DEVELOPER_DIR"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk 2>/dev/null | head -1 || true)"
fi

if [ -n "$SDK" ]; then
    "$SWIFTC" -O -sdk "$SDK" -o "$WORK_DIR/parity" \
        "$SWIFT_MODELS" "$WORK_DIR/main.swift" >/dev/null 2>&1
else
    "$SWIFTC" -O -o "$WORK_DIR/parity" \
        "$SWIFT_MODELS" "$WORK_DIR/main.swift" >/dev/null 2>&1
fi

"$WORK_DIR/parity" "$WORK_DIR/routes.tsv" > "$WORK_DIR/swift.tsv"
echo "   $(wc -l < "$WORK_DIR/swift.tsv" | tr -d ' ') rutas parseadas por la app"

echo "== 3. comparando con parse_short_name del backend =="
cd "$BACKEND_DIR"
"$PYTHON" - "$REPO_DIR/gtfs" "$WORK_DIR/swift.tsv" <<'PY'
import csv, sys
from pathlib import Path

from rutautp_backend.gtfs import parse_short_name

gtfs_dir, swift_tsv = Path(sys.argv[1]), Path(sys.argv[2])

app = {}
for linea in swift_tsv.read_text(encoding="utf-8").splitlines():
    partes = linea.split("\t")
    if len(partes) == 3:
        app[partes[0]] = (partes[1], partes[2])

with (gtfs_dir / "routes.txt").open(encoding="utf-8-sig", newline="") as fh:
    filas = list(csv.DictReader(fh))

discrepancias = []
vacias = []

for fila in filas:
    route_id = fila["route_id"]
    corto = fila["route_short_name"]

    if route_id not in app:
        discrepancias.append(f"{route_id}: la app no lo parseó")
        continue

    backend = parse_short_name(corto)

    if backend != app[route_id]:
        discrepancias.append(
            f"{route_id} ({corto!r}): backend={backend} app={app[route_id]}"
        )

    if not app[route_id][0]:
        vacias.append(f"{route_id} ({corto!r})")

print(f"   rutas comparadas: {len(filas)}")

if vacias:
    print(f"   AVISO: {len(vacias)} rutas con línea vacía: {', '.join(vacias[:5])}")

if discrepancias:
    print(f"\nFALLO: {len(discrepancias)} discrepancia(s) entre app y backend:", file=sys.stderr)
    for d in discrepancias[:20]:
        print(f"   {d}", file=sys.stderr)
    print(
        "\nCon una discrepancia, el backend descarta TODAS las observaciones de "
        "esa línea con LINE_MISMATCH y el vehículo no llega a aparecer.",
        file=sys.stderr,
    )
    raise SystemExit(1)

print("\nOK: la app y el backend derivan la misma línea en todas las rutas")
PY
