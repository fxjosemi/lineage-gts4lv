#!/usr/bin/env bash
# Compila LineageOS 22.2 (Android 15) para gts4lv con toda nuestra
# configuracion: DAP por dispositivo, audio_effects, parches de kernel,
# Jelly fuera, Firefox y Aurora Store. Sin microG: las GApps de Google se
# flashean aparte (MindTheGapps 15.0.0-arm64) despues de la ROM.
#
#   bash scripts/build-a15.sh              # prepara + build completa (zip)
#   bash scripts/build-a15.sh bootimage    # solo boot.img
#   SKIP_PREP=1 bash scripts/build-a15.sh  # saltar prepare-a15/add-firefox
#   WITH_GMS=true bash scripts/build-a15.sh  # volver a microG (no mezclar)
#
# Log: ~/build22-live.log (nativo) + espejo en out/build22-live.log (VS Code)
set -eo pipefail

SRC="${SRC:-${HOME}/android/lineage-22}"
WS_WIN="/mnt/c/Users/xjosemi/Documents/TabS5eLTE"
WS="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-bacon}"
JOBS="${JOBS:-$(nproc)}"
LOG_NATIVE="${HOME}/build22-live.log"
LOG_WIN="${WS_WIN}/out/build22-live.log"

cd "${SRC}"

if [ "${SKIP_PREP:-0}" != "1" ]; then
    bash "${WS}/scripts/prepare-a15.sh" "${SRC}"
    bash "${WS}/scripts/add-firefox.sh" "${SRC}"
fi

# blobs de audio de Samsung (SoundAlive/MySound/DAP) que TheMuppets no trae
python3 "${WS}/scripts/port-audio-blobs.py" "${SRC}" "${A13_TREE:-${HOME}/android/lineage-20}"

export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export USE_CCACHE=1
export CCACHE_EXEC="$(command -v ccache)"
export CCACHE_DIR="${CCACHE_DIR:-${HOME}/.ccache}"
# sin microG: la ROM va limpia y las GApps (MindTheGapps) se flashean despues.
# Con WITH_GMS=true vuelve microG; ojo, no se pueden mezclar y cambiar la
# variable recompila medio arbol.
export WITH_GMS="${WITH_GMS:-false}"
export LINEAGE_BUILD=gts4lv

# Ojo con la RAM: el analisis de Soong (soong_build) pide ~27 GB residentes y 36
# virtuales, asi que siempre hay algo de swap. Soong lo lanza con `env -i`, asi que
# GOGC/GOMAXPROCS no le llegan: el limite util esta en .wslconfig
# (memory=28GB, processors=12, swap=14GB). Con swappiness bajo el kernel solo
# manda a swap lo imprescindible.
if [ -w /proc/sys/vm/swappiness ]; then
    sysctl -qw vm.swappiness=10 2>/dev/null || true
fi

: > "${LOG_NATIVE}"
mkdir -p "${WS_WIN}/out"

mirror() { while true; do sleep 15; cp -f "${LOG_NATIVE}" "${LOG_WIN}" 2>/dev/null || true; done; }
mirror &
MIRROR=$!
trap 'kill ${MIRROR} 2>/dev/null' EXIT INT TERM

echo "=== $(date '+%F %T') build ${TARGET} (gts4lv, lineage-22.2) ===" | tee -a "${LOG_NATIVE}"
source build/envsetup.sh >>"${LOG_NATIVE}" 2>&1
breakfast gts4lv >>"${LOG_NATIVE}" 2>&1
echo "=== $(date '+%F %T') mka ${TARGET} -j${JOBS} ===" | tee -a "${LOG_NATIVE}"
mka "${TARGET}" -j"${JOBS}" 2>&1 | tee -a "${LOG_NATIVE}"

echo "=== $(date '+%F %T') artefactos ===" | tee -a "${LOG_NATIVE}"
ls -lh "$OUT"/lineage-*.zip "$OUT"/boot.img "$OUT"/recovery.img "$OUT"/vbmeta.img 2>/dev/null | tee -a "${LOG_NATIVE}" || true
( cd "$OUT" && sha256sum lineage-*.zip boot.img recovery.img vbmeta.img 2>/dev/null || true ) | tee -a "${LOG_NATIVE}"
cp -f "${LOG_NATIVE}" "${LOG_WIN}" 2>/dev/null || true
