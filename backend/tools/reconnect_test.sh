#!/usr/bin/env bash
#
# Prueba de reconexión del puente (B02).
#
# Cubre el criterio de aceptación del informe:
#
#   1. Arrancar el backend con el broker APAGADO.
#   2. Encender el broker  -> debe conectarse solo.
#   3. Publicar            -> debe salir la posición vehicular.
#   4. Apagar el broker    -> el proceso debe seguir vivo.
#   5. Encenderlo de nuevo -> debe reconectar y volver a publicar.
#
# Antes, un corte dejaba el servicio desconectado para siempre y sin avisar.
#
# Requisitos: mosquitto, mosquitto_pub, mosquitto_sub y el entorno de Python.
#
# Uso:
#   ./tools/reconnect_test.sh
#   PYTHON=/ruta/al/python ./tools/reconnect_test.sh
#
set -uo pipefail

PORT="${1:-18840}"
MIN_PRINCIPALS="${BACKEND_MIN_PUBLISH_PRINCIPALS:-2}"
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
PYTHON="${PYTHON:-python3}"

WORK_DIR="$(mktemp -d)"
MOSQUITTO_PID=""
BACKEND_PID=""
FAILED=0

if ! [[ "$MIN_PRINCIPALS" =~ ^[1-9][0-9]*$ ]]; then
    echo "FALLO: BACKEND_MIN_PUBLISH_PRINCIPALS debe ser un entero >= 1" >&2
    exit 1
fi

cleanup() {
    for pid in "$BACKEND_PID" "$MOSQUITTO_PID"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done

    wait 2>/dev/null || true

    # Red de seguridad: si algo sobreviviera, se avisa y se fuerza. Dejar el
    # backend huérfano ciclando contra un broker apagado era invisible desde el
    # resultado de la prueba, que salía en verde.
    for pid in "$BACKEND_PID" "$MOSQUITTO_PID"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "AVISO: el proceso $pid sobrevivió al cierre; se fuerza" >&2
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ok()   { printf "  OK    %s\n" "$1"; }
fail() { printf "  FALLA %s\n" "$1"; FAILED=1; }

# Cuántas veces aparece `patron` en el registro del backend.
cuenta() {
    local total

    # `grep -c` ya imprime `0` cuando no encuentra coincidencias, pero devuelve
    # código 1. El antiguo `|| echo 0` añadía un segundo cero y la sustitución de
    # comandos terminaba conteniendo `0\n0`, que no es un entero válido para
    # `-gt`. Solo usamos el código de salida para tolerar el caso sin resultados.
    total="$(grep -c -- "$1" "$WORK_DIR/backend.log" 2>/dev/null)" || true

    printf '%s\n' "${total:-0}"
}

# Espera a que el registro acumule una ocurrencia MÁS de `patron` que `previas`.
#
# Sin esto la comprobación da un falso positivo: al restaurar el broker por
# segunda vez, un `grep -q` casa con la línea que ya estaba en el registro desde
# la primera reconexión, así que el test publicaba antes de que el backend
# hubiera vuelto a conectar (la espera progresiva tarda hasta 8 s) y el mensaje
# se perdía. El fallo aparecía como "no volvió a publicar", culpando al backend
# de un error del propio test.
wait_for_new() {
    local patron="$1" previas="$2" timeout="${3:-20}"

    for _ in $(seq 1 $((timeout * 2))); do
        if [ "$(cuenta "$patron")" -gt "$previas" ]; then
            return 0
        fi

        sleep 0.5
    done

    return 1
}

start_broker() {
    mosquitto -c "$WORK_DIR/mosquitto.conf" > "$WORK_DIR/mosquitto.log" 2>&1 &
    MOSQUITTO_PID=$!

    for _ in $(seq 1 40); do
        mosquitto_pub -h 127.0.0.1 -p "$PORT" -t ping -m ok 2>/dev/null && return 0
        sleep 0.25
    done

    return 1
}

stop_broker() {
    [ -n "$MOSQUITTO_PID" ] && kill "$MOSQUITTO_PID" 2>/dev/null
    wait "$MOSQUITTO_PID" 2>/dev/null
    MOSQUITTO_PID=""
    sleep 1
}

# Observación sintética sobre el recorrido real de la ruta indicada.
observacion() {
    ( cd "$BACKEND_DIR" && "$PYTHON" - "$REPO_DIR/gtfs" "$1" "$2" <<'PY'
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
    "sessionId": sys.argv[3] if len(sys.argv) > 3 else "reconexion",
    "routeId": route.route_id,
    "linea": route.linea,
    "lat": lat, "lon": lon,
    "speed": 8.0,
    "heading": segment_bearing_deg(list(route.shape), index),
    "accuracy": 8.0,
    "motionActivity": "automotive",
    "timestamp": time.time(),
}, ensure_ascii=False))
PY
    )
}

publicar() {
    local ruta="$1" sesion="$2"

    # Publica desde tantos principals distintos como exige
    # `BACKEND_MIN_PUBLISH_PRINCIPALS`. Publicar varias sesiones bajo el mismo
    # principal no cuenta: el cliente puede rotar `sessionId` a voluntad.
    #
    # Antes se publicaba una sola vez desde `reconnect-test-device`. Con el
    # quórum activo el vehículo se crea pero nunca se publica, así que esta
    # prueba fallaba siempre: el script no se actualizó cuando entró el
    # quórum, y el README seguía citando un resultado anterior a ese cambio.
    #
    # El `sessionId` del cuerpo tiene que coincidir con el del tópico, o el
    # puente descarta el mensaje por SESSION_MISMATCH.
    for indice in $(seq 1 "$MIN_PRINCIPALS"); do
        local principal="reconnect-test-device-$indice"
        mosquitto_pub -h 127.0.0.1 -p "$PORT" \
            -t "rutautp/observaciones/$principal/$sesion-$indice/posicion" \
            -q 1 -m "$(observacion "$ruta" "$sesion-$indice")"
    done
}

