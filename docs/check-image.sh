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

# --- 0. quale board ----------------------------------------------------------
# Il DTB non e' scritto qui: e' l'unico *.dtb in images/, e da lui dipende
# il resto (FAT, bootcmd, model, /boot). Zero o piu' DTB vuol dire una build
# configurata male (per esempio INTREE_DTS_NAME rimasto insieme a
# CUSTOM_DTS_DIR): meglio fermarsi che sceglierne uno a caso.
dtbs=()
for f in "$IMAGES"/*.dtb; do [ -f "$f" ] && dtbs+=("$(basename "$f")"); done
case "${#dtbs[@]}" in
	1) DTB_NAME="${dtbs[0]}" ;;
	0) fail "nessun DTB in $IMAGES"; exit 1 ;;
	*) fail "piu' DTB in $IMAGES: ${dtbs[*]}"; exit 1 ;;
esac
# La console: FTVOGUE su uart1 (PA2/PA3, header TTL), EGARE su uart0
# (PE0/PE1, UART0 del connettore SODIMM). CONS_INDEX vale per l'SPL, il
# nodo per U-Boot proper e kernel (alias serial0 / stdout-path).
case "$DTB_NAME" in
	suniv-f1c200s-lctech-pi.dtb)
		MODEL="Lctech Pi F1C200s"; CONS_INDEX=2; CONSOLE_NODE=serial@1c25400 ;;
	suniv-f1c200s-egare.dtb)
		MODEL="EGARE F1C200S";     CONS_INDEX=1; CONSOLE_NODE=serial@1c25000 ;;
	*) fail "DTB sconosciuto: $DTB_NAME"; exit 1 ;;
esac
echo "  board: $MODEL ($DTB_NAME)"
echo

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
	echo "$listing" | grep -qi "$DTB_NAME" \
		&& pass "DTB presente nella FAT" || fail "DTB assente dalla FAT"
else
	skip "mtools non disponibile: contenuto della FAT non verificato"
fi

# --- 4. configurazione U-Boot ------------------------------------------------
ucfg="$(ls -d "$BUILD"/uboot-*/.config 2>/dev/null | head -1)"
if [ -n "$ucfg" ] && [ -f "$ucfg" ]; then
	chk() { grep -q "^$1\$" "$ucfg" && pass "u-boot: $1" || fail "u-boot: atteso $1"; }
	chk "CONFIG_CONS_INDEX=$CONS_INDEX"
	chk 'CONFIG_SUNXI_MINIMUM_DRAM_MB=64'
	# DT di U-Boot: la base e' quella Lctech per tutte le board; la EGARE ci
	# accoda il suo .dtsi (console su uart0), controllato nella sezione 7.
	chk 'CONFIG_DEFAULT_DEVICE_TREE="allwinner/suniv-f1c200s-lctech-pi"'
	chk 'CONFIG_SPL_SPI_SUNXI=y'
	chk 'CONFIG_SPL_SPI_SUNXI_NAND=y'
	chk 'CONFIG_SPL_SPI_SUNXI_NAND_ASSUMED_PAGESIZE=0x800'
	chk 'CONFIG_SYS_SPI_U_BOOT_OFFS=0x48000'
	chk 'CONFIG_MTD_SPI_NAND=y'
	chk 'CONFIG_CMD_UBI=y'
	chk 'CONFIG_CMD_UBIFS=y'
	chk 'CONFIG_ENV_IS_NOWHERE=y'
	# ENV_IS_IN_FAT e' il default di sunxi: un uboot.env sulla FAT (basta un
	# saveenv) sostituirebbe in silenzio il bootcmd compilato.
	chk '# CONFIG_ENV_IS_IN_FAT is not set'
	chk 'CONFIG_MTDPARTS_DEFAULT="mtdparts=spi0.0:1M(boot),-(ubi)"'
	grep -q '^CONFIG_BOOTCOMMAND=.*ubi part ubi' "$ucfg" \
		&& pass "u-boot: bootcmd ha il ramo NAND (ubi part ubi)" \
		|| fail "u-boot: il bootcmd non ha il ramo NAND"
	grep -q '^CONFIG_BOOTCOMMAND=.*load mmc 0:1' "$ucfg" \
		&& pass "u-boot: bootcmd carica da mmc 0:1" \
		|| fail "u-boot: il bootcmd non carica da mmc 0:1"
	# Il DTB va caricato in entrambi i rami (SD e NAND). Un fragment che punta
	# al DTB di un'altra board si scoprirebbe solo con la board che non parte.
	# grep -o | wc -l e non grep -c: grep -c conta le righe, non le occorrenze.
	n="$(grep '^CONFIG_BOOTCOMMAND=' "$ucfg" | grep -o "$DTB_NAME" | wc -l)"
	[ "$n" = 2 ] \
		&& pass "u-boot: bootcmd carica $DTB_NAME in entrambi i rami" \
		|| fail "u-boot: $DTB_NAME compare $n volte nel bootcmd invece di 2"
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
	chk 'CONFIG_SPI_SUN6I=y'
	chk 'CONFIG_MTD_SPI_NAND=y'
	chk 'CONFIG_MTD_CMDLINE_PARTS=y'
	chk 'CONFIG_MTD_UBI=y'
	chk 'CONFIG_UBIFS_FS=y'
	# 3 UART, non 0: con RUNTIME_UARTS=0 la console 8250 non si registra.
	chk 'CONFIG_SERIAL_8250_RUNTIME_UARTS=3'
	chk '# CONFIG_LEGACY_PTYS is not set'
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
	# E niente '^': in strings, bootcmd= e' attaccato alla stringa che lo
	# precede nel binario.
	n="$(strings "$IMAGES/u-boot.bin" | grep -c 'bootcmd=if test -e mmc 0:1 zImage')"
	[ "${n:-0}" -ge 1 ] \
		&& pass "bootcmd SD/NAND presente nell'ambiente compilato in u-boot.bin" \
		|| fail "bootcmd non trovato in u-boot.bin: il fragment non e' stato applicato"
