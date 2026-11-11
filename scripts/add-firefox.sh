#!/usr/bin/env bash
# Deja Firefox como app de sistema (prebuilt) en un arbol LineageOS 22.2.
#
#   bash scripts/add-firefox.sh [ruta-del-arbol] [arm64-v8a|universal]
#   # por defecto arm64-v8a (gts4lv es SDM670), que pesa bastante menos
#
# Descarga el APK oficial firmado de Mozilla desde archive.mozilla.org (el viejo
# download.mozilla.org/?product=firefox-latest&os=android ya devuelve 404) y crea
# el android_app_import. Jelly sigue siendo el navegador de LineageOS: Firefox se
# anade al lado, y con Browser2 fuera no hay ningun otro navegador.
set -euo pipefail

SRC="${1:-$HOME/android/lineage-22}"
FLAVOUR="${2:-arm64-v8a}"
DIR="$SRC/device/samsung/gts4lv-common/prebuilt/Firefox"
ARCHIVE="https://archive.mozilla.org/pub/fenix/releases"

if [ ! -d "$SRC/device/samsung/gts4lv-common" ]; then
    echo "no parece el arbol esperado: $SRC" >&2
    exit 1
fi

latest_version() {
    curl -sL --fail --retry 3 "$ARCHIVE/" |
        grep -oE 'href="/pub/fenix/releases/[0-9][^"]*/"' |
        sed 's#href="/pub/fenix/releases/##;s#/"##' |
        grep -vE '(a|b)[0-9]+$' |
        sort -t. -k1,1n -k2,2n -k3,3n |
        tail -1
}

if [ -s "$DIR/Firefox.apk" ]; then
    echo "Firefox.apk ya existe ($(du -h "$DIR/Firefox.apk" | cut -f1)), no se descarga"
else
    V="$(latest_version)"
    [ -n "$V" ] || { echo "no pude resolver la ultima version de Firefox" >&2; exit 1; }
    if [ "$FLAVOUR" = "universal" ]; then
        URL="$ARCHIVE/$V/android/fenix-$V-android/fenix-$V.multi.android-universal.apk"
    else
        URL="$ARCHIVE/$V/android/fenix-$V-android-arm64-v8a/fenix-$V.multi.android-arm64-v8a.apk"
    fi
    mkdir -p "$DIR"
    echo "descargando Firefox $V ($FLAVOUR)..."
    curl -L --fail --retry 3 --output "$DIR/Firefox.apk" "$URL"
fi

if [ "$(head -c 2 "$DIR/Firefox.apk")" != "PK" ]; then
    echo "la descarga no es un APK valido" >&2
    rm -f "$DIR/Firefox.apk"
    exit 1
fi

# Firefox trae las librerias JNI comprimidas, y un prebuilt va como
# preprocessed: true (targetSdk >= 30 -> firma v2), lo que exige que vayan sin
# comprimir. Se reempaqueta y se firma con la clave de plataforma del arbol.
ZIPALIGN="$SRC/out/host/linux-x86/bin/zipalign"
APKSIGNER_JAR="$SRC/prebuilts/sdk/tools/linux/lib/apksigner.jar"
JAVA="$SRC/prebuilts/jdk/jdk21/linux-x86/bin/java"
KEYS="$SRC/build/make/target/product/security"

needs_repackage() {
    [ "$(head -c 2 "$DIR/Firefox.apk")" = "PK" ] || return 0
    # si el APK ya esta firmado con la clave de plataforma, no se toca
    "$JAVA" -jar "$APKSIGNER_JAR" verify --print-certs "$DIR/Firefox.apk" 2>/dev/null |
        grep -q "CN=Android, OU=Android, O=Android" && return 1
    return 0
}

if needs_repackage; then
    for f in "$ZIPALIGN" "$APKSIGNER_JAR" "$JAVA" "$KEYS/platform.pk8"; do
        [ -e "$f" ] || { echo "falta $f (compila antes de anadir Firefox)" >&2; exit 1; }
    done
    echo "reempaquetando (libs JNI y resources.arsc sin comprimir) y firmando..."
    W="$(mktemp -d)"
    cp "$DIR/Firefox.apk" "$W/orig.apk"
    mkdir "$W/x" && ( cd "$W/x" && unzip -q ../orig.apk )
    # targetSdk >= 30: resources.arsc y las .so van STORED, y luego zipalign -p
    ( cd "$W/x" && zip -q -r -0 "$W/unaligned.apk" lib resources.arsc &&
      zip -q -r "$W/unaligned.apk" . -x 'lib/*' -x 'resources.arsc' )
    "$ZIPALIGN" -p -f 4 "$W/unaligned.apk" "$W/aligned.apk"
    "$JAVA" -jar "$APKSIGNER_JAR" sign \
        --key "$KEYS/platform.pk8" --cert "$KEYS/platform.x509.pem" \
        --out "$W/signed.apk" "$W/aligned.apk"
    cp "$W/signed.apk" "$DIR/Firefox.apk"
    rm -rf "$W"
else
    echo "el APK ya estaba reempaquetado y firmado, se deja"
fi

cat > "$DIR/Android.bp" <<'BP'
android_app_import {
    name: "Firefox",
    apk: "Firefox.apk",
    presigned: true,
    // targetSdk >= 30 va firmado con v2; si el build lo reprocesa se carga la
    // firma, asi que se instala tal cual (sin dexpreopt).
    preprocessed: true,
    // Firefox declara estas tres como uses-library-not-required en su manifiesto;
    // si no se listan aqui, manifest_check aborta la build.
    optional_uses_libs: [
        "android.car",
        "androidx.window.extensions",
        "androidx.window.sidecar",
    ],
}
BP

echo "listo: $DIR/Firefox.apk ($(du -h "$DIR/Firefox.apk" | cut -f1))"
echo "el parche 0002-firefox-en-producto.patch del device tree lo mete en el"
echo "producto (lo aplica prepare-a15.sh)."
