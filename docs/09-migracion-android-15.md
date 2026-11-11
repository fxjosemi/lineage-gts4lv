# Migracion a Android 15 (LineageOS 22.2)

Preparado el 2026-11-08. Recoge todo lo que hay que llevarse de la build de
Android 13 (LineageOS 20) y como, sin depender de memoria.

## 1. Por que 22.2

- Es el **ultimo Android con soporte oficial** de `gts4lv`: device trees, kernel
  4.9 y blobs tienen rama `lineage-22.2`. No hay que portar plataforma.
- Trae la **pila de Bluetooth de Android 14** (la reescritura de perfiles donde
  estan los arreglos de A2DP) y **conserva** el quirk del WCN3990
  `bluetooth.hci.disabled_commands` (en 23.2/24.0 ya no existe).
- No necesita backport de kernel (eso es solo para 16/17).

## 2. Lo que ya esta upstream en 22.2 (no hay que portarlo)

Comprobado contra `lineage-22.2`:

| Cosa | Estado |
|---|---|
| `SamsungDAP` en `PRODUCT_PACKAGES` y copia de `audio_effects.xml` | ya esta |
| `hardware/samsung/dap/` | sigue existiendo (en 24.0 paso a `packages/Dap`) |
| Props de SurfaceFlinger (`debug.sf.latch_unsignaled`, `early_*_phase_offset_ns`) | ya estan en `vendor.prop` |
| `bluetooth.hci.disabled_commands=377` y props del SoC BT | ya estan |
| Blobs de audio Samsung basicos (`libswdap`, `lib_SoundAlive_SRC384_ver320`) | en TheMuppets 22.2 |
| microG | `vendor/partner_gms` + `WITH_GMS=true` (probado por lineageos4microg en 22.2) |

## 3. Artefactos preparados

| Que | Donde |
|---|---|
| Manifiesto local | `local_manifests/gts4lv-22.xml` |
| App DAP portada a 22.2 | rama `gts4lv-dap-22.2` en `trees/hardware_samsung.git` y parche `patches/hardware-samsung-22/0001-dap-port-completo-a-LineageOS-22.2-Android-15.patch` |
| `audio_effects.xml` con las declaraciones Samsung | `patches/devicetree-22/audio_effects.xml` (+ parche `0001-audio-effects-samsung.patch`) |
| Tweaks de kernel | `patches/kernel/0001`..`0004` (se aplican en el script) |
| Script que lo aplica | `scripts/prepare-a15.sh` |
| Navegador | Solo Firefox: `patches/vendor-lineage-22/0001-quitar-Jelly.patch`, `patches/build-22/0001-quitar-Browser2.patch`, `patches/devicetree-22/0002-firefox-en-producto.patch` y `scripts/add-firefox.sh` |

La rama `gts4lv-dap-22.2` es `hardware/samsung` lineage-22.2 (`ea4723c`) con
nuestro `dap/` completo: estado por dispositivo, SoundAlive solo en el altavoz,
Dolby opcional, `DapApplication`, panel y tile. Se deja el `Android.bp` de 22.2
(es identico al nuestro).

## 4. Pasos

### 4.1 Disco y RAM

- Un arbol 22.2 ocupa ~200 GB con `.repo`; el `out/` otros ~100 GB.
- El `out/` de 22.2 pide bastante RAM en la fase de globs de Soong. Con 22 GB +
  24 GB de swap de esta maquina deberia llegar (24.0 es el que pide ~53 GiB);
  si muere en `Running globs...`, ampliar swap antes de tocar nada.
- No hace falta tener A13 y A15 a la vez: el arbol de A13 es reproducible con
  `local_manifests/gts4lv.xml` + `trees/` + `patches/`.

### 4.2 Sincronizar

```sh
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2
cp local_manifests/gts4lv-22.xml .repo/local_manifests/
repo sync -c -j8 --no-tags --no-clone-bundle --optimized-fetch
```

### 4.3 Aplicar nuestro trabajo

```sh
bash /mnt/c/Users/xjosemi/Documents/TabS5eLTE/scripts/prepare-a15.sh ~/android/lineage-22
```

El script:

1. aplica el port de la app (`hardware/samsung`) si no esta ya;
2. copia `audio_effects.xml` (declaraciones `soundalive_sec`, `mysound`,
   `myspace`, `dap`, `soundbooster_plus`... sin `sa3d`);