# Espera a que llegue una posición vehicular. Devuelve 0 si llegó.
esperar_vehiculo() {
    local timeout="$1" ruta="$2" sesion="$3"
    local salida="$WORK_DIR/vehiculo-$sesion.txt"

    # Sin `2>/dev/null`: si el suscriptor falla, hay que verlo.
    mosquitto_sub -h 127.0.0.1 -p "$PORT" -t 'rutautp/vehiculos/#' \
        -C 1 -W "$timeout" -v > "$salida" 2> "$WORK_DIR/sub-$sesion.err" &
    local sub=$!

    sleep 1
    publicar "$ruta" "$sesion"

    wait $sub 2>/dev/null

    if [ -s "$WORK_DIR/sub-$sesion.err" ]; then
        echo "      suscriptor: $(head -2 "$WORK_DIR/sub-$sesion.err")"
    fi

    grep -q 'rutautp/vehiculos/' "$salida" 2>/dev/null
}

# Volcado del registro del backend, para no tener que adivinar que paso.
volcar_registro() {
    echo ""
    echo "--- registro del backend (ultimas lineas) ---"
    tail -25 "$WORK_DIR/backend.log" 2>/dev/null | sed 's/^/  /'
    echo "--------------------------------------------"
}

cat > "$WORK_DIR/mosquitto.conf" <<EOF
listener $PORT 127.0.0.1
allow_anonymous true
persistence false
log_dest file $WORK_DIR/mosquitto.log
EOF

echo "== 1. backend arrancado SIN broker =="
(
    cd "$BACKEND_DIR"

    # `exec` sustituye la subshell por el proceso de Python: así `$!` es el PID
    # real del backend y el cierre de la prueba lo alcanza. Sin esto se mataba
    # la subshell y el hijo quedaba huérfano.
    exec env \
        MQTT_HOST=127.0.0.1 \
        MQTT_PORT="$PORT" \
        BACKEND_MIN_PUBLISH_PRINCIPALS="$MIN_PRINCIPALS" \
        BACKEND_DB_PATH= \
        BACKEND_LOG_LEVEL=INFO \
        "$PYTHON" -m rutautp_backend --plain-logs > "$WORK_DIR/backend.log" 2>&1
) &
BACKEND_PID=$!

sleep 5

if kill -0 "$BACKEND_PID" 2>/dev/null; then
    ok "el proceso sigue vivo sin broker (no muere al no poder conectar)"
else
    fail "el proceso terminó al no encontrar el broker"
    echo "--- registro ---"; cat "$WORK_DIR/backend.log"; exit 1
fi

if grep -q "sin conexión con el broker" "$WORK_DIR/backend.log"; then
    ok "avisa de la falta de conexión y reintenta"
else
    fail "no registra la falta de conexión"
fi

echo ""
echo "== 2. encender el broker =="
start_broker || { fail "el broker de prueba no arrancó"; exit 1; }

if wait_for_new "conectado; suscribiendo" 0 20; then
    ok "se conectó solo cuando el broker apareció"
else
    fail "no se conectó tras encender el broker"
fi

echo ""
echo "== 3. publicar y comprobar que sale la posición =="
if esperar_vehiculo 20 17350695 primera; then
    ok "posición vehicular publicada"
    sed 's/^/      /' "$WORK_DIR/vehiculo-primera.txt"
else
    fail "no llegó ninguna posición vehicular"
fi

echo ""
echo "== 4. cortar el broker =="
stop_broker

sleep 3

if kill -0 "$BACKEND_PID" 2>/dev/null; then
    ok "el proceso sobrevive al corte"
else
    fail "el proceso terminó al cortarse el broker"
fi

echo ""
echo "== 5. restaurar el broker y volver a publicar =="
RESTABLECIDAS="$(cuenta "conexión con el broker restablecida")"

start_broker || { fail "el broker no volvió a arrancar"; exit 1; }

# Se espera a una reconexión NUEVA, no a la que ya estaba registrada.
if wait_for_new "conexión con el broker restablecida" "$RESTABLECIDAS" 25; then
    ok "reconectó tras restaurar el broker"
else
    fail "no reconectó tras restaurar el broker"
fi

# Otra ruta: fuerza un vehículo nuevo, que se publica sin esperar al intervalo.
if esperar_vehiculo 20 17419574 segunda; then
    ok "vuelve a publicar tras la reconexión"
    sed 's/^/      /' "$WORK_DIR/vehiculo-segunda.txt"
else
    fail "no volvió a publicar tras la reconexión"
fi

echo ""
echo "--- avisos de conexión del backend ---"
grep -E "sin conexión|restablecida|conectado|reconexión fallida" "$WORK_DIR/backend.log" \
    | sed 's/^/  /' | tail -8
echo "--------------------------------------"

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "OK: el puente se recupera de arranque sin broker y de cortes posteriores"
volcar_registro
    exit 0
fi

echo ""
volcar_registro
echo "FALLO: revisar los puntos marcados arriba" >&2
exit 1
