#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# check-image.sh — verifica gli artefatti di una build, senza avere la board.
#
#   ./docs/check-image.sh [output/images]
#   make check
#
# Ognuno di questi controlli corrisponde a un errore realmente commesso
# durante il bring-up: header di boot assente, console su UART sbagliata,
# mappa DRAM da 32 MB, kernel compilato ARMv7, DTB della board sbagliata,
# bootcmd che punta a una SPI NOR inesistente. Vedi docs/BOARD-FACTS.md.
#
set -uo pipefail

IMAGES="${1:-output/images}"
BUILD="$(cd "$IMAGES/../build" 2>/dev/null && pwd)" || BUILD=""
HOSTBIN="$(cd "$IMAGES/../host/bin" 2>/dev/null && pwd)" || HOSTBIN=""

rc=0
pass() { printf '  \033[32mok\033[0m    %s\n' "$*"; }
fail() { printf '  \033[31mKO\033[0m    %s\n' "$*"; rc=1; }
skip() { printf '  \033[33m--\033[0m    %s\n' "$*"; }

echo
echo "check-image — $IMAGES"
echo

[ -d "$IMAGES" ] || { fail "directory non trovata: $IMAGES (hai gia' lanciato 'make'?)"; exit 1; }

# --- 1. header che cerca la BROM --------------------------------------------
# La BROM dell'F1C200s cerca "eGON.BT0" a offset 8 KiB + 4 byte (i primi 4
# sono l'istruzione di salto). Se manca, la board ignora la SD in silenzio.
if [ -f "$IMAGES/sdcard.img" ]; then
	magic="$(dd if="$IMAGES/sdcard.img" bs=1 skip=8196 count=8 2>/dev/null)"
	[ "$magic" = "eGON.BT0" ] \
		&& pass "eGON.BT0 a offset 8 KiB" \
		|| fail "a offset 8 KiB c'e' '$magic' invece di eGON.BT0"
else
	fail "sdcard.img assente"
fi

# --- 2. layout partizioni ----------------------------------------------------
if [ -f "$IMAGES/sdcard.img" ] && command -v /sbin/fdisk >/dev/null 2>&1; then
	parts="$(/sbin/fdisk -l "$IMAGES/sdcard.img" 2>/dev/null | grep -c '^.*img[12] ')"
	[ "$parts" = 2 ] \
		&& pass "2 partizioni nella tabella MBR" \
		|| fail "trovate $parts partizioni invece di 2"
	# la p1 non deve invadere lo spazio di SPL+U-Boot (8 KiB .. 2 MiB)
	start="$(/sbin/fdisk -l "$IMAGES/sdcard.img" 2>/dev/null | awk '/img1/{print $3}')"
	[ -n "$start" ] && [ "$start" -ge 4096 ] \
		&& pass "p1 parte a settore $start (>= 2 MiB, non calpesta U-Boot)" \
		|| fail "p1 parte a settore ${start:-?}: sovrascrive SPL/U-Boot"
else
	skip "fdisk non disponibile: layout partizioni non verificato"
fi

# --- 3. contenuto della FAT --------------------------------------------------
if [ -f "$IMAGES/boot.vfat" ] && [ -x "$HOSTBIN/mdir" ]; then
	listing="$(MTOOLS_SKIP_CHECK=1 "$HOSTBIN/mdir" -i "$IMAGES/boot.vfat" :: 2>/dev/null)"
	echo "$listing" | grep -qi zImage \
		&& pass "zImage presente nella FAT" || fail "zImage assente dalla FAT"
	echo "$listing" | grep -qi 'suniv-f1c200s-lctech-pi.dtb' \
		&& pass "DTB presente nella FAT" || fail "DTB assente dalla FAT"
else
	skip "mtools non disponibile: contenuto della FAT non verificato"
fi