3. aplica los cuatro parches de kernel;
4. aplica el afinado del device tree (`stune`, GPU, `read_ahead`, sin `discard`
   en `/data`);
5. quita Jelly de `vendor/lineage`, quita `Browser2` de `build/make` y anade
   Firefox al producto;
6. imprime lo que queda a mano.

### 4.4 Kernel: los cuatro parches de A13

Verificados contra el defconfig de `lineage-22.2`:

| Parche | Que hace |
|---|---|
| `0001-gts4lv_defconfig-HZ-300-zram-lz4-y-quitar-DEBUG_INFO` | `HZ=300`, LZ4/LZ4HC, `CC_OPTIMIZE_FOR_PERFORMANCE`, sin `DEBUG_INFO` |
| `0002-...CPU_BOOST` | `CONFIG_CPU_BOOST=y` (boost por eventos de entrada/migraciones) |
| `0003-...RCU_BOOST` | `CONFIG_RCU_BOOST=y` (como el Pixel 3a) |
| `0004-zram-lz4-por-defecto` | `default_compressor = "lz4"` en `zram_drv.c` (el 4.9 no tiene `CONFIG_ZRAM_DEF_COMP_*`) |

`scripts/kernel-tuned.config` (K6/K7: deadline, sin CFQ group, KGSL preemption)
sigue disponible para builds de kernel sueltos con `scripts/build-kernel.sh tuned`.

### 4.5 Navegador: solo Firefox

- `0001-quitar-Jelly.patch` saca Jelly de `vendor/lineage/config/common.mk`.
- `patches/build-22/0001-quitar-Browser2.patch` saca `Browser2` de
  `build/make/target/product/handheld_product.mk`: es el "WebView Browser
  Tester" de AOSP, que aparecia como navegador de relleno.
- `0002-firefox-en-producto.patch` anade `Firefox` a `PRODUCT_PACKAGES` **solo si
  existe el APK** (`ifneq ($(wildcard ...),)`), asi que el arbol compila igual
  sin el.
- `scripts/add-firefox.sh <arbol>` descarga el APK oficial de Mozilla a
  `device/samsung/gts4lv-common/prebuilt/Firefox/` y crea el
  `android_app_import` (`presigned: true`, dexpreopt). El APK **no** se guarda en
  este repositorio.
- Ojo: `certificate: "PRESIGNED"` en 22.2 pide `PRESIGNED.x509.pem`, que ya no
  existe en `build/make/target/product/security/`; hay que usar
  `presigned: true`.
- Y ademas Firefox (targetSdk >= 30) necesita `preprocessed: true`, que exige a
  su vez las librerias JNI **sin comprimir**. `add-firefox.sh` reempaqueta el APK
  (zip con `lib/` en `-0`), lo alinea con `zipalign -p 4` y lo firma con la clave
  de plataforma del arbol. Sin ese paso la build aborta con
  "Contains compressed JNI libraries".
- El APK sale de `archive.mozilla.org/pub/fenix/releases/<version>/`: el viejo
  `download.mozilla.org/?product=firefox-latest&os=android` devuelve 404 desde
  hace tiempo. Por defecto baja `arm64-v8a` (gts4lv es SDM670); con
  `bash scripts/add-firefox.sh <arbol> universal` baja el universal.
- Al quedar Firefox como unico navegador, los enlaces abren en el sin tocar
  ajustes; no hay prop de AOSP para "navegador por defecto".

### 4.6 Compilar y flashear

```sh
export WITH_GMS=true          # microG
source build/envsetup.sh
breakfast gts4lv
mka bacon -j8
```

âš ï¸ Cambio de version: recovery 22.2 + *Format data* + sideload (borra datos).
Volver a A13 es flashear su recovery/zip (tambien borra datos).

## 4.7 Trampas que costaron una build (Android 15)

Todas resueltas; sirven de aviso si algo cambia:

| Sintoma | Causa | Arreglo |
|---|---|---|
| `unresolved reference: R` / `RadioButtonPreference` en `SamsungDAP` | SettingsLib cambiÃ³ de paquete en A15 | `SelectorWithWidgetPreference` + `com.android.settingslib.collapsingtoolbar.R`, y `static_libs` `SettingsLibCollapsingToolbarBaseActivity` / `SettingsLibSelectorWithWidgetPreference` |
| `found ELF prebuilt in PRODUCT_COPY_FILES` | un `.so` copiado con `PRODUCT_COPY_FILES` | declararlo como `cc_prebuilt_library_shared` + `PRODUCT_PACKAGES` (lo hace `port-audio-blobs.py`) |
| `packaging conflict at lib64/...` | el `fsgen` de A15 promociona `vendor/lib` a `lib64` | no copiar la variante de 32 bits si ya estÃ¡ la de 64 |
| `DT_NEEDED "libX" is not specified in shared_libs` | blobs de Samsung con dependencias que no existen como mÃ³dulo | `check_elf_files: false` en esos mÃ³dulos |
| `missing dependencies: libHMT` | igual que arriba, y `shared_libs` declaradas | dejar los prebuilts **sin** `shared_libs` |
| `invalid file` / `zip END header not found` en `webview.apk` | el repo usa Git LFS y el sync no lo trajo | `git -C external/chromium-webview/prebuilt/arm64 lfs pull` (en los 4 arch) |
| `metalava ... Could not find package com.android.ims...` | restos corruptos de un intento anterior | `rm -rf out/soong/.temp/sbox out/soong/.intermediates/frameworks/base/api/test-api-stubs-docs-non-updatable` |
| Soong muere con un `panic` raro | algÃºn repo quedÃ³ a medias en el sync | `git -C <repo> reset && git -C <repo> checkout -- .` |
| `Killed` (OOM) en `soong_build` | el anÃ¡lisis pide ~27 GB residentes / 36 virtuales | `.wslconfig`: `memory=24GB`, `processors=12`, `swap=16GB` (con 28 GB el host se queda sin memoria) |

## 4.8 Audio: de dÃ³nde salen los blobs

TheMuppets 22.2 trae solo 6 libs en `vendor/lib/soundfx`; faltan las de verdad
(`libaudiosaplus_sec`, `libmysound`, `libmyspace`,
`libsamsungSoundbooster_plus`, `libaudioeffectoffload`, `libgearvr`,
`libplaybackrecorder`). Se sacan del dispositivo con el LineageOS 20 que ya
funcionaba:

```sh
adb pull /vendor/lib64/soundfx /tmp/dump/lib64/soundfx
adb pull /vendor/lib/soundfx   /tmp/dump/lib/soundfx
adb pull /vendor/lib64/libsecaudioinfo.so /tmp/dump/lib64/
python3 scripts/port-audio-blobs.py ~/android/lineage-22 /tmp/dump
```

El script los declara con `soc_specific: true`, `relative_install_path:
"soundfx"` y `check_elf_files: false`, y aÃ±ade el `android_arm64` al mÃ³dulo
`libsecaudioinfo` (que upstream define solo para 32 bits).

## 5. Lo que hay que revisar a mano en el device tree 22.2

Estos commits nuestros de `lineage-20-optimized` **no** estan upstream y hay que
decidir si siguen haciendo falta:

| Tema | Por que |
|---|---|
| `releasetools.py` incremental | por si se quiere OTA propia; para sideload no hace falta |
| WiFi CSC (codigo de pais) | comprobar si 22.2 ya lo trae |
| Revert del stack BT de OP6 | 22.2 usa la pila nueva; el revert es de la vieja |
| Script de zram (`init.gts4lv.zram.sh`) | el `init.target.rc` de 22.2 es distinto; revisar el bloque `on property:sys.boot_completed=1` |
| `AudioFX` fuera del product | en 22.2 ya no se empaqueta |

## 6. Audio (lo importante de esta migracion)

- La app es la misma (`dap/` no cambio de ruta). El port esta en la rama
  `gts4lv-dap-22.2`.
- `audio_effects.xml` de 22.2 solo declara `dap`; el nuestro anade las
  declaraciones de `soundalive_sec`, `mysound`, `myspace`, `soundbooster_plus` y
  los proxies. Sin ellas la app no puede instanciar los efectos.
- **No** se anade `sa3d` al postproceso de musica: se aplica a todas las salidas y
  no se puede apagar (ver `docs/03-dolby.md`, seccion 24).
