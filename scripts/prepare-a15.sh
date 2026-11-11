#!/usr/bin/env bash
# Prepara un arbol LineageOS 22.2 (Android 15) con nuestro trabajo de A13.
#
#   bash scripts/prepare-a15.sh [ruta-del-arbol]     # por defecto ~/android/lineage-22
#
# No sincroniza ni compila: da por hecho que el arbol ya existe con el
# manifiesto local_manifests/gts4lv-22.xml aplicado. Es idempotente.
set -euo pipefail

SRC="${1:-$HOME/android/lineage-22}"
WS="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$SRC/.repo" ]; then
    echo "no parece un arbol repo: $SRC" >&2
    exit 1
fi

say() { printf '\n== %s\n' "$*"; }

say "comprobando ramas"
for d in device/samsung/gts4lv-common device/samsung/gts4lv \
         kernel/samsung/sdm670 hardware/samsung \
         vendor/samsung/gts4lv-common vendor/samsung/gts4lv; do
    if [ ! -d "$SRC/$d" ]; then
        echo "falta $d (revisa el manifiesto y repo sync)" >&2
        exit 1
    fi
done

say "app DAP (hardware/samsung)"
if [ -f "$SRC/hardware/samsung/dap/src/org/lineageos/dap/DeviceState.kt" ]; then
    echo "ya aplicada"
else
    git -C "$SRC/hardware/samsung" apply -3 \
        "$WS/patches/hardware-samsung-22/0001-dap-port-completo-a-LineageOS-22.2-Android-15.patch"
    echo "parche aplicado"
fi

say "audio_effects.xml (declaraciones Samsung, sin sa3d)"
cp "$WS/patches/devicetree-22/audio_effects.xml" \
   "$SRC/device/samsung/gts4lv-common/audio/configs/audio_effects.xml"
echo "copiado"

say "kernel (HZ 300, zram lz4, CPU_BOOST, sin DEBUG_INFO)"
for p in "$WS"/patches/kernel/000*.patch; do
    if git -C "$SRC/kernel/samsung/sdm670" apply --check "$p" 2>/dev/null; then
        git -C "$SRC/kernel/samsung/sdm670" apply "$p"
        echo "aplicado $(basename "$p")"
    else
        echo "NO aplica limpio: $(basename "$p")  -> revisar a mano"
    fi
done

say "device tree: afinado medido (stune, GPU, read_ahead, sin discard en /data)"
P="$WS/patches/devicetree-22/0003-afinado-rendimiento.patch"
if git -C "$SRC/device/samsung/gts4lv-common" apply --check "$P" 2>/dev/null; then
    git -C "$SRC/device/samsung/gts4lv-common" apply "$P"
    echo "aplicado"
elif git -C "$SRC/device/samsung/gts4lv-common" apply --reverse --check "$P" 2>/dev/null; then
    echo "ya estaba aplicado"
else
    echo "NO aplica limpio -> a mano, ver docs/09"
fi

say "device tree: fuera AudioFX (pelea con SoundAlive, como en A13)"
P="$WS/patches/devicetree-22/0004-quitar-AudioFX.patch"
if git -C "$SRC/device/samsung/gts4lv" apply --check "$P" 2>/dev/null; then
    git -C "$SRC/device/samsung/gts4lv" apply "$P"
    echo "aplicado"
elif git -C "$SRC/device/samsung/gts4lv" apply --reverse --check "$P" 2>/dev/null; then
    echo "ya estaba aplicado"
else
    echo "NO aplica limpio (revisar lineage_gts4lv.mk)"
fi

say "navegadores: solo Firefox (Jelly fuera, Browser2 fuera)"
if [ -d "$SRC/vendor/lineage" ]; then
    P="$WS/patches/vendor-lineage-22/0001-quitar-Jelly.patch"
    if git -C "$SRC/vendor/lineage" apply --reverse --check "$P" 2>/dev/null; then
        echo "Jelly ya estaba fuera"
    elif git -C "$SRC/vendor/lineage" apply --check "$P" 2>/dev/null; then
        git -C "$SRC/vendor/lineage" apply "$P"
        echo "Jelly fuera de vendor/lineage"
    else
        echo "Jelly: NO aplica limpio (quitar a mano en config/common.mk)"
    fi
fi
P="$WS/patches/build-22/0001-quitar-Browser2.patch"
if git -C "$SRC/build/make" apply --check "$P" 2>/dev/null; then
    git -C "$SRC/build/make" apply "$P"
    echo "Browser2 (WebView Browser Tester) fuera"
elif git -C "$SRC/build/make" apply --reverse --check "$P" 2>/dev/null; then
    echo "Browser2 ya estaba fuera"
else
    echo "Browser2: parche no aplica limpio (revisar handheld_product.mk)"
fi
P="$WS/patches/devicetree-22/0002-firefox-en-producto.patch"
if git -C "$SRC/device/samsung/gts4lv-common" apply --check "$P" 2>/dev/null; then
    git -C "$SRC/device/samsung/gts4lv-common" apply "$P"
    echo "Firefox anadido al producto (solo entra si existe el APK)"
elif git -C "$SRC/device/samsung/gts4lv-common" apply --reverse --check "$P" 2>/dev/null; then
    echo "Firefox ya estaba en el producto"
else
    echo "Firefox: parche no aplica limpio (revisar gts4lv.mk)"
fi
echo "descarga el APK con: bash scripts/add-firefox.sh $SRC"
echo "blobs de audio: python3 scripts/port-audio-blobs.py $SRC"

cat <<'FIN'

== Queda a mano (no automatizable sin mirar el arbol)
  1. Device tree 22.2: revisar si siguen haciendo falta nuestros commits de
     releasetools incremental, WiFi CSC y el revert del stack BT de OP6.
     Propiedades de SurfaceFlinger y el quirk de Bluetooth ya estan upstream.
  2. audio: python3 scripts/port-audio-blobs.py <arbol> <arbol-a13>
     (las lib_SoundAlive* y SoundBooster que TheMuppets no trae).
  3. Compilar con microG:  export WITH_GMS=true  y variante userdebug.
  4. WebView/F-Droid: scripts/apply-extras.py <arbol> <cromite.apk> si se usa.
  5. Firefox: bash scripts/add-firefox.sh <arbol> (descarga el APK oficial).
  6. Logs de la tablet: persist.log.tag debe estar en I (no Settings) y no usar
     adb logcat -c (deja los buffers a 0 hasta reiniciar).

== Navegadores
  Solo Firefox: Jelly sale de vendor/lineage y Browser2 (el "WebView Browser
  Tester" de AOSP) sale de build/make. Sin Jelly, Firefox es el unico navegador
  y los enlaces abren en el sin configurar nada.

== Compilar
  bash scripts/build-a15.sh            # prepara todo y compila
  source build/envsetup.sh && breakfast gts4lv && mka bacon -j8

FIN
