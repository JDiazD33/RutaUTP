#!/usr/bin/env bash
#
# Prueba de humo de extremo a extremo del puente.
#
# Levanta un Mosquitto local en un puerto de prueba, arranca el backend contra
# él, publica una observación sintética construida sobre el recorrido real de
# una línea y comprueba que aparece la posición vehicular correspondiente.
#
# Es la única comprobación que cubre el cableado con el broker: las pruebas
# unitarias usan un publicador inyectado y nunca abren un socket.
#
# Requisitos: mosquitto, mosquitto_pub, mosquitto_sub y el entorno de Python
# del backend.
#
# Uso:
#   ./tools/smoke_test.sh                    # puerto 18830 por defecto
#   ./tools/smoke_test.sh 18831
#   PYTHON=/ruta/al/python ./tools/smoke_test.sh
#
set -euo pipefail

PORT="${1:-18830}"
RUTA="${RUTA:-17350695}"

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
PYTHON="${PYTHON:-python3}"

WORK_DIR="$(mktemp -d)"
MOSQUITTO_PID=""
BACKEND_PID=""
SUB_PID=""

cleanup() {
    for pid in "$SUB_PID" "$BACKEND_PID" "$MOSQUITTO_PID"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done

    wait 2>/dev/null || true

    # Red de seguridad: si algo sobreviviera, se avisa y se fuerza.
    #
    # Dejar un proceso vivo no es hipotético: el backend se quedaba huérfano
    # ciclando contra un broker ya apagado, y no había forma de enterarse desde
    # el resultado de la prueba, que salía en verde.
    for pid in "$SUB_PID" "$BACKEND_PID" "$MOSQUITTO_PID"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "AVISO: el proceso $pid sobrevivió al cierre; se fuerza" >&2
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for tool in mosquitto mosquitto_pub mosquitto_sub; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FALTA: $tool (brew install mosquitto)" >&2
        exit 1
    fi
done

echo "== 1. broker de prueba en el puerto $PORT =="
cat > "$WORK_DIR/mosquitto.conf" <<EOF
listener $PORT 127.0.0.1
allow_anonymous true
persistence false
log_dest file $WORK_DIR/mosquitto.log
EOF

mosquitto -c "$WORK_DIR/mosquitto.conf" &
MOSQUITTO_PID=$!

for _ in $(seq 1 40); do
    if mosquitto_pub -h 127.0.0.1 -p "$PORT" -t ping -m ok 2>/dev/null; then
        break
    fi
    sleep 0.25
done

echo "== 2. backend suscrito =="
(
    cd "$BACKEND_DIR"

    # `exec` sustituye la subshell por el proceso de Python, así que `$!` pasa a
    # ser el PID real del backend y el cierre de la prueba lo alcanza. Sin esto
    # se mataba la subshell y el hijo sobrevivía ciclando contra un broker ya
    # apagado, sin que el resultado de la prueba lo delatara.
    exec env \
        MQTT_HOST=127.0.0.1 \
        MQTT_PORT="$PORT" \
        MQTT_USERNAME="" \
        MQTT_PASSWORD="" \
        BACKEND_LOG_LEVEL=INFO \
        "$PYTHON" -m rutautp_backend --plain-logs > "$WORK_DIR/backend.log" 2>&1
) &
BACKEND_PID=$!

echo "== 3. observador de vehiculos/# =="
mosquitto_sub -h 127.0.0.1 -p "$PORT" -t 'rutautp/vehiculos/#' -C 1 -W 25 -v \
    > "$WORK_DIR/vehicle.txt" 2>/dev/null &
SUB_PID=$!

sleep 2

echo "== 4. observación sintética sobre la ruta $RUTA =="
OBSERVATION="$(
    cd "$BACKEND_DIR" && "$PYTHON" - "$REPO_DIR/gtfs" "$RUTA" <<'PY'
import json, sys, time
from pathlib import Path

from rutautp_backend.geo import segment_bearing_deg
from rutautp_backend.gtfs import load_feed

feed = load_feed(Path(sys.argv[1]))
route = feed.get(sys.argv[2])

if route is None:
    raise SystemExit(f"la ruta {sys.argv[2]} no está en el feed")

index = len(route.shape) // 2
lat, lon = route.shape[index]

print(json.dumps({
    "schemaVersion": 1,
    "sessionId": "smoke-test-session",
    "routeId": route.route_id,
    "linea": route.linea,
    "lat": lat,
    "lon": lon,
    "speed": 8.0,
    "heading": segment_bearing_deg(list(route.shape), index),
    "accuracy": 8.0,
    "motionActivity": "automotive",
    "timestamp": time.time(),
}, ensure_ascii=False))
PY
)"

echo "   $OBSERVATION"
mosquitto_pub -h 127.0.0.1 -p "$PORT" \
    -t "rutautp/observaciones/smoke-test-session/posicion" \
    -q 1 -m "$OBSERVATION"

echo "== 5. esperando la posición vehicular =="
wait "$SUB_PID" 2>/dev/null || true
SUB_PID=""

echo ""
echo "---- vehiculos/ recibido ----"
cat "$WORK_DIR/vehicle.txt" || true
echo "-----------------------------"
echo ""
echo "---- resumen del backend ----"
grep -E "vehículo|resumen|feed cargado|conectado" "$WORK_DIR/backend.log" | tail -10 || true
echo "-----------------------------"

if grep -q "rutautp/vehiculos/" "$WORK_DIR/vehicle.txt" 2>/dev/null; then
    echo ""
    echo "OK: el puente publicó una posición vehicular"
    exit 0
fi

echo ""
echo "FALLO: no llegó ninguna posición vehicular a vehiculos/#" >&2
exit 1
