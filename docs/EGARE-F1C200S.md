# EGARE F1C200S

Board con lo stesso SoC della FTVOGUE F1C200S (Allwinner F1C200s, `suniv`),
costruita **a parte** e confrontata con quella. La FTVOGUE è la board di
riferimento: hardware noto, su cui una feature si prova senza dubitare del
disegno. Se una cosa funziona sulla FTVOGUE e non sulla EGARE, il sospetto va
sull'hardware EGARE o sulle differenze di configurazione, che stanno tutte in
`external/board/egare-f1c200s/`.

Per tutto ciò che le due board hanno in comune (console UART1, DRAM, boot
chain, layout NAND, trappole) vale [BOARD-FACTS.md](BOARD-FACTS.md).
Le ragioni dell'organizzazione dei file sono nel
[design](superpowers/specs/2026-11-27-board-egare-f1c200s-design.md).

## Differenze hardware

### SPI NAND Winbond W25N02KV

* `xfel spinand` → `Found spi nand flash 'W25N02KV' with 268435456 bytes`
  (prova su board, 2026-11-27).
* Pagina 2048 B, OOB 128, blocco 128 KiB, 2048 blocchi: la stessa geometria
  del GD5F1GQ4xAYIG della FTVOGUE, dimensione doppia. Fonte: voce
  `W25N02KV` in `drivers/mtd/nand/spi/winbond.c` di U-Boot 2026.07 e
  Linux 6.12.111.
* Il kernel della FTVOGUE la vede: `/proc/mtd` → `mtd0: 10000000 00020000
  "spi0.0"` (boot da SD, 2026-11-27).
* `docs/flash-nand.sh` la scrive e la rilegge senza differenze (2026-11-27).
* **Boot da SPI NAND verificato** (prova su board, 2026-11-27) con
  l'immagine **FTVOGUE** (`output/images`) scritta da `docs/flash-nand.sh`:
  senza SD la catena è BROM → SPL patchato → U-Boot → `boot: NAND` → login,
  con `ubi0:rootfs` su `/`. `df -h /` dà 111.8M, come atteso con
  `MAXLEBCNT=1016` (valore FTVOGUE): UBIFS usa solo metà del chip.
* L'SPL patchato usa solo comandi SPI NAND standard (`0xFF`, `0x13`, `0x0F`,
  `0x03`).
* UBIFS è dimensionato per 256 MiB: `BR2_TARGET_ROOTFS_UBIFS_MAXLEBCNT=2040`
  (sulla FTVOGUE 1016).

### EEPROM ST M24C02-FMN

* Bus **i2c0**: SCK su **PE11** (pin 38 del QFN88), SDA su **PE12**
  (pin 37). Corrispondenza pin/porta: *Pin Map* del datasheet F1C200s V1.1.
* Indirizzo **0x50** (E0-E2 a GND).
* Prova su board, 2026-11-27, con un DTB di prova uguale a quello di questa
  build (senza driver AT24): `i2cdetect -y 0` vede `50`; `i2cdump` legge 256
  byte, tutti `ff` (EEPROM vergine); `i2cset`/`i2cget` sull'offset `0xff`
  scrivono e rileggono `0xa5`, poi ripristinato `0xff`.
* Il `.dtsi` del kernel definisce i2c0 solo su PD0/PD12: il gruppo
  `i2c0-pe-pins` è nel DTS EGARE.
* Da Linux: `/sys/bus/i2c/devices/0-0050/eeprom` (driver
  `CONFIG_EEPROM_AT24`). **Verificato** (prova su board, 2026-11-27) con la
  build EGARE avviata da SD (`root=/dev/mmcblk0p2`, model `EGARE F1C200S`):
  `hexdump -C` legge 256 byte, tutti `ff`; scrittura di `a5` all'offset 255
  con `dd`, riletto `a5`, poi ripristinato `ff`.

## Build e flash

Sempre con `O=output-egare`: senza, si sovrascrive la build FTVOGUE in
`output/`.

```bash
make O=output-egare egare_f1c200s_defconfig
make O=output-egare
make O=output-egare check

sudo dd if=output-egare/images/sdcard.img of=/dev/sdX bs=1M conv=fsync status=progress
./docs/flash-nand.sh output-egare/images      # board in FEL
```

`make O=output-egare check` controlla anche che i2c0 sia attivo nel DTB, che
ci sia `eeprom@50` e che il kernel abbia `CONFIG_EEPROM_AT24=y`.

## Da verificare su board

* Boot da SPI NAND con la build EGARE (`boot: NAND`, `ubi0:rootfs` su `/`).
  Quello con l'immagine FTVOGUE è verificato, vedi sopra.
* `df -h /` da NAND: attesi circa 230-240 MiB con `MAXLEBCNT=2040`.

## Lavoro futuro

L'EEPROM sarà l'EEPROM di identificazione del modulo. Due passi ancora da
progettare, ciascuno con il suo design:

1. schema dei 64 byte (identificazione, dati per esemplare, CRC16) e tool
   per scriverli;
2. U-Boot che legge l'EEPROM e sceglie DT e overlay della carrier.
