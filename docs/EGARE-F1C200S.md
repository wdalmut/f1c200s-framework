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
* **Boot da SPI NAND con la build EGARE verificato** (prova su board,
  2026-11-27): `./docs/flash-nand.sh output-egare/images`, poi senza SD
  login su `egare-f1c200s` con `ubi0:rootfs` su `/`. `df -h /` dà
  **221.5M**, il doppio dei 111.8M dell'immagine FTVOGUE: UBIFS usa tutto il
  chip. Il volume UBI ha circa 1996 LEB da 124 KiB (241.7 MiB); la
  differenza è l'overhead di UBIFS (indice, journal), nella stessa
  proporzione della FTVOGUE.
* Per mandare in FEL una board con un SPL valido in NAND e senza pulsante:
  dal prompt di U-Boot (`CONFIG_BOOTDELAY=2`) `mtd erase spi-nand0 0
  0x40000`, cioè i blocchi 0-1 dove la BROM cerca l'SPL; poi accensione
  senza SD. Rovinare kernel o rootfs non basta: SPL e U-Boot partono
  comunque.

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

### LAN9512 (hub USB + Ethernet 10/100)

* **`USB_SEL` = PE4** (pin 45 del QFN88) pilota i mux FSUSB42 U6/U7 e il gate
  di Q2. Alto: CPU → upstream del LAN9512, connettore OTG sulla porta 2
  dell'hub, `USB0_ID` a massa. Basso (default, pull-down sulla SoM): CPU
  diretta sul connettore OTG, come serve alla BROM per il FEL. Fonte: schema
  SoM, fogli CPU e USB.
* Il DTS EGARE tiene PE4 alto con un `gpio-hog` e mette la MUSB in
  `dr_mode = "host"` (il DTS Lctech la vuole `peripheral`). Da Linux la porta
  OTG è quindi solo host, attraverso l'hub.
* Kernel: `USB_USBNET`, `USB_NET_SMSC95XX`, `SMSC_PHY` (fragment EGARE), più la
  patch della FIFO MUSB descritta in BOARD-FACTS, "USB OTG (MUSB)". Senza la
  patch il link sale ma non si riceve nulla.
* **Verificato** (prova su board, 2026-11-28): hub `1-1` a 3 porte, Ethernet su
  `1-1.1` in high-speed, `Link is Up - 100Mbps/Full`, `ping` al gateway con
  risposta in ~1.2 ms.
* Niente EEPROM sul LAN9512 (pin EE* liberi): `smsc95xx` usa un **MAC casuale**
  a ogni avvio. Da risolvere con il MAC nella M24C02 o passato da U-Boot nel DT.
* Le coppie TX/RX verso l'RJ45 sono scambiate di proposito (nota sullo schema):
  le copre l'Auto-MDIX, che il driver `smsc` accende comunque scavalcando lo
  strap `AUTOMDIX_EN`.
* Diagnosi: nell'immagine c'è `ethtool`. `ethtool -d eth0` legge i registri
  del LAN9512 (`RX_FIFO_INF` a 0x18, `MAC_CR` a 0x100), `ethtool -t eth0` fa il
  loopback interno del PHY, `ethtool --phy-statistics eth0` gli errori di
  simbolo. `CONFIG_USB_MON` dà `/sys/kernel/debug/usb/usbmon/`.

#### Da correggere nella prossima revisione hardware

Tutto confrontato con il datasheet LAN9512 (DS00002304A, figura 2-2 e
tabelle 2-3, 2-6) e con lo schema Mavis, dove lo stesso circuito funziona.

* **L7 (SoM) va tolta.** Collega `VDD18CORE` a `VDD18ETHPLL`, mettendo in
  parallelo due regolatori interni diversi: per la figura 2-2 `VDD18ETHPLL` si
  alimenta solo da `VDD18USBPLL` attraverso la ferrite (L6). Tagliata sulla
  board di prova (2026-11-28): boot e Ethernet funzionano. Non era la causa
  della RX bloccata, ma è comunque un errore.
* **C50/C51 invertiti (SoM).** La figura 2-2 vuole 1,0 µF su `VDD18USBPLL`
  (l'uscita del regolatore) e 0,1 µF su `VDD18ETHPLL`; lo schema ha il
  contrario (come Mavis, che funziona lo stesso).
* **LED dell'RJ45 (carrier) al contrario.** `nLNKA_LED`/`nSPD_LED` sono OD12
  attivi bassi: il LED va da 3V3 (anodo) al pin attraverso la resistenza, come
  su Mavis. Sulla carrier l'anodo va al pin e il catodo a GND: i LED restano
  accesi debolmente dal pull-up interno. Solo estetico.
* **Nomi delle net dei LED (carrier).** Nel foglio Ethernet `ETH0_LNK`/`ETH0_ACT`,
  sul connettore `ETH0_LNK_LED`/`ETH0_SPD_LED`: se le label non coincidono i
  LED sono scollegati. "ACT" in realtà è `nSPD_LED` (velocità).
* **Da verificare: pin TEST.** Tabella 2-3: TEST1 (13) e TEST4 (47) scollegati,
  TEST2 (**34**) a VSS, TEST3 (40) a VDD33IO. Nel simbolo sembra esserci
  "TEST2 33", e il pin 33 è VDD33IO.

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

## Lavoro futuro

L'EEPROM sarà l'EEPROM di identificazione del modulo. Due passi ancora da
progettare, ciascuno con il suo design:

1. schema dei 64 byte (identificazione, dati per esemplare, CRC16) e tool
   per scriverli;
2. U-Boot che legge l'EEPROM e sceglie DT e overlay della carrier.
