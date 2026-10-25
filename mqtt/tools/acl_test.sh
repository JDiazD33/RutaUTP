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
mosquitto_passwd -b "$WORK_DIR/passwords" sim-001 "$PASSWORD" >/dev/null 2>&1
mosquitto_passwd -b "$WORK_DIR/passwords" sim-002 "$PASSWORD" >/dev/null 2>&1

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

check "app PUEDE enviar cambios bajo su identidad" \
    backend "rutautp/cambios/device-001/reporte" \
    device-001 "rutautp/cambios/device-001/reporte" si

check "app NO PUEDE suplantar otra cuenta en cambios" \
    backend "rutautp/cambios/device-002/reporte" \
    device-001 "rutautp/cambios/device-002/reporte" no

check "app PUEDE leer alertas confirmadas del backend" \
    device-001 "rutautp/cambios/estado" \
    backend "rutautp/cambios/estado" si

check "app NO PUEDE publicar alertas confirmadas" \
    device-001 "rutautp/cambios/estado" \
    device-001 "rutautp/cambios/estado" no

check "app PUEDE leer su recibo" \
    device-001 "rutautp/cambios/device-001/recibo" \
    backend "rutautp/cambios/device-001/recibo" si

check "app NO PUEDE leer recibos ajenos" \
    device-001 "rutautp/cambios/device-002/recibo" \
    backend "rutautp/cambios/device-002/recibo" no

check "app NO PUEDE leer reportes individuales" \
    device-001 "rutautp/cambios/device-001/reporte" \
    device-001 "rutautp/cambios/device-001/reporte" no

check "app PUEDE reportar ocupación propia" \
    backend "rutautp/ocupacion/device-001/reporte" \
    device-001 "rutautp/ocupacion/device-001/reporte" si

check "app NO PUEDE suplantar votos de ocupación" \
    backend "rutautp/ocupacion/device-002/reporte" \
    device-001 "rutautp/ocupacion/device-002/reporte" no

check "app PUEDE consultar ocupación confirmada" \
    device-001 "rutautp/ocupacion/estado" \
    backend "rutautp/ocupacion/estado" si

check "app NO PUEDE inventar ocupación confirmada" \
    device-001 "rutautp/ocupacion/estado" \
    device-001 "rutautp/ocupacion/estado" no

check "app PUEDE leer su recibo de ocupación" \
    device-001 "rutautp/ocupacion/device-001/recibo" \
    backend "rutautp/ocupacion/device-001/recibo" si

check "app NO PUEDE leer recibos de ocupación ajenos" \
    device-001 "rutautp/ocupacion/device-002/recibo" \
    backend "rutautp/ocupacion/device-002/recibo" no

check "app NO PUEDE leer votos individuales" \
    device-001 "rutautp/ocupacion/device-001/reporte" \
    device-001 "rutautp/ocupacion/device-001/reporte" no

check "app PUEDE registrar sus avisos" \
    backend "rutautp/notificaciones/device-001/registro" \
    device-001 "rutautp/notificaciones/device-001/registro" si

check "app NO PUEDE registrar avisos de otra cuenta" \
    backend "rutautp/notificaciones/device-002/registro" \
    device-001 "rutautp/notificaciones/device-002/registro" no

check "app NO PUEDE leer registros con tokens" \
    device-001 "rutautp/notificaciones/device-001/registro" \
    device-001 "rutautp/notificaciones/device-001/registro" no

check "backend PUEDE enviar el recibo privado" \
    device-001 "rutautp/notificaciones/device-001/recibo" \
    backend "rutautp/notificaciones/device-001/recibo" si

check "app NO PUEDE leer recibos de otra cuenta" \
    device-001 "rutautp/notificaciones/device-002/recibo" \
    backend "rutautp/notificaciones/device-002/recibo" no

check "app NO PUEDE falsificar recibos" \
    device-001 "rutautp/notificaciones/device-001/recibo" \
    device-001 "rutautp/notificaciones/device-001/recibo" no

# S03: aislamiento entre roles, sin usar cuentas ni broker del despliegue.
SIM_TOPIC="rutautp/simulacion/5bdb08e8-e971-4a9e-a18e-47f359841321/observaciones/sim-001/c58e47f5-7a2b-44d3-b657-e794b54c19ae/posicion"
check "sim PUEDE enviar su observación sintética al backend" \
    backend "$SIM_TOPIC" sim-001 "$SIM_TOPIC" si
check "app NO PUEDE escribir en rama sintética" \
    backend "$SIM_TOPIC" device-001 "$SIM_TOPIC" no
check "sim NO PUEDE suplantar otro actor" \
    backend "$SIM_TOPIC" sim-002 "$SIM_TOPIC" no
check "sim NO PUEDE escribir en rama habitual" \
    backend "rutautp/observaciones/sim-001/probe/posicion" \
    sim-001 "rutautp/observaciones/sim-001/probe/posicion" no
check "sim NO PUEDE publicar vehículos" \
    device-001 "rutautp/vehiculos/probe/posicion" \
    sim-001 "rutautp/vehiculos/probe/posicion" no
check "sim NO PUEDE publicar control" \
    device-001 "rutautp/simulacion/estado" sim-001 "rutautp/simulacion/estado" no
check "sim PUEDE leer el control del backend" \
    sim-001 "rutautp/simulacion/estado" backend "rutautp/simulacion/estado" si
check "app PUEDE leer el control del backend" \
    device-001 "rutautp/simulacion/estado" backend "rutautp/simulacion/estado" si
check "app NO PUEDE publicar control" \
    device-001 "rutautp/simulacion/estado" device-001 "rutautp/simulacion/estado" no
check "sim NO PUEDE votar ocupación" \
    backend "rutautp/ocupacion/sim-001/reporte" sim-001 "rutautp/ocupacion/sim-001/reporte" no
check "sim NO PUEDE reportar cambios" \
    backend "rutautp/cambios/sim-001/reporte" sim-001 "rutautp/cambios/sim-001/reporte" no
check "sim NO PUEDE registrar avisos" \
    backend "rutautp/notificaciones/sim-001/registro" sim-001 "rutautp/notificaciones/sim-001/registro" no
check "sim NO PUEDE leer posiciones" \
    sim-001 "rutautp/vehiculos/probe/posicion" backend "rutautp/vehiculos/probe/posicion" no
check "sim NO PUEDE leer observaciones sintéticas" \
    sim-001 "$SIM_TOPIC" sim-001 "$SIM_TOPIC" no

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
