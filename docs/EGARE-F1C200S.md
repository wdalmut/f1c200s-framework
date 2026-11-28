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

Il confronto con la specifica del connettore SODIMM 260-pin, e cosa manca
ancora nel DT, sta in [EGARE-SPEC-SODIMM.md](EGARE-SPEC-SODIMM.md).

## Differenze hardware

### Console su UART0 (PE0/PE1)

* La specifica SODIMM mette la console di debug sulla UART0 del connettore
  (pin 205/207), che sulla SoM è **uart0 su PE0/PE1** (pin 49/48 del QFN88;
  schema SoM, foglio CPU). uart1 (PA2/PA3), la console della FTVOGUE, qui va
  alla UART1 del connettore (pin 180/182), la porta RS-485.
* SPL: `CONFIG_CONS_INDEX=1` nel [uboot.fragment](../external/board/egare-f1c200s/uboot.fragment).
  U-Boot proper: `serial0 = &uart0` nel
  [.dtsi](../external/board/egare-f1c200s/uboot/suniv-f1c200s-egare-u-boot.dtsi)
  accodato al DT Lctech con `CONFIG_DEVICE_TREE_INCLUDES`. Kernel:
  `serial0 = &uart0`, `serial1 = &uart1` nel DTS EGARE. `ttyS0` resta la
  console, quindi bootargs e getty non cambiano; `ttyS1` è la UART1 del
  connettore.
* `make O=output-egare check` verifica `CONS_INDEX=1` e che l'alias `serial0`
  punti a `serial@1c25000` sia nel DTB del kernel sia in `u-boot.dtb`
  (2026-11-28: tutto ok).
* **Verificato** (prova su board, 2026-11-28): con la build EGARE il boot
  esce sulla UART0 del connettore.

### UART1 del connettore con RTS/CTS

* uart1 usa PA0 (RTS), PA1 (CTS), PA2 (TX), PA3 (RX), tutti con la funzione
  `uart1` (`pinctrl-suniv-f1c100s.c`), e ha `uart-has-rtscts`. È `ttyS1`.
