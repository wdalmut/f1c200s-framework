EGARE F1C200S — boot da SD card o da SPI NAND
=============================================

Board con lo stesso SoC della FTVOGUE F1C200S, costruita a parte per
confrontarla con quella. Questa directory contiene solo le differenze; il
resto (patch SPL, fragment di base, U-Boot) viene da ../ftvogue-f1c200s/.

  dts/allwinner/suniv-f1c200s-egare.dts
                   DTS Lctech Pi + i2c0 su PE11/PE12 + EEPROM a 0x50,
                   MUSB in host e PE4 (USB_SEL) alto verso il LAN9512
  linux.fragment   applicato dopo quello FTVOGUE: CONFIG_EEPROM_AT24,
                   smsc95xx (LAN9512), usbmon
  uboot.fragment   applicato dopo quello FTVOGUE: solo il bootcmd, con il
                   DTB di questa board
  genimage.cfg     layout dell'immagine SD (copia FTVOGUE, altro DTB)

uboot.fragment e genimage.cfg devono restare uguali a quelli FTVOGUE a parte
il nome del DTB: lo controlla la CI.

Sempre con O=output-egare, altrimenti si sovrascrive la build FTVOGUE:

  make O=output-egare egare_f1c200s_defconfig
  make O=output-egare
  make O=output-egare check

SD:

  sudo dd if=output-egare/images/sdcard.img of=/dev/sdX bs=1M conv=fsync status=progress

SPI NAND (W25N02KV, 256 MiB), board in FEL:

  ./docs/flash-nand.sh output-egare/images

EEPROM da Linux:

  hexdump -C /sys/bus/i2c/devices/0-0050/eeprom

Ethernet (LAN9512, MAC casuale a ogni avvio):

  udhcpc -i eth0

Fatti verificati e stato delle prove: docs/EGARE-F1C200S.md.