- Las libs que TheMuppets no trae (`lib_SoundAlive_3DPosition_ver202`,
  `lib_SoundAlive_play_plus_ver400`, `lib_SoundAlive_AlbumArt_ver105`,
  `lib_SoundBooster_ver900`, `lib_SoundAlive_SRC384_ver320`...) se copian del
  dispositivo (o de un dump stock) con
  `scripts/port-audio-blobs.py <arbol-22.2> <origen>`, que ademÃ¡s los declara
  como mÃ³dulos y aÃ±ade su bloque a `PRODUCT_PACKAGES`. Ver Â§4.8.

## 7. Estado real a 10/11/2026 (A15 ya instalado)

La tablet corre **22.2-20261110-UNOFFICIAL-gts4lv** (Android 15, userdebug) con:

- microG, Firefox como unico navegador y navegador por defecto (`isDefault=true`).
- SoundAlive/Dolby: 27 libs en `/vendor/lib64/soundfx` (6 de Samsung) y
  `SamsungDAP` instalado.
- Kernel con `CONFIG_HZ=300`, `CONFIG_CPU_BOOST`, `CONFIG_RCU_BOOST`.

âš ï¸ **Pendiente**: el `Firefox.apk` del zip instalado no valida (falla por
`resources.arsc` comprimido; targetSdk >= 30 lo exige STORED y alineado). En la
tablet ya esta corregido a mano (`/system/app/Firefox/Firefox.apk`), pero **el zip
de `out/lineage-22-a15/` sigue con el APK viejo**, asi que un reflasheo dejaria la
tablet sin navegador. Para arreglarlo: `scripts/add-firefox.sh` ya reempaqueta con
`resources.arsc` sin comprimir, y el APK corregido esta en
`out/lineage-22-a15/Firefox-fixed.apk`; falta **recompilar** (`bash
scripts/build-a15.sh`) para regenerar el zip.

Pendiente tambien comprobar en la tablet:
- `zram` **ya usa lz4**: en `/sys/block/zram0/comp_algorithm` la salida es
  `lzo [lz4] deflate lz4hc` y los corchetes marcan el **activo**, asi que el
  parche `0004` funciona. Ratio medido en `mm_stat`: 86,9 MB â†’ 18,8 MB (4,6:1).

### Estado de RAM medido (11/11/2026, sin recompilar nada)

| Metrica | Valor | Lectura |
|---|---|---|
| MemTotal / MemAvailable | 3.565 MB / 639 MB | sano |
| Cached | 726 MB | el sistema esta usando cache, como debe |
| Swap total / usado | 2.169 MB / 91 MB | zram casi sin usar |
| PSI memoria (some avg300) | **0,12 %** | sin presion de memoria |
| PSI CPU (some avg10) | 2,83 % | **el cuello de botella es CPU** |
| PSI io (some avg300) | 0,79 % | despreciable |
| Kills del LMK | **0** | nunca ha matado nada |

Conclusion: no hay nada que afinar en RAM/zram (ni swappiness, ni
`vfs_cache_pressure`, ni tamaÃ±o de zram): el sistema no pasa penuria, y lo que
limita es CPU/GPU, igual que salio en `docs/04-benchmarks.md`. Lo unico que se
come la memoria es Firefox (2 pestaÃ±as â‰ˆ 760 MB entre 4 procesos).

Verificado que **no** hace falta: el `recovery.img` de 22.2 si se flasheo. Se
comprueba sin reiniciar comparando el arranque de la particion con el fichero:

```sh
adb shell "dd if=/dev/block/mmcblk0p49 bs=1M count=1 2>/dev/null | sha256sum"
head -c 1048576 recovery.img | sha256sum      # deben coincidir
```

(Comparar los 64 MB enteros da distinto aunque sea el correcto: la particion mide
72.744.960 bytes y el `dd` arrastra relleno.)

## 8. Audio en A15: causa raiz y arreglo (11/11/2026)

**Sintoma**: el DSP de Samsung no se aplicaba. La app DAP fallaba al crear el
efecto (`Cannot initialize effect engine ... Error: -3`) y Dolby solo "aparecia"
sin control.

**Causa raiz, una sola**: quien parsea `/vendor/etc/audio_effects.xml` y hace
`dlopen` de `/vendor/lib/soundfx` es el **HAL de efectos**, que en esta ROM es
**de 32 bits** (`android.hardware.audio.effect@6.0`, `/vendor/lib/hw/`, lo
confirma `lshal`). Las dependencias de Samsung solo estaban en `/vendor/lib64`,
asi que:

```
EffectsFactoryConfigLoader: loadLibrary Could not dlopen /vendor/lib/soundfx/libaudiosaplus_sec.so:
    dlopen failed: library "lib_SoundAlive_play_plus_ver400.so" not found
libmyspace.so:                  lib_SoundAlive_3DPosition_ver202.so  not found
libsamsungSoundbooster_plus.so: lib_SoundBooster_ver900.so           not found
libgearvr.so:                   libHMT.so                           not found
```

Con 11 elementos del config descartados, cualquier `AudioEffect` con esos UUIDs
devolvia `-2` (NAME_NOT_FOUND) â€” y tambien los de AOSP (`equalizer`, `downmix`,
`bassboost`...), porque sus librerias tampoco estaban en 32 bits.

**Arreglo**: las dependencias **de 32 bits** (venian del vendor de A13) van a
`/vendor/lib` y se declaran en el vendor tree con `compile_multilib: "both"`:

- `lib_SoundAlive_play_plus_ver400.so`
- `lib_SoundAlive_AlbumArt_ver105.so`
- `lib_SoundAlive_3DPosition_ver202.so`
- `lib_SoundBooster_ver900.so`

Falta `libHMT.so`: solo afecta a `vr3d`/GearVR, no al audio.

**Comprobacion**: el config loader pasa de `11 errors ... skipped 11 elements` a
`5 errors ... skipped 5 elements`, y en la tablet:

```
1 Effect Chains / 1 effects for session 0
  Effect ID 11: Enabled: y, State 002
  UUID: 05227ea0-50bb-11e3-ac69-0002a5d5c51b
  TYPE: c4da1d1f-7cdf-42e2-ba60-efc7eb3508a3
  name: SoundAlivePlus   implementor: Samsung
  Clientes: pid de org.lineageos.dap
```

**UUIDs que funcionan de verdad** (probados uno a uno con una sonda en la app):
`c4da1d1f` (SoundAlive; el proxy `soundalive` lo resuelve a
`libaudiosaplus_sec`) y `46d279d9` (Dolby DAX3, que lo expone el propio HAL).
El resto (`dap`, `dap_proxy`, `soundalive_proxy`, `cf65eb39`, `sa3d`...) **no**
son creables por un cliente aunque esten declarados en el XML.

**Sesion global**: el sistema no manda `OPEN_AUDIO_EFFECT_CONTROL_SESSION` a la
app (el controlador configurado es AudioFX, que va fuera del producto), asi que
el motor se engancha tambien a la **sesion 0** (salida global) desde
`refreshEffects()`/`setEnabled()`. Asi suena en todas las apps sin depender de
que el reproductor avise.

**Diagnostico** (lo que dio con la causa):

```
adb shell setprop log.tag.EffectsFactoryConfigLoader VERBOSE
adb shell setprop log.tag.EffectsFactory VERBOSE
adb shell setprop ctl.restart audioserver
adb shell logcat -d | grep -E "EffectsFactoryConfigLoader|Effect config"
```

**Descartado por el camino**: `<apply effect="sa3d"/>` en el stream de musica
(rompe la cadena), `audio_effects_sec.xml` (no cambia nada), y comparar los
64 MB del recovery (la particion lleva relleno).

**Estado del zip**: el zip que hay en `out/lineage-22-a15/` es anterior a este
arreglo. Un reflash tal cual dejaria la tablet sin las dependencias de 32 bits y
sin la app nueva, asi que hay que regenerarlo antes de volver a flashear.

## 9. Riesgos

| Riesgo | Mitigacion |
|---|---|
| Rendimiento en 4 GB | medir con `docs/04-benchmarks.md` contra el build 2 de A13 antes de decidir |
| Conflictos al aplicar el afinado (init.target.rc/fstab) | parche propio `patches/devicetree-22/0003-afinado-rendimiento.patch`, verificado contra 22.2 |
| Sync que deja un repo con ficheros a medias | si Soong muere con un `panic` raro, `git -C <repo> reset && git -C <repo> checkout -- .` (paso con `art`) |
| El `audio_effects.xml` de 22.2 cambie de formato | comparar con `patches/devicetree-22/0001-audio-effects-samsung.patch` |
| microG | `WITH_GMS=true` y `userdebug`; si falla, aislarlo del resto |
| Logs | en la tablet: `persist.log.tag` en `I` (estaba en `Settings` y filtraba todo) y no usar `adb logcat -c` |