* Sulla carrier c'è solo l'header: la modalità RS-485 non è accesa nel DT.
  Dettagli in [EGARE-SPEC-SODIMM.md](EGARE-SPEC-SODIMM.md#uart1-con-rtscts).
* **Da provare su board.**

### UART2 del connettore

* uart2 su PD13 (TX) / PD14 (RX), funzione `uart2`, solo TX/RX come vuole la
  specifica: PD15/PD16, i suoi RTS/CTS, sono I2C2. È `ttyS2`
  (`serial2 = &uart2`).
* **Da provare su board.**

### I2C1, I2C2 e SPI0 del connettore

* i2c1 su PD5/PD6 (`/dev/i2c-1`), i2c2 su PD15/PD16 (`/dev/i2c-2`), spi1 su
  PE7-PE10 (bus SPI 1, la SPI0 del connettore). Solo i controller: la carrier
  non ha periferiche su questi bus.
* Alias `spi0 = &spi0` / `spi1 = &spi1`: la NAND resta sul bus 0, come dicono
  i bootargs (`mtdparts=spi0.0`), qualunque sia l'ordine di probe.
* Dettagli in [EGARE-SPEC-SODIMM.md](EGARE-SPEC-SODIMM.md#i2c1-i2c2-e-spi0).
  **Da provare su board** (`i2cdetect -y 1`, `i2cdetect -y 2`).

### PWM0 e GPIO del connettore

* PWM0 del connettore = canale 1 del PWM su PE6: `pwmchip0` canale 1. Non
  esiste un alias che lo rinumeri.
* GPIO0..7 = PD0-PD4, PD17-PD19, con il nome in `gpio-line-names`; nell'immagine
  ci sono i tool di libgpiod (`gpioinfo`, `gpioget`, `gpioset`).
* Dettagli in [EGARE-SPEC-SODIMM.md](EGARE-SPEC-SODIMM.md#pwm0-e-gpio).
* **Verificato** (prova su board, 2026-11-28): GPIO0..7. **PWM0 da provare.**

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
* È l'EEPROM di identificazione del modulo (schema v1.0,
  [EEPROM-ID.md](EEPROM-ID.md)): `som-id` nel rootfs la legge e la scrive,
  e il DTS ne dichiara le celle nvmem (`/sys/bus/nvmem/devices/*/cells/`).
  **Verificato** (prova su board, 2026-11-28): `som-id` funziona sulla
  EGARE con la build EGARE avviata da SD (package `som-id` 1.0.0, comandi
  di [EEPROM-ID.md](EEPROM-ID.md)). Prodotto e MAC scritti sono valori di
  prova.

### Porte USB

Il F1C200s ha una sola USB (MUSB OTG). Sulla EGARE passa dai mux FSUSB42
U6/U7 comandati da `USB_SEL` (PE4), e le porte della carrier si dividono così
(schema SoM, foglio USB; schema carrier, foglio USB):

| Porta | Collegamento | PE4 basso: BROM, SPL, U-Boot | PE4 alto: Linux |
|---|---|---|---|
| USB-C (CN4) | `USB0_DP/DM`, pin 39/41 del SODIMM → U7 | diretta sulla CPU, modalità device: FEL | porta 2 dell'hub LAN9512 (`1-1.2`) |
| USB-A (CN8) | `USB1_DP/DM`, pin 45/47 del SODIMM → `USBDP3/USBDM3` del LAN9512 | non raggiungibile: il LAN9512 è staccato dalla CPU | porta 3 dell'hub (`1-1.3`) |
| Ethernet | interna al LAN9512 | non raggiungibile | porta 1 dell'hub (`1-1.1`, verificata) |

* PE4 lo porta alto solo il kernel (hog nel DTS EGARE): fino a U-Boot compreso
  vale il pull-down, quindi la USB-C resta la porta del FEL.
* Da Linux entrambe le porte sono host, attraverso l'hub. I numeri `1-1.2` e
  `1-1.3` vengono dallo schema; finora è verificata solo la `1-1.1`.
* **USB-C:** CC1/CC2 con 5,1 kΩ verso GND, cioè la board si presenta come
  sink; il VBUS entra su `VSYS` attraverso D3. È un ingresso di alimentazione:
  in host la porta non alimenta il dispositivo collegato, che deve essere
  autoalimentato (o passare da un hub alimentato).
* **USB-A:** VBUS da `VSYS` (dalla prossima revisione della carrier), sempre
  acceso: `PRTCTL3` del LAN9512 non è collegato e il suo pull-up interno tiene
  la porta senza sovracorrente.
* **Niente tastiere né mouse**: la MUSB suniv ha due soli slot per gli
  endpoint interrupt, occupati dall'hub del LAN9512 e da `smsc95xx`
  (BOARD-FACTS, "USB OTG (MUSB)"). Un dispositivo HID sulla USB-A ottiene
  `hwep alloc failed`. I dispositivi solo bulk (una chiavetta, con
  `USB_STORAGE`, che oggi manca nel kernel) dividono EP1 con l'Ethernet.

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
  patch, o con un layout che usa EP4/EP5, il link sale ma non si riceve nulla,
  oppure il cambio di link non viene mai notificato.
* **Verificato** (prova su board, 2026-11-28): hub `1-1` a 3 porte, Ethernet su
  `1-1.1` in high-speed, `Link is Up - 100Mbps/Full`, `ping` al gateway con
  risposta in ~1.2 ms.
* Niente EEPROM sul LAN9512 (pin EE* liberi): senza altro `smsc95xx` usa un
  **MAC casuale** a ogni avvio. Il DTS EGARE gli dà quello della M24C02 con
  `nvmem-cells` (cella `mac-address@10`, alias `ethernet0`):
  [EEPROM-ID.md](EEPROM-ID.md). **Verificato** (prova su board,
  2026-11-28, avvio da SD): `ip a` mostra su `eth0` lo stesso MAC che
  `som-id verify` legge come `mac0`; at24 si registra a 1,18 s, il LAN9512
  a 2,41 s. Il messaggio `musb-sunxi 1c13000.usb: Failed to create device
  link (0x180) with 1c27000.i2c:eeprom@50:nvmem-layout` è innocuo:
  fw_devlink prova a legare la MUSB al nodo `nvmem-layout`, che non è un
  device; il MAC arriva lo stesso.
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

L'EEPROM è l'EEPROM di identificazione del modulo. Due passi:

1. ~~schema dei 64 byte e tool per scriverli~~: fatto, schema v1.0 e tool
   `som-id` ([EEPROM-ID.md](EEPROM-ID.md));
2. U-Boot che legge l'EEPROM (`ethaddr`, `serial#`) e sceglie DT e overlay
   della carrier. Per ora non serve: il MAC dell'ETH0 arriva a Linux via
   `nvmem-cells`. La scelta della carrier richiede un'EEPROM sulla carrier:
   quella del modulo non la identifica.
