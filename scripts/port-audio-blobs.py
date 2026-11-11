#!/usr/bin/env python3
"""Declara en el vendor los blobs de audio de Samsung que TheMuppets no trae.

TheMuppets trae solo una parte de la pila de audio de Samsung: sin las demas
(`libaudiosaplus_sec`, `libmysound`, `libmyspace`, `libsamsungSoundbooster_plus`,
`libaudioeffectoffload`, `libsecaudioinfo`...) los efectos no cargan y SoundAlive
no hace nada.

El script NO descarga nada: copia los blobs que ya esten en ORIGIN (un dump del
vendor stock o un arbol de otra version) y los declara como modulo
`cc_prebuilt_library_shared` + `PRODUCT_PACKAGES`, que es lo que exige
`check-non-elf-file-timestamps` (un ELF por PRODUCT_COPY_FILES aborta la build).

    python3 scripts/port-audio-blobs.py <arbol-22.2> [origen]

Para sacar los blobs del dispositivo con LineageOS 20 ya funcionando:

    adb pull /vendor/lib64/soundfx /tmp/dump/lib64/soundfx
    adb pull /vendor/lib/soundfx   /tmp/dump/lib/soundfx
    adb pull /vendor/lib64/libsecaudioinfo.so /tmp/dump/lib64/
    python3 scripts/port-audio-blobs.py ~/android/lineage-22 /tmp/dump
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "android/lineage-22")
ORIGIN = Path(sys.argv[2] if len(sys.argv) > 2 else Path.home() / "android/lineage-20")

VEN = SRC / "vendor/samsung/gts4lv-common"
PROPRIETARY = VEN / "proprietary/vendor"
MK = VEN / "gts4lv-common-vendor.mk"
BP = VEN / "Android.bp"

# libs sueltas en vendor/lib64 que TheMuppets no trae
ROOT_LIBS = [
    # Del motor de Samsung solo queda Dolby (libswdap, que ya trae TheMuppets) y
    # el offload del HAL. Todo lo de SoundAlive/MySpace/MySound/Booster se quito:
    # la curva del altavoz la hace nuestro libdapeq (hardware/samsung/dap/eq).
    "lib64/libsecaudioinfo.so",
]

# blobs que deben acabar en vendor/{lib,lib64}/soundfx/
SOUNDFX = [
    # Lo carga el propio HAL de Samsung (sec_adev_open), no el framework.
    "libaudioeffectoffload",
]

CANDIDATES = [
    "vendor/samsung/gts4lv-common/proprietary/vendor/{rel}",
    "{rel}",
    "vendor/{rel}",
]


def dt_needed(so):
    out = subprocess.run(["readelf", "-d", str(so)], capture_output=True, text=True).stdout
    libs = re.findall(r"\(NEEDED\)\s+Shared library: \[(.+?)\]", out)
    return [lib[:-3] if lib.endswith(".so") else lib for lib in libs]


def origin_of(rel):
    for cand in CANDIDATES:
        p = ORIGIN / cand.format(rel=rel)
        if p.is_file() and p.stat().st_size > 0:
            return p
    return None


def provide(rel, copied, present, missing):
    """Deja el blob en el arbol (copiandolo si hace falta)."""
    dst = PROPRIETARY / rel
    if dst.is_file() and dst.stat().st_size > 0:
        present.append(rel)
        return True
    src = origin_of(rel)
    if not src:
        missing.append(rel)
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    copied.append(rel)
    return True


def module_block(name, arches, install_path=None):
    # Sin shared_libs a proposito: estos blobs no se enlazan, los carga el
    # framework en runtime. Declararlas obligaria a tener el modulo de cada
    # DT_NEEDED (y en la misma arquitectura), y muchas no existen
    # (libHMT, las SoundAlive de 32 bits...), lo que rompe el meta_lic.
    srcs = []
    for arch, rel in arches:
        srcs.append('        android_%s: {\n'
                    '            srcs: [\n'
                    '                "proprietary/vendor/%s",\n'
                    '            ],\n'
                    '        },\n' % (arch, rel))

    extra = ('    relative_install_path: "%s",\n' % install_path) if install_path else ""
    # Sin compile_multilib: "both" Soong instala solo la variante primaria
    # (arm64) y las de 32 bits no llegan a /vendor/lib. Con prefer: true ademas
    # se genera la variante android_vendor_arm (sin el, no hay 32 bits).
    multilib = '    compile_multilib: "both",\n    prefer: true,\n' if len(arches) > 1 else ""
    return ('\ncc_prebuilt_library_shared {\n'
            '    name: "%s",\n'
            '    owner: "samsung",\n'
            '    soc_specific: true,\n'
            '%s'
            '%s'
            '    strip: {\n'
            '        none: true,\n'
            '    },\n'
            '    // Los DT_NEEDED de Samsung (libHMT, las SoundAlive de 32 bits, la\n'
            '    // variante Quad del booster...) no existen como modulo en AOSP, y el\n'
            '    // chequeo ELF exige declararlos todos: se salta para estos blobs.\n'
            '    check_elf_files: false,\n'
            '    target: {\n%s'
            '    },\n'
            '}\n') % (name, extra, multilib, "".join(srcs))


def main():
    if not VEN.is_dir():
        raise SystemExit("no encuentro %s (arbol 22.2 sincronizado?)" % VEN)
    if not (MK.is_file() and BP.is_file()):
        raise SystemExit("faltan gts4lv-common-vendor.mk o Android.bp en %s" % VEN)

    copied, present, missing = [], [], []
    for rel in ROOT_LIBS:
        provide(rel, copied, present, missing)
    for name in SOUNDFX:
        for d in ("lib", "lib64"):
            provide("%s/soundfx/%s.so" % (d, name), copied, present, missing)

    for rel in copied:
        print("copiada  %s" % rel)
    if present:
        print("ya estaba: %d blobs" % len(present))

    bp_text = BP.read_text()
    mk_text = MK.read_text()
    new_blocks, new_pkgs = [], []

    def declare(name, arches, install_path=None):
        if 'name: "%s",' % name in bp_text:
            return
        new_blocks.append(module_block(name, arches, install_path))
        if "    %s \\\n" % name not in mk_text:
            new_pkgs.append(name)

    for name in sorted({Path(rel).name for rel in ROOT_LIBS}):
        arches = []
        for arch, d in (("arm", "lib"), ("arm64", "lib64")):
            rel = "%s/%s" % (d, name)
            if (PROPRIETARY / rel).is_file():
                arches.append((arch, rel))
        if arches:
            declare(name[:-3], arches)

    for name in SOUNDFX:
        arches = []
        for arch, d in (("arm", "lib"), ("arm64", "lib64")):
            rel = "%s/soundfx/%s.so" % (d, name)
            if (PROPRIETARY / rel).is_file():
                arches.append((arch, rel))
        if arches:
            declare(name, arches, install_path="soundfx")

    if new_blocks:
        BP.write_text(bp_text.rstrip("\n") + "\n" + "\n".join(new_blocks))
        print("Android.bp: +%d modulos" % len(new_blocks))

    if new_pkgs:
        block = "".join("    %s \\\n" % n for n in new_pkgs)
        anchor = "    libswdap \\\n"
        if anchor in mk_text:
            mk_text = mk_text.replace(anchor, anchor + block, 1)
        else:
            mk_text = mk_text.rstrip("\n") + "\n\nPRODUCT_PACKAGES += \\\n" + block
        MK.write_text(mk_text)
        print("gts4lv-common-vendor.mk: +%d en PRODUCT_PACKAGES" % len(new_pkgs))

    if missing:
        print("FALTAN (no estan en %s):" % ORIGIN)
        for rel in missing:
            print("  %s" % rel)
        print("sacalos del dispositivo: adb pull /vendor/%s" % missing[0])
        sys.exit(1)
    print("listo")


if __name__ == "__main__":
    main()