# --- 4. configurazione U-Boot ------------------------------------------------
ucfg="$(ls -d "$BUILD"/uboot-*/.config 2>/dev/null | head -1)"
if [ -n "$ucfg" ] && [ -f "$ucfg" ]; then
	chk() { grep -q "^$1\$" "$ucfg" && pass "u-boot: $1" || fail "u-boot: atteso $1"; }
	chk 'CONFIG_CONS_INDEX=2'
	chk 'CONFIG_SUNXI_MINIMUM_DRAM_MB=64'
	chk 'CONFIG_DEFAULT_DEVICE_TREE="allwinner/suniv-f1c200s-lctech-pi"'
	grep -q '^CONFIG_BOOTCOMMAND=.*load mmc 0:1' "$ucfg" \
		&& pass "u-boot: bootcmd carica da mmc 0:1" \
		|| fail "u-boot: il bootcmd non carica da mmc 0:1"
	grep -q '^CONFIG_BOOTCOMMAND=.*sf read' "$ucfg" \
		&& fail "u-boot: il bootcmd usa 'sf read' — la flash di questa board e' NAND, non NOR" \
		|| pass "u-boot: nessun 'sf read' nel bootcmd"
else
	skip "config di U-Boot non trovata: build fatta altrove?"
fi

# --- 5. configurazione kernel ------------------------------------------------
kcfg="$(ls -d "$BUILD"/linux-*/.config 2>/dev/null | head -1)"
if [ -n "$kcfg" ] && [ -f "$kcfg" ]; then
	chk() { grep -q "^$1\$" "$kcfg" && pass "kernel: $1" || fail "kernel: atteso $1"; }
	chk 'CONFIG_ARCH_MULTI_V5=y'
	chk 'CONFIG_MACH_SUNIV=y'
	chk 'CONFIG_CPU_ARM926T=y'
	chk 'CONFIG_MMC_SUNXI=y'
	chk 'CONFIG_EXT4_FS=y'
	grep -q '^CONFIG_ARCH_MULTI_V7=y' "$kcfg" \
		&& fail "kernel: ARCH_MULTI_V7 attivo — il binario non gira su ARM926EJ-S" \
		|| pass "kernel: ARCH_MULTI_V7 disattivo"
else
	skip "config del kernel non trovata: build fatta altrove?"
fi

# --- 6. bootcmd realmente compilato nel binario ------------------------------
if [ -f "$IMAGES/u-boot.bin" ]; then
	# NB: 'grep -c' e non 'grep -q'. Con -q grep esce al primo match e manda
	# SIGPIPE a strings; sotto 'set -o pipefail' lo stato della pipeline
	# diventa 141 e il controllo fallisce anche quando la stringa c'e'.
	n="$(strings "$IMAGES/u-boot.bin" | grep -c '^bootcmd=load mmc 0:1')"
	[ "${n:-0}" -ge 1 ] \
		&& pass "bootcmd presente nell'ambiente compilato in u-boot.bin" \
		|| fail "bootcmd non trovato in u-boot.bin: il fragment non e' stato applicato"
else
	skip "u-boot.bin assente"
fi

# --- 7. il DTB e' quello della board -----------------------------------------
dtb="$IMAGES/suniv-f1c200s-lctech-pi.dtb"
if [ -f "$dtb" ] && [ -x "$HOSTBIN/dtc" ]; then
	model="$("$HOSTBIN/dtc" -I dtb -O dts "$dtb" 2>/dev/null | sed -n 's/.*model = "\(.*\)".*/\1/p' | head -1)"
	[ "$model" = "Lctech Pi F1C200s" ] \
		&& pass "DTB: model = \"$model\"" \
		|| fail "DTB: model = \"${model:-?}\" invece di \"Lctech Pi F1C200s\""
elif [ -f "$dtb" ]; then
	skip "dtc non disponibile: model del DTB non verificato"
else
	fail "DTB assente da $IMAGES"
fi

echo
[ "$rc" = 0 ] && echo "  tutto a posto." || echo "  ci sono controlli falliti."
echo
exit $rc
