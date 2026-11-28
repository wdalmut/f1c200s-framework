# EGARE F1C200S rispetto alla specifica SODIMM 260-pin

Confronto fra tre cose:

* la **specifica** *Pinout SoM SODIMM 260-pin* (28/09/2026), che fissa la
  funzione di ogni pin del connettore;
* lo **schema della SoM** EGARE (KiCad, rev. 1 del 03/10/2026, fogli
  *connectors*, *CPU*, *USB*, *storage*), che dice quale pin del F1C200s
  arriva a quale pin del connettore;
* il **device tree** che costruiamo:
  [suniv-f1c200s-egare.dts](../external/board/egare-f1c200s/dts/allwinner/suniv-f1c200s-egare.dts),
  che include il DTS Lctech del kernel 6.12.111.

Serve a sapere quali funzioni del connettore la SoM porta e il software non
descrive ancora. Le differenze già verificate su board stanno in
[EGARE-F1C200S.md](EGARE-F1C200S.md).

Le funzioni dei pin sono controllate in
`drivers/pinctrl/sunxi/pinctrl-suniv-f1c100s.c` (Linux 6.12.111). Lo schema
è stato letto da un PDF a bassa risoluzione: le righe segnate con † vanno
ricontrollate su KiCad prima di scriverci un DT sopra.

Stato: 2026-11-28.

---

## Cosa descrive oggi il DT

Dal DTS Lctech: SPI NAND su spi0 (PC0-PC3), mmc0, uart1, MUSB, PHY USB.
Dal DTS EGARE: i2c0 su PE11/PE12 con l'EEPROM a 0x50, l'hog di `USB_SEL`
(PE4), la MUSB in host e, dal 2026-11-28, la console su uart0 (vedi sotto).

Fra i bus che la SoM porta al connettore, quelli descritti sono I2C0, UART0 e
UART1 (senza RTS/CTS).

## Mappa connettore → SoC → DT

| Connettore (spec) | Pin | SoC (schema SoM) | Nel DT | Da fare |
|---|---|---|---|---|
| UART0, console di debug | 205/207 | uart0, PE0/PE1 | ✅ console, verificata su board 2026-11-28 | — |
| UART1 + RTS/CTS (RS-485) | 180-186 | uart1, PA2/PA3 + PA0 (RTS) / PA1 (CTS) | attivo, solo TX/RX | gruppo PA0-PA3 (funzione `uart1`), `uart-has-rtscts` o RS-485 |
| UART2 | 190/192 | uart2, PD13/PD14 | manca | gruppo `uart2` + `&uart2` |
| I2C0 + EEPROM | 211/213 | i2c0, PE11/PE12 | ✅ | layout nvmem dei 64 byte (seriale, MAC) |
| I2C1 (touch) | 170/172 | i2c1, PD5/PD6 | manca | gruppo `i2c1` + `&i2c1` |
| I2C2 (camera) | 174/176 | i2c2, PD15/PD16 | manca | gruppo `i2c2` + `&i2c2` |
| SPI0 | 148-154 | **spi1**, PE7 (CS) / PE8 (MOSI) / PE9 (CLK) / PE10 (MISO) | manca | gruppo `spi1` + `&spi1` |
| SPI1 | 160-166 | — | — | NC |
| PWM0 | 210 † | **canale PWM1**, PE6 | `&pwm` disabilitato | gruppo `pwm1` + `&pwm` |
| GPIO0..4 | 223-233 | PD0-PD4 | senza nome | `gpio-line-names` |
| GPIO5..7 | 235-241 | PD17-PD19 | senza nome | `gpio-line-names` |
| GPIO8..19 | — | — | — | NC |
| SD0 | 111-127 | mmc0, PF0-PF5 | ✅ | — |
| SD0_CD# | 58 | PD21 | `broken-cd` (DTS Lctech) | `cd-gpios = <&pio 3 21 (GPIO_ACTIVE_LOW \| GPIO_PULL_UP)>` † |
| SD0_VSEL | 60 | — | — | NC: solo 3V3 |
| USB0 OTG | 39/41 | MUSB attraverso U7 | ✅ host fisso | dichiarare il vincolo (sotto) |
| USB0_VBUS (sense) | 22 | PE2, partitore R24/R25 | non descritto | niente (sotto) |
| USB0_ID | 24 | PE3, pull-up R23; Q2 lo porta a massa con PE4 alto | non descritto | niente (sotto) |
| USB1 | 45/47 | porta 3 del LAN9512 | ✅ attraverso l'hub | — |
| USB1_VBUS_EN / USB1_OC# | 26/28 | — | — | NC, vedi "Fuori dal DT" |
| ETH0 MDI0/MDI1 + LED + CT | 3-11, 6-10 | LAN9512 | ✅ funziona, MAC casuale | nodo USB + MAC dall'EEPROM |
| ETH1, DSI, CSI, I2S, CAN, ADC | — | — | — | NC: la SoM non ha display, camera né CAN |

Le funzioni pinctrl citate (`uart1`, `uart2`, `i2c1`, `i2c2`, `spi1`, `pwm1`)
esistono nel driver per quei pin. Il `.dtsi` suniv non ha i gruppi: vanno
scritti nel DTS EGARE, come già fatto per `i2c0-pe-pins`.

## Console su UART0

La specifica mette la console di debug su **UART0** (pin 205/207), che sulla
SoM è uart0 su PE0/PE1. Il DTS Lctech la mette su uart1 (PA2/PA3), che sulla
SoM va alla **UART1** del connettore (pin 180/182), cioè la porta RS-485.

Dal 2026-11-28 la build EGARE usa uart0:

| Stadio | Da dove prende la console | Dove si imposta |
|---|---|---|
| SPL | `CONFIG_CONS_INDEX=1` (configura PE0/PE1, `arch/arm/mach-sunxi/board.c`) | [uboot.fragment EGARE](../external/board/egare-f1c200s/uboot.fragment) |
| U-Boot proper | `stdout-path` → alias `serial0` del suo DT | [suniv-f1c200s-egare-u-boot.dtsi](../external/board/egare-f1c200s/uboot/suniv-f1c200s-egare-u-boot.dtsi), accodato con `CONFIG_DEVICE_TREE_INCLUDES` |
| Kernel | alias `serial0` → `ttyS0`, `console=ttyS0` nei bootargs | [DTS EGARE](../external/board/egare-f1c200s/dts/allwinner/suniv-f1c200s-egare.dts) |

Gli alias seguono i numeri del connettore: `ttyS0` è UART0 (console), `ttyS1`
è UART1. Bootargs e getty restano su `ttyS0` e non cambiano. Il DT di U-Boot
resta quello Lctech upstream più il `.dtsi`: la FTVOGUE non è toccata.
`make O=output-egare check` (sezione 7b) verifica che SPL, U-Boot e kernel
puntino alla stessa UART.

**Verificato su board** (2026-11-28): il boot esce sulla UART0 del
connettore.

## Numeri del connettore e numeri del SoC

La specifica nomina i bus con il numero del connettore. Due di questi non
coincidono con il numero del SoC:

* **SPI0 del connettore è `spi1` del SoC**, perché spi0 serve la SPI NAND di
  boot (come prescrive la specifica). In Linux è il bus 1
  (`/dev/spidev1.0`). Un alias `spi0 = &spi1` lo rinumererebbe, ma
  scambierebbe anche il nome della NAND, che i bootargs chiamano
  `mtdparts=spi0.0`: meglio lasciarlo e dichiararlo nel datasheet.
* **PWM0 del connettore è il canale 1** di `pwmchip0`.

UART e I2C invece coincidono: uartN e i2cN del SoC sono UARTn e I2Cn del
connettore.

## Note sulle righe da fare

**USB0_VBUS e USB0_ID.** Linux tiene PE4 alto: la CPU sta sempre dietro
l'hub LAN9512 e Q2 tiene `USB0_ID` a massa. Descrivere `usb0_id_det-gpios` e
`usb0_vbus_det-gpios` non servirebbe a niente. Il datasheet del modulo deve
dichiarare la limitazione che la specifica chiede ai moduli con Ethernet su
USB ("Vincolo per il modulo che usa un controller Ethernet USB"): in Linux non
c'è device mode. Il FEL invece resta, perché fino a U-Boot PE4 è basso.

**MAC dell'ETH0.** Si può fare tutto nel DT:

* sotto `&usb_otg`, il nodo dell'hub (`compatible = "usb424,9512"`,
  `reg = <1>`) e dentro quello dell'Ethernet (`"usb424,ec00"`, `reg = <1>`),
  come sul Raspberry Pi B;
* sul nodo Ethernet, `nvmem-cells` che punta a una cella fissa all'offset
  `0x2D` dell'EEPROM (offset della specifica).

Verificato nei sorgenti: la glue `drivers/usb/musb/sunxi.c` passa il nodo DT
al device `musb-hdrc`, quindi l'hub radice ha un `of_node` e i figli si
agganciano per `reg`. `smsc95xx` legge il MAC con
`platform_get_ethdev_address()`, che conosce `nvmem-cells`. Prima va definito
e scritto il contenuto dell'EEPROM (passo 1 del lavoro futuro in
[EGARE-F1C200S.md](EGARE-F1C200S.md)).

**SD0_CD#.** La specifica vuole il pull-up da 10 kΩ sulla SoM. Nel foglio CPU
non si vede (†): se manca, il flag `GPIO_PULL_UP` usa quello interno (il
pinctrl sunxi implementa `set_config`, quindi il flag funziona).

**Bus senza periferiche.** Il DT base del modulo dovrebbe descrivere i gruppi
pinctrl di tutti i bus del connettore. Il `status = "okay"` va messo solo per
quelli che la carrier usa davvero.

## Fuori dal DT

Differenze dalla specifica che si correggono nell'hardware:

* `USB1_VBUS_EN` e `USB1_OC#` (26/28) non sono collegati. `PRTCTL3` del
  LAN9512 potrebbe pilotarli.
* Sembrano non collegati † anche `RESET_OUT#` (195), `PWR_EN` (181),
  `PWR_GOOD` (183) e `BOOT_SEL1` (201). Sono T0: servono per la conformità.
* Il simbolo KiCad del connettore viene da una revisione precedente della
  specifica: ha ancora `UART3_TX/RX` su 194/196, `SPI0_CS1` su 156 e
  `CAM_PWDN` su 54, che ora sono `RSVD_B18/B19`, `RSVD_B20` e `RSVD_B17`. Sono
  tutti NC, quindi l'elettrico non cambia, ma il simbolo va rigenerato.

## Prossimo passo proposto

La specifica descrive il boot come DT base del modulo più overlay della
carrier. Oggi è tutto in un file. La divisione:

* `suniv-f1c200s-egare-som.dtsi`: quello che sta sulla SoM. NAND, EEPROM,
  LAN9512, PE4, console, e i gruppi pinctrl dei bus del connettore con
  `status = "disabled"`;
* il `.dts` della carrier, che include il `.dtsi` e accende i bus che usa.

Quando U-Boot leggerà l'EEPROM e caricherà gli overlay, il `.dts` della
carrier diventerà un overlay senza toccare il `.dtsi`.