## 10. Checklist de validacion
- Arranque, WiFi, LTE datos, pantalla/tactil.
- Audio por altavoz con la curva stock y los perfiles.
- Cascos/BT: **sin** efecto de SoundAlive (panel en `Solo altavoz`), Dolby
  opcional.
- A2DP con los Nothing: conexion estable y audio enroutado (esto es lo que motivÃ³
  el salto).
- Navegador: solo Firefox instalado (sin Jelly ni `Browser2`) y los enlaces
  abren en Firefox.
- microG: F-Droid y microG Settings.
- Medicion: arranque, `meminfo`, `gfxinfo`, `batterystats` (3 pasadas).

## 10. Curva del altavoz propia: `libdapeq` (11/11/2026)

Sustituye al motor de Samsung: mismo sonido de partida, sin sus librerias.

**Donde esta**: `hardware/samsung/dap/eq/` (`Android.bp` + `dapeq.cpp`), efecto
propio con la API `hardware/audio_effect.h` (simbolo `AELI`).

**La curva** es la unica cosa que haciamos con su motor, 9 bandas en dB:

```
63 Hz  125  250  500   1k   2k    4k   8k  16k
   1     4    3   -6    1   -3   -12   -2    4
```

`dapeq.cpp` la lleva dentro (`kBaseDb`), asi que la curva va puesta desde que se
crea el efecto, sin que nadie la pida.

**Parametros** (`setParameter`), todos en centesimas de dB:

| Param | Que es |
|---|---|
| `1` | bypass (0/1) |
| `2` | pre-ganancia, que la app calcula sola: `-max(0, pico de la curva)` |
| `10+n` | banda `n` (0..8) |
| `20` | las 9 bandas de golpe (9 x int32) |

**DSP**: 9 biquads peaking (RBJ, Q=1.4) en cascada por canal, pre-ganancia y
saturacion suave. Soporta `PCM_FLOAT` (lo que entrega el mezclador de A15) y
`PCM_16_BIT`. Por encima de Nyquist la banda se deja pasar.

**Instalacion**: `compile_multilib: "both"` + `relative_install_path: "soundfx"`,
o sea `/vendor/lib/soundfx/libdapeq.so` (32 bits, que es lo que carga el HAL de
efectos) y `/vendor/lib64/soundfx/`.

**Enganche**: la app lo crea en la **sesion 0** (salida global) como antes, con
el UUID `d1e0a001-7c00-4b00-9f00-000000000001`. Comprobado en la tablet:

```
Effect ID 11: Session 00000  State 003  Enabled y
TYPE/UUID: d1e0a001-7c00-4b00-9f00-000000000001
name: Speaker EQ   implementor: The LineageOS Project
```

**Trampa que costo 20 minutos**: el simbolo `AELI` **no** puede estar dentro de
un `namespace { }` anonimo. Queda con linkage interno y el config loader dice
`failed not find symbol 'AELI' ... undefined symbol: AELI`.

**Dolby fuera**: `EffectSessionReceiver` y `BootCompletedReceiver` ya no llaman a
`DolbyCore`/`applyDolby`; el 3D (`sa3d`) tampoco se crea.

**Depuracion**:

```
adb shell setprop log.tag.EffectsFactoryConfigLoader VERBOSE
adb shell setprop ctl.restart audioserver
adb shell logcat -d | grep -E "EffectsFactoryConfigLoader|DapEq"
adb shell dumpsys media.audio_flinger | grep -E "name:|Enabled"
```

Los errores del config bajan a 5 (todos de librerias de Samsung que sobran y de
`libHMT`/`vr3d`); `dapeq` no da ninguno.

**Pendiente**: quitar del producto los blobs de Samsung (`soundfx` y los 4 de 32
bits) y los `lib_SoundAlive_*`, ya sin uso. Eso y regenerar el zip.

## 11. Ajustes finos del 11/11 (madrugada): una instancia y cascada corregida

**Dos instancias = doble EQ.** El receptor creaba el efecto en la sesion del
reproductor *ademas* de la global (0), asi que una pista con sesion propia pasaba
por las dos: +4 dB -> +9 dB en 125 Hz y -12 -> -24 dB en 4 kHz (suena a graves de
sobra). Ahora solo existe en la sesion 0: `EffectSessionReceiver` ya no llama a
`addSession`, asi que nunca hay dos.