else
	skip "u-boot.bin assente"
fi

# --- 7. il DTB e' quello della board -----------------------------------------
dtb="$IMAGES/$DTB_NAME"
if [ -f "$dtb" ] && [ -x "$HOSTBIN/dtc" ]; then
	model="$("$HOSTBIN/dtc" -I dtb -O dts "$dtb" 2>/dev/null | sed -n 's/.*model = "\(.*\)".*/\1/p' | head -1)"
	[ "$model" = "$MODEL" ] \
		&& pass "DTB: model = \"$model\"" \
		|| fail "DTB: model = \"${model:-?}\" invece di \"$MODEL\""
elif [ -f "$dtb" ]; then
	skip "dtc non disponibile: model del DTB non verificato"
else
	fail "DTB assente da $IMAGES"
fi

# --- 7b. console: stessa UART in SPL, U-Boot e kernel ------------------------
# L'SPL la prende da CONS_INDEX (sezione 4), U-Boot proper e kernel dall'alias
# serial0 del loro DT. Se uno dei tre diverge, la console si interrompe a
# meta' boot: SPL visibile e poi silenzio, o U-Boot visibile e kernel muto.
console_chk() {	# $1 = etichetta, $2 = dtb
	local dts alias
	dts="$("$HOSTBIN/dtc" -I dtb -O dts "$2" 2>/dev/null)"
	alias="$(echo "$dts" | sed -n 's/^[[:space:]]*serial0 = "\(.*\)";/\1/p' | head -1)"
	[ "$alias" = "/soc/$CONSOLE_NODE" ] \
		&& pass "$1: serial0 = $alias" \
		|| fail "$1: serial0 = \"${alias:-?}\" invece di /soc/$CONSOLE_NODE"
	echo "$dts" | sed -n "/$CONSOLE_NODE {/,/^\t\t};/p" | grep -q 'status = "okay"' \
		&& pass "$1: $CONSOLE_NODE attivo" \
		|| fail "$1: $CONSOLE_NODE non attivo"
}
udtb="$(ls -d "$BUILD"/uboot-*/u-boot.dtb 2>/dev/null | head -1)"
if [ -x "$HOSTBIN/dtc" ]; then
	[ -f "$dtb" ] && console_chk "DTB kernel" "$dtb"
	if [ -n "$udtb" ] && [ -f "$udtb" ]; then
		console_chk "DTB U-Boot" "$udtb"
	else
		skip "u-boot.dtb non trovato: console di U-Boot proper non verificata"
	fi
