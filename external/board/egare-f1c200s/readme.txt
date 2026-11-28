EGARE F1C200S — boot da SD card o da SPI NAND
=============================================

Board con lo stesso SoC della FTVOGUE F1C200S, costruita a parte per
confrontarla con quella. Questa directory contiene solo le differenze; il
resto (patch SPL, fragment di base, U-Boot) viene da ../ftvogue-f1c200s/.

  dts/allwinner/suniv-f1c200s-egare.dts
                   DTS Lctech Pi + console su uart0 (PE0/PE1), uart1 con
                   RTS/CTS (PA0-PA3), uart2 (PD13/PD14), i2c0 su
                   PE11/PE12 + EEPROM a 0x50, i2c1 (PD5/PD6), i2c2
                   (PD15/PD16), spi1 (PE7-PE10), PWM canale 1 (PE6), nomi
                   GPIO0..7, MUSB in host e PE4 (USB_SEL) alto verso il
                   LAN9512
  linux.fragment   applicato dopo quello FTVOGUE: CONFIG_EEPROM_AT24,
                   smsc95xx (LAN9512), usbmon
  uboot.fragment   applicato dopo quello FTVOGUE: console su uart0
                   (CONS_INDEX=1) e bootcmd con il DTB di questa board
  uboot/suniv-f1c200s-egare-u-boot.dtsi
                   accodato al DT U-Boot Lctech: serial0 = uart0
  genimage.cfg     layout dell'immagine SD (copia FTVOGUE, altro DTB)

La riga del bootcmd in uboot.fragment e genimage.cfg devono restare uguali a
quelli FTVOGUE a parte il nome del DTB: lo controlla la CI.

Console: UART0 del connettore SODIMM (pin 205/207, uart0 su PE0/PE1),
115200 8N1, non UART1 come sulla FTVOGUE.

Sempre con O=output-egare, altrimenti si sovrascrive la build FTVOGUE:

  make O=output-egare egare_f1c200s_defconfig
  make O=output-egare
  make O=output-egare check

SD:

  sudo dd if=output-egare/images/sdcard.img of=/dev/sdX bs=1M conv=fsync status=progress

SPI NAND (W25N02KV, 256 MiB), board in FEL:

  ./docs/flash-nand.sh output-egare/images

EEPROM di identificazione (schema v1.0, docs/EEPROM-ID.md):

  som-id show
  som-id write --product 0x0001 --rev 1 --ram 64 \
    --serial "$(som-id serial MA264800017)" --mac0 00:11:22:33:44:55
  som-id verify
  hexdump -C /sys/bus/i2c/devices/0-0050/eeprom

GPIO del connettore (libgpiod):

  gpioinfo
  gpioset -c gpiochip0 GPIO3=1

Ethernet (LAN9512, MAC casuale a ogni avvio):

  udhcpc -i eth0

Fatti verificati e stato delle prove: docs/EGARE-F1C200S.md.
