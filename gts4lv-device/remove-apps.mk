#
# Se hereda DESPUES de vendor/lineage/config/common_full_tablet.mk.
#
# Ojo: $(call inherit-product, ...) es diferido,asi que un filter-out en
# lineage_gts4lv.mk se evalua ANTES de que las hojas heredadas anadan sus
# paquetes y no borra nada. Poniendolo en un makefile heredado en ultimo lugar,
# cuando se evalua ya estan todos los PRODUCT_PACKAGES.
#
#  - AudioFX: mete sus propios efectos (Equalizer, BassBoost, Virtualizer,
#    Reverb) en la cadena y ademas pelea con SoundAlive. Todo el audio se
#    controla desde el panel de Dolby / SoundAlive.
#
PRODUCT_PACKAGES := $(filter-out AudioFX,$(PRODUCT_PACKAGES))