**Las bandas se sumaban.** Los 9 filtros estan a una octava y se solapan, de modo
que la respuesta real era la suma de todos:

| Banda | Pedido | Real (Q=1.4, sin corregir) |
|---|---|---|
| 125 Hz | +4,0 | +4,5 |
| 1 kHz | +1,0 | -1,1 |
| 2 kHz | -3,0 | -5,5 |
| 8 kHz | -2,0 | -4,0 |

`computeCoefficients()` ahora resuelve los puntos de ajuste con 4 iteraciones
(9x9 respuestas complejas, solo al cambiar parametros) para que en el centro de
cada banda se mida exactamente lo pedido.

**Reparto de responsabilidades (lo que quedo):**

| Que | Quien | Cuando |
|---|---|---|
| Curva BASE del altavoz | `libdapeq` en la sesion 0 | **siempre**, solo altavoz |
| Ajustes del usuario | la misma instancia (`enabled`) | solo con Dolby encendido |
| Dolby Atmos | `libswdap` (DAX3) en la sesion 0 | si el interruptor esta on |

Nuestra EQ declara `EFFECT_FLAG_INSERT_FIRST`, asi que va siempre antes de Dolby.

**Interfaz**: el panel queda en dos bloques. "Dolby Atmos" (interruptor +
Automatico/Pelicula/Musica/Voz + juegos) y "Ecualizador", que **solo se ve con
Dolby encendido** (`eq_category` se oculta en `updateDolbyUi`). Fuera el
interruptor "Activar SoundAlive", los textos largos de intro, el 3D y las
valvulas.

**Device effects: descartado en esta ROM.** `AudioPolicyEffects: cannot attach
effect Speaker EQ on patch 12`: el patch del altavoz al arrancar es HW y los
device effects solo van en patches SW. Se probo con `POST_PROC` (obligatorio para
ellos) y el fallo es el enganche, no el tipo.

**Verificado en la tablet**: con Dolby apagado, una sola `Speaker EQ` activa
(sesion 0). Con Dolby encendido, `2 effects for session 0`: `Speaker EQ` +
`DAX3_S_3.6.2.0_r1`.

## 12. Kernel: afinado final (11/11)

Ya venian de A13: `HZ=300`, `PREEMPT`, `SCHED_WALT`, `SCHED_TUNE`,
`CGROUP_SCHEDTUNE`, `CPU_BOOST` (boost por eventos), `RCU_BOOST`, zram con lz4
(`ZRAM_DEF_COMP_LZ4` + `CRYPTO_LZ4`), `CC_OPTIMIZE_FOR_PERFORMANCE`, sin
`DEBUG_INFO`.

Anadido ahora (`0005-gts4lv_defconfig-bbr-y-sin-schedstats.patch`):

- **BBR** como congestion de TCP por defecto (`CONFIG_TCP_CONG_BBR=y` +
  `CONFIG_DEFAULT_TCP_CONG="bbr"`). El codigo ya estaba en el arbol
  (`net/ipv4/tcp_bbr.c`), solo no se compilaba. Va mejor en movil (menos colas,
  mejor latencia con perdidas).
- **`CONFIG_DEFAULT_BIC` fuera**: choca con el selector de congestion por defecto.
- **`CONFIG_SCHEDSTATS` fuera**: contabilidad por tarea que no usamos.

No se ha tocado: `PREEMPT` (se queda en voluntary/full segun stock), governor
(`schedutil`), ni nada de termica.

Comprobacion en la tablet tras flashear:
```
adb shell cat /proc/sys/net/ipv4/tcp_congestion_control   # bbr
adb shell cat /sys/block/sda/queue/scheduler              # el que use el UFS
```


## 13. microG fuera, GApps de Google (11/11, madrugada)

### 13.1 Que paso con microG

microG no es un parche: son paquetes que solo entran si el producto lo pide. La
cadena es `vendor/lineage/config/partner_gms.mk`, que empieza con
`ifeq ($(WITH_GMS),true)` y, si se cumple, hereda
`vendor/partner_gms/products/gms.mk` (`GmsCore`, `FakeStore`, `GsfProxy`,
`FDroid`, `FDroidPrivilegedExtension`, `additional_repos.*`).

