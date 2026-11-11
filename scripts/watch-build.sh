#!/usr/bin/env bash
# Sigue en vivo el log de compilación sin cortarse.
#
#   bash scripts/watch-build.sh            # el log más reciente (A13 o A15)
#   bash scripts/watch-build.sh a15        # ~/build22-live.log  (LineageOS 22.2)
#   bash scripts/watch-build.sh a13        # ~/build-live.log    (LineageOS 20)
#   LOG=/ruta/log bash scripts/watch-build.sh
#
# - Reintenta si tail termina (p. ej. al truncarse el log entre builds)
# - Muestra una línea de estado cada 30 s (tamaño + último progreso de ninja)
set -uo pipefail

WS="/mnt/c/Users/xjosemi/Documents/TabS5eLTE/out"
A15_LOG="${HOME}/build22-live.log"
A13_LOG="${HOME}/build-live.log"

case "${1:-}" in
  a15) LOG="${LOG:-${A15_LOG}}" ;;
  a13) LOG="${LOG:-${A13_LOG}}" ;;
  *)   LOG="${LOG:-}" ;;
esac

if [ -z "${LOG}" ]; then
  LOG=$(ls -t "${A15_LOG}" "${A13_LOG}" "${WS}/build22-live.log" "${WS}/build-live.log" 2>/dev/null | head -1)
  [ -n "${LOG}" ] || LOG="${A15_LOG}"
fi

touch "${LOG}" 2>/dev/null || true

echo "==> siguiendo ${LOG}  (Ctrl+C para salir)"

ticker() {
  while true; do
    sleep 30
    local pct size last
    pct=$(grep -aoE '\[[0-9]+% [0-9]+/[0-9]+\]' "${LOG}" 2>/dev/null | tail -1)
    size=$(du -h "${LOG}" 2>/dev/null | cut -f1)
    last=$(tr '\r' '\n' < "${LOG}" 2>/dev/null | grep -av '^$' | tail -1 | cut -c1-110)
    printf '[watch %s] %s  log=%s  %s\n' "$(date +%H:%M:%S)" "${pct:-sin progreso}" "${size:-?}" "${last}"
  done
}
ticker &
TICKER=$!
trap 'kill ${TICKER} 2>/dev/null' EXIT INT TERM

while true; do
  tail -n 40 -F "${LOG}" 2>/dev/null
  echo "[watch] tail se detuvo; reintentando en 2 s..."
  sleep 2
done