#!/usr/bin/env bash
#
# Prueba de la ACL de Mosquitto con un broker REAL.
#
# `acl.example` la mencionaba desde el principio ("hay una prueba automática de
# estos permisos: tools/acl_test.sh"), pero el archivo no existía. Esto lo
# cierra: los permisos que la plantilla documenta se comprueban de verdad, no
# por lectura.
#
# Qué se comprueba
# ----------------
#   1. `device-001` PUEDE publicar bajo su propia identidad.
#   2. `device-001` NO PUEDE publicar bajo otra identidad.
#   3. La identidad compartida histórica `observer` queda bloqueada.
#   4. `device-001` NO PUEDE leer observaciones (ni las suyas): esa rama contiene
#      la trayectoria individual de cada persona a bordo.
#   5. `device-001` PUEDE leer posiciones vehiculares.
#   6. `device-001` NO PUEDE publicar posiciones vehiculares (suplantación).
#   7. La cuenta `debug` PUEDE leer todo, y solo se habilita a propósito.
#
# Cómo se mide
# ------------
# El método es siempre el mismo: se suscribe un cliente autorizado (o el mismo
# que publica) y se comprueba si el mensaje LLEGA. Así se detecta una denegación
# sin depender de códigos de salida ni de mensajes de error concretos de
# `mosquitto_pub`, que cambian entre versiones.
#
# La prueba no toca `mqtt/config/acl`: monta su propio broker en un puerto de
# prueba y su propia ACL, y la borra al terminar.
#
# Uso:
#   ./tools/acl_test.sh            # puerto 18860
#   ./tools/acl_test.sh 18861
#
set -uo pipefail

PORT="${1:-18860}"
MQTT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASSWORD="rutautp-acl-test"
WORK_DIR="$(mktemp -d)"
MOSQUITTO_PID=""
FAILED=0

cleanup() {
    [ -n "$MOSQUITTO_PID" ] && kill "$MOSQUITTO_PID" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for tool in mosquitto mosquitto_pub mosquitto_sub mosquitto_passwd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FALTA: $tool (brew install mosquitto)" >&2
        exit 1
    fi
done

# ── Broker de prueba con la ACL de la plantilla ───────────────────────────
cp "$MQTT_DIR/config/acl.example" "$WORK_DIR/acl"

# La cuenta de depuración está comentada en la plantilla a propósito: no se
# distribuye con la app. Aquí se habilita solo dentro del directorio temporal,
# para poder comprobar que el permiso que documenta funciona de verdad.
cat >> "$WORK_DIR/acl" <<'EOF'

user debug
topic read rutautp/#
EOF

mosquitto_passwd -c -b "$WORK_DIR/passwords" device-001 "$PASSWORD" >/dev/null 2>&1
mosquitto_passwd -b "$WORK_DIR/passwords" observer "$PASSWORD" >/dev/null 2>&1
mosquitto_passwd -b "$WORK_DIR/passwords" backend "$PASSWORD" >/dev/null 2>&1
mosquitto_passwd -b "$WORK_DIR/passwords" debug "$PASSWORD" >/dev/null 2>&1

cat > "$WORK_DIR/mosquitto.conf" <<EOF
listener $PORT 127.0.0.1
allow_anonymous false
password_file $WORK_DIR/passwords
acl_file $WORK_DIR/acl
persistence false
log_dest file $WORK_DIR/mosquitto.log
EOF

mosquitto -c "$WORK_DIR/mosquitto.conf" &
MOSQUITTO_PID=$!

for _ in $(seq 1 40); do
    mosquitto_pub -h 127.0.0.1 -p "$PORT" \
        -u device-001 -P "$PASSWORD" \
        -t rutautp/observaciones/device-001/ping/posicion \
        -m ok >/dev/null 2>&1 && break
    sleep 0.25
done

# ── Comprobaciones ────────────────────────────────────────────────────────

ok()   { printf "  OK    %s\n" "$1"; }
fail() { printf "  FALLA %s\n" "$1"; FAILED=1; }

# check <descripcion> <usuario_suscribe> <filtro> <usuario_publica> <topico> <si|no>
check() {
    local desc="$1" subuser="$2" subtopic="$3" pubuser="$4" pubtopic="$5"
    local expect="$6"

    local out="$WORK_DIR/probe.txt"
    : > "$out"

    mosquitto_sub -h 127.0.0.1 -p "$PORT" \
        -u "$subuser" -P "$PASSWORD" \
        -t "$subtopic" -C 1 -W 3 -v > "$out" 2>/dev/null &
    local sub=$!

    sleep 0.8

    mosquitto_pub -h 127.0.0.1 -p "$PORT" \
        -u "$pubuser" -P "$PASSWORD" \
        -t "$pubtopic" -m "acl-probe" -q 1 >/dev/null 2>&1 || true

    wait "$sub" 2>/dev/null || true

    local got="no"
    [ -s "$out" ] && got="si"

    if [ "$got" = "$expect" ]; then
        ok "$desc"
    else
        fail "$desc (llegó: $got, se esperaba: $expect)"
    fi
}

echo "== ACL de RutaUTP contra un broker real (puerto $PORT) =="
echo ""

check "device-001 PUEDE publicar bajo su identidad" \
    backend "rutautp/observaciones/device-001/probe/posicion" \
    device-001 "rutautp/observaciones/device-001/probe/posicion" \
    si

check "device-001 NO PUEDE publicar bajo otra identidad" \
    backend "rutautp/observaciones/device-002/probe/posicion" \
    device-001 "rutautp/observaciones/device-002/probe/posicion" \
    no

check "observer compartido queda bloqueado" \
    backend "rutautp/observaciones/observer/probe/posicion" \
    observer "rutautp/observaciones/observer/probe/posicion" \
    no

check "device-001 NO PUEDE leer observaciones" \
    device-001 "rutautp/observaciones/device-001/probe/posicion" \
    device-001 "rutautp/observaciones/device-001/probe/posicion" \
    no

check "device-001 PUEDE leer posiciones vehiculares" \
    device-001 "rutautp/vehiculos/probe/posicion" \
    backend "rutautp/vehiculos/probe/posicion" \
    si

check "device-001 NO PUEDE publicar posiciones vehiculares" \
    device-001 "rutautp/vehiculos/probe/posicion" \
    device-001 "rutautp/vehiculos/probe/posicion" \
    no

check "debug PUEDE leer observaciones (cuenta de diagnóstico)" \
    debug "rutautp/observaciones/device-001/probe/posicion" \
    device-001 "rutautp/observaciones/device-001/probe/posicion" \
    si

echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "OK: la ACL aplica los permisos que documenta acl.example"
    exit 0
fi

echo "FALLO: revisar los permisos marcados arriba" >&2
exit 1
