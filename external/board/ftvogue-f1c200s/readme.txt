FTVOGUE F1C200S (Lctech Pi F1C200s) — boot da SD card
=====================================================

Questa directory contiene i file di board per Buildroot: frammenti di
configurazione per kernel e U-Boot, e il layout dell'immagine SD.

  linux.fragment   opzioni kernel applicate sopra sunxi_defconfig
  uboot.fragment   opzioni U-Boot applicate sopra lctech_pi_f1c200s_defconfig
  genimage.cfg     layout dell'immagine SD

Non si usa direttamente: si passa dal wrapper nella radice del repository.

  ./setup.sh
  make ftvogue_f1c200s_defconfig
  make
  make check

L'immagine da scrivere sulla SD e' output/images/sdcard.img.

  sudo dd if=output/images/sdcard.img of=/dev/sdX bs=1M conv=fsync status=progress

Console seriale: UART1, pin PA2 (TX) / PA3 (RX), 115200 8N1 -> ttyS0.
Login: root, senza password.

I fatti sull'hardware e le trappole di questa board (la flash e' SPI NAND non
NOR; la console e' UART1 non UART0; il kernel va forzato su ARMv5) stanno in
docs/BOARD-FACTS.md nella radice del repository.