else
	skip "dtc non disponibile: console nei DT non verificata"
fi

# --- 8. l'SPL contiene davvero il lettore SPI NAND ---------------------------
# Le patch stanno in external/.../patches/uboot/. Se un bump di U-Boot le
# rendesse inapplicabili la build fallirebbe; se invece venissero saltate
# (per esempio spostate in una sottodirectory di versione) l'SPL uscirebbe
# senza lettore NAND, e lo si scoprirebbe solo con la board muta.
smap="$(ls -d "$BUILD"/uboot-*/spl/u-boot-spl.map 2>/dev/null | head -1)"
if [ -n "$smap" ] && [ -f "$smap" ]; then
	n="$(grep -c 'spi_load_read_nand' "$smap")"
	[ "${n:-0}" -ge 1 ] \
		&& pass "SPL: lettore SPI NAND presente (spi_load_read_nand)" \
		|| fail "SPL: manca spi_load_read_nand — patch non applicate?"
else
	skip "map dell'SPL non trovata: build fatta altrove?"
fi

# --- 8b. FIFO della MUSB entro i 4 KiB di SRAM D -----------------------------
# Senza patches/linux/0001-* il driver dispone 5184 byte di FIFO su 4 KiB:
# gli endpoint oltre 4 KiB non funzionano e un bulk-in li' non si completa
# mai (LAN9512 EGARE: link su, TX ok, RX a 0 senza errori).
musbc="$(ls -d "$BUILD"/linux-*/drivers/usb/musb/sunxi.c 2>/dev/null | head -1)"
if [ -n "$musbc" ] && [ -f "$musbc" ]; then
	grep -A1 'suniv_f1c100s_musb_cfg = {' "$musbc" | grep -q 'sunxi_musb_hdrc_config_suniv' \
		&& pass "kernel: FIFO MUSB suniv entro 4 KiB (patch linux applicata)" \
		|| fail "kernel: FIFO MUSB suniv a 5 endpoint da 512 — patch linux non applicata?"
else
	skip "sorgenti del kernel non trovati: FIFO MUSB non verificata"
fi

# --- 9. U-Boot sta nella zona boot della NAND --------------------------------
# flash-nand.sh scrive u-boot-sunxi-with-spl.bin lineare a 0x40000; la
# partizione UBI parte a 0x100000. Se U-Boot cresce oltre, il primo PEB di
# UBI viene sovrascritto e nessuno se ne accorge fino all'attach.
# L'SPL cerca u-boot.img a 0x48000, cioe' a +0x8000 nel file: se un bump
# sposta quell'offset, li' c'e' il vuoto.
ubin="$IMAGES/u-boot-sunxi-with-spl.bin"
if [ -f "$ubin" ]; then
	size="$(stat -c %s "$ubin")"
	[ $((0x40000 + size)) -le $((0x100000)) ] \
		&& pass "NAND: u-boot-sunxi-with-spl.bin ($size B) finisce prima di 0x100000" \
		|| fail "NAND: u-boot-sunxi-with-spl.bin ($size B) sfora in UBI"
	magic="$(od -An -tx1 -j $((0x8000)) -N4 "$ubin" | tr -d ' ')"
	[ "$magic" = 27051956 ] \
		&& pass "NAND: u-boot.img a +0x8000 nel file (flash 0x48000)" \
		|| fail "NAND: a +0x8000 c'e' '$magic' invece dell'header uImage"
else
	fail "u-boot-sunxi-with-spl.bin assente"
fi

