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
(PE4), la MUSB in host e, dal 2026-11-28, le tre UART: console su uart0 (vedi
sotto), uart1 con RTS/CTS, uart2 su PD13/PD14; i2c1 e i2c2; spi1. Gli alias
`serial0..2` e `i2c0..2` seguono i numeri del connettore (`ttyS0..2`,
`/dev/i2c-0..2`); `spi0`/`spi1` fissano la NAND sul bus 0.

Fra le funzioni che la SoM porta al connettore, quelle descritte sono le tre
UART (UART0 console, UART1 con RTS/CTS, UART2), i tre I2C, SPI0, PWM0 e i
GPIO0..7 con il loro nome. Manca il card detect di SD0.

## Mappa connettore → SoC → DT

| Connettore (spec) | Pin | SoC (schema SoM) | Nel DT | Da fare |
|---|---|---|---|---|
| UART0, console di debug | 205/207 | uart0, PE0/PE1 | ✅ console, verificata su board 2026-11-28 | — |
| UART1 + RTS/CTS (RS-485) | 180-186 | uart1, PA2/PA3 + PA0 (RTS) / PA1 (CTS) | ✅ PA0-PA3, `uart-has-rtscts` (2026-11-28) | prova su board; RS-485 nel DT della carrier che monta il transceiver |
| UART2 | 190/192 | uart2, PD13 (TX) / PD14 (RX) | ✅ `ttyS2` (2026-11-28) | prova su board |
| I2C0 + EEPROM | 211/213 | i2c0, PE11/PE12 | ✅ | layout nvmem dei 64 byte (seriale, MAC) |
| I2C1 (touch) | 170/172 | i2c1, PD5 (SCK) / PD6 (SDA), pull-up R26/R17 | ✅ `/dev/i2c-1` (2026-11-28) | prova su board |
| I2C2 (camera) | 174/176 | i2c2, PD15 (SCK) / PD16 (SDA), pull-up R27/R18 | ✅ `/dev/i2c-2` (2026-11-28) | prova su board |
| SPI0 | 148-154 | **spi1**, PE7 (CS) / PE8 (MOSI) / PE9 (CLK) / PE10 (MISO) | ✅ bus 1, senza periferiche (2026-11-28) | periferiche nel DT della carrier; prova su board |
| SPI1 | 160-166 | — | — | NC |
| PWM0 | 210 | **canale 1** del PWM, PE6 | ✅ `pwmchip0` canale 1, verificato su board 2026-11-28 | — |
| GPIO0..4 | 223-233 | PD0-PD4 | ✅ `gpio-line-names`, verificato su board 2026-11-28 | — |
| GPIO5..7 | 235-241 | PD17-PD19 | ✅ `gpio-line-names`, verificato su board 2026-11-28 | — |
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

Il `.dtsi` suniv non ha i gruppi pinctrl di questi pin: sono tutti nel DTS
EGARE.

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

## UART1 con RTS/CTS

La UART1 del connettore è la porta che la specifica pensa per l'RS-485: RTS
pilota il DE del transceiver. Sulla carrier EGARE dietro i pin 180-186 c'è
solo un header, nessun transceiver. Il DTS EGARE quindi descrive soltanto
quello che sta sulla SoM:

* gruppo `uart1-pa-rtscts-pins` con PA0 (RTS), PA1 (CTS), PA2 (TX), PA3 (RX),
  funzione `uart1`, al posto di `uart1_pa_pins` del DTS Lctech, che ha solo
  PA2/PA3;
* `uart-has-rtscts`.

La modalità RS-485 non è accesa nel DT. Un'applicazione la accende con
l'ioctl `TIOCSRS485`. `8250_dw` la emula via software (em485, toggling di
RTS) se la UART non ha l'RS-485 in hardware (`dw8250_setup_port()` in
`8250_dwlib.c`). Una carrier con il transceiver la accende nel suo DT con
`linux,rs485-enabled-at-boot-time`, e se serve `rs485-rts-active-low`.

CTS non ha pull-up né sulla SoM né nel DT: con l'header scollegato, attivare
il flow control (`crtscts`) può bloccare la trasmissione.

`make O=output-egare check` (sezione 12b) verifica gruppo e proprietà nel
DTB. **Da provare su board**, per esempio con un loopback sull'header (TX su
RX, RTS su CTS).

## I2C1, I2C2 e SPI0