Consecuencia: **`m bacon` a mano, sin `WITH_GMS`, compila una ROM sin microG**, y
no avisa de nada. El 10/11 paso exactamente eso:

| build | como | microG |
|---|---|---|
| 12:19 | `scripts/build-a15.sh` (`WITH_GMS=true`) | si (`adding: SYSTEM/product/priv-app/GmsCore/GmsCore.apk`) |
| 23:42 | `m bacon` suelto para probar el audio | **no** |

`getprop ro.build.date` en la tablet daba `Tue Nov 10 23:42:03`, o sea la segunda.
Al flashear, un APK de sistema que ya no existe se borra **con sus datos**: hubo
que volver a iniciar sesion en microG.

### 13.2 Decision: ROM limpia + MindTheGapps

Se deja de compilar microG. `scripts/build-a15.sh` exporta
`WITH_GMS="${WITH_GMS:-false}"`, asi que la ROM sale limpia y las GApps se
flashean aparte, que es lo que hace todo el mundo con LineageOS:

```sh
adb sideload lineage-22.2-<fecha>-UNOFFICIAL-gts4lv.zip
adb sideload MindTheGapps-15.0.0-arm64-<fecha>.zip    # en recovery, justo despues
```

- MindTheGapps 15.0.0-arm64 se baja de su GitHub
  (`MindTheGapps/15.0.0-arm64`); el espejo `download.mirrorservice.com` esta
  muerto (403 / dominio en venta), asi que `tools/get-gapps.sh` usa la API de
  GitHub y comprueba el `sha256`.
- El zip trae 22 APK en `system/product` y `system/system_ext` (GmsCore,
  Phonesky, Velvet, GSF, SetupWizard, overlays) mas sus `privapp-permissions`,
  `sysconfig` y un `addon.d`, asi que **sobreviven a las actualizaciones** de la
  ROM.
- No se puede mezclar: microG y GApps usan el mismo nombre de paquete
  (`com.google.android.gms`) con firmas distintas. Al flashear una ROM sin microG,
  PackageManager borra el paquete y sus datos, y las GApps entran limpias.
- Volver a microG es `WITH_GMS=true bash scripts/build-a15.sh`, pero eso
  recompila medio arbol (cambia la configuracion del producto).

### 13.3 Aurora Store como app de sistema

`scripts/add-aurorastore.sh` deja dos prebuilts en
`device/samsung/gts4lv-common/prebuilt/` y el parche
`0006-aurora-store-en-producto.patch` los mete en `PRODUCT_PACKAGES` (con guarda
`ifneq ($(wildcard ...),)`, igual que Firefox).

- `AuroraStore` (4.8.4): `android_app_import` con `presigned: true`,
  `privileged: true` y `dex_preopt` desactivado (targetSdk 37). Ademas un
  `default-permissions` con notificaciones y almacenamiento.
- `AuroraServices` (1.1.1): el backend que instala y desinstala sin dialogos.
  Es el unico que declara permisos privilegiados, y son exactamente dos:

  ```
  android.permission.INSTALL_PACKAGES   [signature|privileged]
  android.permission.DELETE_PACKAGES    [signature|privileged|role]
  ```

  `Aurora Store` **no** declara ninguno (comprobado con `aapt2 dump permissions`
  contra el `AndroidManifest.xml` del framework). Por eso hacerla priv-app no le
  da instalar sola: el instalador se elige en
  **Ajustes -> Instalacion -> Metodo de instalacion**, y ahi hay que marcar
  *Servicios de Aurora* (por defecto esta *Instalador de sesion*, que pide
  confirmacion en cada APK).

Ojo con `ro.control_privapp_permissions=enforce`, que es como viene esta ROM: la
whitelist tiene que estar **completa** o el paquete no arranca. Por eso la de
Services se genero desde el manifiesto y no a ojo.

Los APK no se guardan en el repositorio. Si las descargas fallan, el script
acepta el APK ya descargado:

```sh
AURORA_STORE_APK=~/Descargas/AuroraStore-4.8.4.apk bash scripts/add-aurorastore.sh
```

Comprobacion en la tablet:
```
adb shell pm list packages | grep -iE "gms|vending|aurora|fdroid"
adb shell dumpsys package com.aurora.services | grep -E "codePath|INSTALL_PACKAGES"
adb shell dumpsys package com.aurora.store    | grep -E "codePath|flags="
```