# --- 10. rootfs.ubi ha la geometria della NAND -------------------------------
# GD5F1GQ4xA e W25N02KV: pagina 2048, niente sub-page. Con -m 2048 -s 2048 l'header EC
# dice VID header a 2048 e dati a 4096. Una geometria sbagliata produce
# un'immagine che ubinize accetta e che il kernel rifiuta all'attach.
ubi="$IMAGES/rootfs.ubi"
if [ -f "$ubi" ]; then
	m="$(dd if="$ubi" bs=1 count=4 2>/dev/null)"
	[ "$m" = 'UBI#' ] && pass "rootfs.ubi: magic UBI#" || fail "rootfs.ubi: magic '$m'"
	offs="$(od -An -tx1 -j16 -N8 "$ubi" | tr -d ' \n')"
	[ "$offs" = 0000080000001000 ] \
		&& pass "rootfs.ubi: VID header a 2048, dati a 4096" \
		|| fail "rootfs.ubi: offset VID/dati = $offs (attesi 0x800 / 0x1000)"
	size="$(stat -c %s "$ubi")"
	[ "$size" -le $((0x8000000 - 0x100000)) ] \
		&& pass "rootfs.ubi ($size B) sta nella partizione ubi" \
		|| fail "rootfs.ubi ($size B) non sta nei 127 MiB della partizione ubi"
else
	fail "rootfs.ubi assente"
fi

# --- 11. kernel e DTB nel rootfs, dove li cerca il ramo NAND del bootcmd ----
tgt="$IMAGES/../target/boot"
for f in zImage "$DTB_NAME"; do
	[ -f "$tgt/$f" ] && pass "rootfs: /boot/$f" || fail "rootfs: manca /boot/$f"
done