Sono bus del connettore senza periferiche sulla carrier EGARE di oggi. Il DTS
accende i controller con i loro pin. Le periferiche, cioè un touch su I2C1, un
sensore su I2C2 o un chip SPI, le dichiara il DT della carrier che le monta.

* **I2C1** su PD5/PD6 e **I2C2** su PD15/PD16, con i pull-up da 4k7 sulla SoM
  (foglio CPU: R26/R17 e R27/R18), come vuole la specifica. Da Linux si
  esplorano con `i2cdetect -y 1` e `i2cdetect -y 2`.
* **SPI0** del connettore è spi1 del SoC, su PE7-PE10, con un solo chip
  select (PE7), come vuole la specifica. Senza un nodo figlio non c'è un
  device da aprire. `spidev` non accetta `compatible = "spidev"` nel DT
  ("spidev listed directly in DT is not supported", `drivers/spi/spidev.c`),
  e `CONFIG_SPI_SPIDEV` non è nel kernel. Per provare il bus serve il nodo
  della periferica vera nel DT della carrier.

`make O=output-egare check` (sezione 12c) verifica per ciascun bus alias,
nodo attivo e pin, e che `spi0` resti la NAND.

## PWM0 e GPIO

**PWM0** (pin 210) è il canale 1 del PWM su PE6: il DTS accende il
controller e mette in mux solo PE6. Il canale 0 non è sul connettore, e i
suoi pin (PA2, PE12) servono a UART1 e I2C0. Per la numerazione vedi sotto.

**GPIO0..7** (pin 223-241) hanno il nome della specifica in
`gpio-line-names` sul controller `pio`. L'indice di ogni nome è
banco × 32 + pin a partire da PA0 (`pinctrl-sunxi.c`: `PINS_PER_BANK` 32,
`pin_base` 0), quindi PD0 = 96 e PD17 = 113. Hanno un nome anche i segnali
della SoM che sono GPIO puri: `SD0_CD#` (PD21), `USB0_VBUS` (PE2),
`USB0_ID` (PE3), `USB_SEL` (PE4). GPIO8..19 non sono popolati.

Nel kernel `GPIO_SYSFS` è spento: da shell si usano i tool di libgpiod,
aggiunti alla build EGARE (`BR2_PACKAGE_LIBGPIOD2_TOOLS`):

```sh
gpioinfo                       # tutte le linee, con nome e consumer
gpioget -c gpiochip0 GPIO3     # legge GPIO3 del connettore
gpioset -c gpiochip0 GPIO3=1   # lo porta alto (finché il comando gira)
```

**Verificato su board** (2026-11-28): PWM0 e GPIO0..7 funzionano.

`make O=output-egare check` (sezione 12c) verifica che la PWM sia attiva su
PE6 e che ogni nome GPIO0..7 stia sulla linea giusta: un `""` in più o in
meno sposterebbe tutti i nomi.

## Numeri del connettore e numeri del SoC

La specifica nomina i bus con il numero del connettore. Due di questi non
coincidono con il numero del SoC:

* **SPI0 del connettore è `spi1` del SoC**, perché spi0 serve la SPI NAND di
  boot (come prescrive la specifica). In Linux è il bus 1 (`spi1.0`,
  `/dev/spidev1.0` con spidev). Gli alias lo fissano: `spi0 = &spi0` (NAND),
  `spi1 = &spi1`. Senza alias, con due controller attivi il numero
  dipenderebbe dall'ordine di probe, e i bootargs NAND chiamano la flash
  `mtdparts=spi0.0`. Un alias `spi0 = &spi1` darebbe il numero del
  connettore, ma toglierebbe il bus 0 alla NAND: meglio dichiararlo nel
  datasheet.
* **PWM0 del connettore è il canale 1** di `pwmchip0`, e non si può
  rinumerare. Il core PWM del kernel non legge alias (`drivers/pwm/core.c`
  numera i chip con un IDR), e il numero del canale è quello dell'hardware:
  il blocco PWM ha due canali, PE6 è il canale 1 e il canale 0 non arriva al
  connettore. Nel DT di una carrier: `pwms = <&pwm 1 periodo polarità>`; da
  sysfs: `echo 1 > /sys/class/pwm/pwmchip0/export`.

UART e I2C invece coincidono: uartN e i2cN del SoC sono UARTn e I2Cn del
connettore, e `ttySn` è UARTn.

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
