# LineageOS 22.2 para Galaxy Tab S5e LTE (gts4lv)

Device tree de `gts4lv-common` con mis cambios para Android 15, más los parches
y scripts que van en otros repos.

## Qué hay

- Raíz: device tree `gts4lv-common`.
- `gts4lv-device/`: el device tree `gts4lv`.
- `patches/kernel/`: defconfig (`HZ=300`, zram lz4, CPU/RCU boost, BBR).
- `patches/build/`, `patches/vendor-lineage/`: quitar Browser2 y Jelly.
- `patches/hardware-samsung/`: app DAP (curva del altavoz + Dolby).
- `patches/0005-bbr-por-sysctl.patch`: BBR por defecto en `init.target.rc`.
- `docs/`: notas de la migración y del audio.
- `scripts/`: sincronizar, compilar, Firefox, blobs de audio y sideload.

## Audio

La curva del altavoz la hace un efecto propio (`hardware/samsung/dap/eq`), sin
librerías de Samsung: 9 bandas en la sesión global, solo en el altavoz. Dolby se
queda como efecto opcional encima y su ecualizador de usuario solo actúa con
Dolby encendido.

## Compilar

```
scripts/build-a15.sh
```

El APK de Firefox no está en el repo (238 MB); lo descarga y firma
`scripts/add-firefox.sh`.
