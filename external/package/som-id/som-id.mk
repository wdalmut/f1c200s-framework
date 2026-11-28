################################################################################
#
# som-id
#
# Tool e parser del record di identificazione nell'EEPROM del modulo. Il
# sorgente vive in una repo propria perche' serve a tutta la famiglia di SoM:
# questo package fissa solo il tag. Per lavorare su un checkout locale senza
# tag: SOM_ID_OVERRIDE_SRCDIR = /percorso/som-id in <output>/local.mk.
#
################################################################################

SOM_ID_VERSION = 1.0.0
SOM_ID_SITE = $(call github,egaree,som-id,v$(SOM_ID_VERSION))
SOM_ID_LICENSE = MIT
SOM_ID_LICENSE_FILES = LICENSE

# clean prima: con SOM_ID_OVERRIDE_SRCDIR la copia del checkout porta con se'
# i binari compilati per l'host, con date piu' recenti dei sorgenti.
define SOM_ID_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) clean
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" som-id
endef

define SOM_ID_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) PREFIX=/usr install
endef

$(eval $(generic-package))