# --- 12. EGARE: EEPROM M24C02 su i2c0 ----------------------------------------
# Il DTS EGARE attiva i2c0 su PE11/PE12 con la EEPROM a 0x50; senza
# EEPROM_AT24 il nodo c'e' ma /sys/bus/i2c/devices/0-0050/eeprom no.
if [ "$DTB_NAME" = suniv-f1c200s-egare.dtb ]; then
	if [ -x "$HOSTBIN/dtc" ]; then
		i2c0="$("$HOSTBIN/dtc" -I dtb -O dts "$dtb" 2>/dev/null \
			| sed -n '/i2c@1c27000 {/,/^\t\t};/p')"
		echo "$i2c0" | grep -q 'status = "okay"' \
			&& pass "DTB: i2c0 attivo" || fail "DTB: i2c0 non attivo"
		echo "$i2c0" | grep -q 'eeprom@50 {' \
			&& pass "DTB: eeprom@50 su i2c0" || fail "DTB: manca eeprom@50 su i2c0"
	else
		skip "dtc non disponibile: i2c0 ed EEPROM non verificati"
	fi
	if [ -n "$kcfg" ] && [ -f "$kcfg" ]; then
		grep -q '^CONFIG_EEPROM_AT24=y$' "$kcfg" \
			&& pass "kernel: CONFIG_EEPROM_AT24=y" || fail "kernel: atteso CONFIG_EEPROM_AT24=y"
	else
		skip "config del kernel non trovata: EEPROM_AT24 non verificato"
	fi

	# --- 12b. EGARE: UART1 del connettore con RTS/CTS -----------------------
	# Il DTS Lctech mette uart1 solo su PA2/PA3: senza il gruppo EGARE la
	# porta funziona ma RTS (PA0) e CTS (PA1) restano GPIO, e un transceiver
	# RS-485 sulla carrier non vede mai il DE.
	if [ -x "$HOSTBIN/dtc" ]; then
		dts="$("$HOSTBIN/dtc" -I dtb -O dts "$dtb" 2>/dev/null)"
		uart1="$(echo "$dts" | sed -n '/serial@1c25400 {/,/^\t\t};/p')"
		echo "$uart1" | grep -q 'uart-has-rtscts' \
			&& pass "DTB: uart1 con uart-has-rtscts" || fail "DTB: uart1 senza uart-has-rtscts"
		ph="$(echo "$uart1" | sed -n 's/.*pinctrl-0 = <\(0x[0-9a-f]*\)>;.*/\1/p')"
		pins="$(echo "$dts" | grep -B3 "phandle = <${ph:-none}>;" | sed -n 's/.*pins = \(.*\);/\1/p')"
		[ "$pins" = '"PA0", "PA1", "PA2", "PA3"' ] \
			&& pass "DTB: uart1 su PA0-PA3 (TX, RX, RTS, CTS)" \
			|| fail "DTB: uart1 su ${pins:-?} invece di PA0-PA3"
	else
		skip "dtc non disponibile: pin di uart1 non verificati"
	fi

	# --- 12c. EGARE: bus del connettore -----------------------------------
	# Per ogni bus: alias (numero in Linux = numero del connettore, tranne
	# SPI0 che e' spi1), nodo attivo, pin. I nodi sono disabilitati nel
	# .dtsi: senza il DTS EGARE il bus non esiste e nessuno se ne accorge.
	bus_chk() {	# $1 = alias, $2 = nodo, $3 = pin attesi, $4 = etichetta
		local node ph pins
		echo "$dts" | grep -q "^[[:space:]]*$1 = \"/soc/$2\";" \
			&& pass "DTB: $1 = $2 ($4)" || fail "DTB: $1 non punta a $2 ($4)"
		node="$(echo "$dts" | sed -n "/$2 {/,/^\t\t};/p")"
		echo "$node" | grep -q 'status = "okay"' \
			&& pass "DTB: $2 attivo" || fail "DTB: $2 non attivo"
		ph="$(echo "$node" | sed -n 's/.*pinctrl-0 = <\(0x[0-9a-f]*\)>;.*/\1/p')"
		pins="$(echo "$dts" | grep -B3 "phandle = <${ph:-none}>;" | sed -n 's/.*pins = \(.*\);/\1/p')"
		[ "$pins" = "$3" ] \
			&& pass "DTB: $2 su $3" || fail "DTB: $2 su ${pins:-?} invece di $3"
	}
	if [ -x "$HOSTBIN/dtc" ]; then
		dts="$("$HOSTBIN/dtc" -I dtb -O dts "$dtb" 2>/dev/null)"
		bus_chk serial2 serial@1c25800 '"PD13", "PD14"' 'UART2 del connettore'
		bus_chk i2c1 i2c@1c27400 '"PD5", "PD6"' 'I2C1 del connettore'
		bus_chk i2c2 i2c@1c27800 '"PD15", "PD16"' 'I2C2 del connettore'
		bus_chk spi1 spi@1c06000 '"PE7", "PE8", "PE9", "PE10"' 'SPI0 del connettore'
		# La NAND deve restare il bus 0: i bootargs dicono mtdparts=spi0.0.
		echo "$dts" | grep -q '^[[:space:]]*spi0 = "/soc/spi@1c05000";' \
			&& pass "DTB: spi0 = spi@1c05000 (SPI NAND, mtdparts=spi0.0)" \
			|| fail "DTB: spi0 non punta alla SPI NAND: mtdparts=spi0.0 rischia di non trovarla"
	else
		skip "dtc non disponibile: bus del connettore non verificati"
	fi

	# --- 13. EGARE: LAN9512 dietro la MUSB ----------------------------------
	# Con la MUSB in peripheral (default Lctech) o PE4 basso il LAN9512 non
	# si vede, e senza smsc95xx si vede ma eth0 non compare: tutto in silenzio.
	if [ -x "$HOSTBIN/dtc" ]; then
		dts="$("$HOSTBIN/dtc" -I dtb -O dts "$dtb" 2>/dev/null)"
		echo "$dts" | sed -n '/usb@1c13000 {/,/^\t\t};/p' | grep -q 'dr_mode = "host"' \
			&& pass "DTB: MUSB in host" || fail "DTB: MUSB non in host (LAN9512 invisibile)"
		echo "$dts" | sed -n '/usb-sel-hog {/,/};/p' | grep -q 'output-high' \
			&& pass "DTB: hog usb-sel (PE4) alto" || fail "DTB: manca l'hog usb-sel su PE4"
	else
		skip "dtc non disponibile: MUSB e USB_SEL non verificati"
	fi
	if [ -n "$kcfg" ] && [ -f "$kcfg" ]; then
		for o in USB_USBNET USB_NET_SMSC95XX SMSC_PHY; do
			grep -q "^CONFIG_$o=y$" "$kcfg" \
				&& pass "kernel: CONFIG_$o=y" || fail "kernel: atteso CONFIG_$o=y"
		done
	else
		skip "config del kernel non trovata: smsc95xx non verificato"
	fi
fi

echo
[ "$rc" = 0 ] && echo "  tutto a posto." || echo "  ci sono controlli falliti."
echo
exit $rc
