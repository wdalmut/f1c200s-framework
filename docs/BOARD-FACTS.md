# BOARD-FACTS — FTVOGUE F1C200S (Lctech Pi F1C200s)

Fatti verificati sull'hardware e sui sorgenti, con la fonte di ciascuno.
Tutto quello che sta qui è stato controllato; quello che non lo è sta in
[Aperti](#aperti).

## Identità

La board venduta da FTVOGUE come "Scheda sviluppo F1C200S" è la **Lctech Pi
F1C200s** (in passato brandizzata anche "Cherry Pi"), supportata in mainline:

| Componente | File | Dal |
|---|---|---|
| Linux | `arch/arm/boot/dts/allwinner/suniv-f1c200s-lctech-pi.dts` | sync DT in albero |
| U-Boot | `configs/lctech_pi_f1c200s_defconfig` | v2023.07 |

Il commit U-Boot che introduce il defconfig è *"sunxi: defconfig: Add Lctech Pi
F1C200s board"* di Andre Przywara, e nel messaggio dichiara il punto chiave:

> The Lctech Pi F1C200s ... is the same as the F1C100s, but with 64MB instead
> of 32MB co-packaged DRAM. ... This uses the new 64MB memory map, which avoids
> the very tight memory map we use for the 32MB F1C100s board(s).

| | |
|---|---|
| SoC | Allwinner **F1C200s** (famiglia `suniv`), ARM926EJ-S, **ARMv5TE** |
| DRAM | **64 MB DDR1** co-packaged, base `0x80000000` |
| Flash | **1 Gbit SPI NAND** su `spi0` |
| Seriale | **UART1**, **PA2 (TX) / PA3 (RX)**, 115200 8N1 → `ttyS0` |
| USB-C | OTG, modalità FEL per il recovery |
| Non configurati | LCD 40 pin, CSI 24 pin, audio 1 W |

## Le cinque trappole

Quasi tutte le guide in rete sono scritte per la **LicheePi Nano** (F1C100s),
che è una board *diversa*. Applicarle a questa produce guasti silenziosi.

### 1. La flash è SPI NAND, non SPI NOR

Fonte: il DTS mainline della board.

```dts
&spi0 {
	flash@0 {
		compatible = "spi-nand";
		reg = <0>;
		spi-max-frequency = <40000000>;
	};
};
```

Conseguenza: i comandi U-Boot `sf probe` / `sf read` / `sf write`, che parlano
**solo** SPI NOR, qui non funzionano; non funziona `sunxi-fel spiflash-write`;
e non ha senso un rootfs **JFFS2** con `mtdparts=spi0.0:...`. Tutte le ricette
con `flash.bin` sono per NOR.

### 2. L'SPL di U-Boot mainline non legge la SPI NAND

Fonte: `arch/arm/mach-sunxi/spl_spi_sunxi.c`, controllato sui tag **v2025.10,
v2026.04 e v2026.07** — zero occorrenze della stringa `nand` (410 righe in
tutte e tre le release: il file non è cambiato).

Riscontro indipendente: `lctech_pi_f1c200s_defconfig` **non** abilita
`CONFIG_SPL_SPI_SUNXI`, mentre `licheepi_nano_defconfig` (che ha una NOR) sì.

**Conseguenza: con U-Boot mainline questa board boota solo da SD.** Il boot da
NAND richiede un bootloader fuori mainline. Vedi [Aperti](#aperti).

### 3. La console è UART1, non UART0

Fonte: il DTS della board.

```dts
aliases { serial0 = &uart1; };
chosen  { stdout-path = "serial0:115200n8"; };
&uart1  { pinctrl-0 = <&uart1_pa_pins>; status = "okay"; };
```

In U-Boot questo significa **`CONFIG_CONS_INDEX=2`**. Con `CONS_INDEX=1`
(UART0, pin PE0/PE1, **non cablati su questa board**) il risultato è **nessun
carattere sulla seriale**, dal primo istante, senza alcun messaggio di errore:
la board sembra morta pur essendo perfettamente viva.

È l'errore che si eredita usando `licheepi_nano_defconfig`.

### 4. Il kernel va forzato su ARMv5

`sunxi_defconfig` di Linux è ARMv7 multiplatform (`CONFIG_ARCH_MULTI_V7=y`).
L'F1C200s è ARM926EJ-S, cioè **ARMv5TE**. Il frammento
`board/ftvogue-f1c200s/linux.fragment` ribalta il profilo:

```
# CONFIG_ARCH_MULTI_V7 is not set
CONFIG_ARCH_MULTI_V5=y
CONFIG_MACH_SUNIV=y
```

La verifica che conta è nel `.config` finale: deve risultare
`CONFIG_CPU_ARM926T=y`. La controlla `docs/check-image.sh`.

Lato Buildroot: `BR2_arm=y` + `BR2_arm926t=y` → toolchain
`arm-buildroot-linux-gnueabi-`, EABI **soft float** (l'ARM926 non ha FPU).

Attenzione a una sottigliezza: `BR2_arm926t` e' il **default** di `BR2_arm`,
quindi `make savedefconfig` lo rimuove dal defconfig perche' ridondante. Il
defconfig in albero non lo contiene, ed e' corretto cosi'. Il valore effettivo
va quindi controllato nel `.config` risultante, non nel defconfig — ed e'
esattamente quello che fa la CI, cosi' che un eventuale cambio di default in
un futuro bump di Buildroot non passi inosservato.

### 5. `CONFIG_BOOTCOMMAND` disattiva boot.scr ed extlinux

Se in U-Boot è definito `CONFIG_BOOTCOMMAND`, viene eseguito quello e
bootstd / distro-boot / `boot.scr` / `extlinux.conf` **non vengono nemmeno
cercati**. Qui il `bootcmd` è esplicito di proposito: meno pezzi mobili, e
nessun fallback che maschera un errore.

## Catena di boot

```
BROM (in ROM nel SoC)
  └─ cerca l'header "eGON.BT0" a offset 8 KiB della SD (mmc0)
     └─ carica SPL in SRAM ed esegue
        │
        ├─ SPL: init DDR1 (64 MB @ 0x80000000), UART1 @115200,
        │       carica U-Boot proper in RAM a 0x81700000
        │
        └─ U-Boot proper (si rialloca in cima alla RAM)
           └─ CONFIG_BOOTCOMMAND:
                load mmc 0:1 0x80008000 zImage
                load mmc 0:1 0x81800000 suniv-f1c200s-lctech-pi.dtb
                bootz 0x80008000 - 0x81800000
              └─ Linux, con CONFIG_BOOTARGS:
                   console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw
```

La BROM prova **prima la SD**, poi la SPI: una SD inserita ha sempre la
precedenza sul firmware di fabbrica nella NAND, e toglierla fa ripartire il
sistema originale. Riscontro: la board boota la build di questo repo con la SD
inserita, e il sistema preinstallato senza.

## Mappa di memoria

```
0x80000000  base DRAM
0x80008000  zImage            (base + 32 KiB, convenzione ARM)
0x81700000  TEXT_BASE U-Boot  (pre-rilocazione)
0x81800000  DTB               (base + 24 MiB)
0x83FFFFFF  fine DRAM         (U-Boot rilocato vicino a qui)
```

`0x81800000` è sicuro perché quando gira `bootcmd` U-Boot si è già spostato in
cima alla RAM. Il margine fra zImage e DTB è di 24 MiB: se un giorno il kernel
decompresso li superasse, il DTB va spostato più in alto.

## Immagine SD

```
offset  8 KiB          SPL + U-Boot (u-boot-sunxi-with-spl.bin, ~400 KB)
                       riservato fino a 2 MiB
offset  2 MiB   p1     FAT16, 16 MB, bootable, tipo 0x0C
                       └─ zImage, suniv-f1c200s-lctech-pi.dtb
poi             p2     ext4, 120 MB, tipo 0x83  → /dev/mmcblk0p2
```

La p1 parte a 2 MiB per non calpestare il bootloader. `docs/check-image.sh`
verifica che non scenda sotto.

## Aperti

* **Boot da SPI NAND.** Richiede un bootloader fuori mainline: awboot, oppure
  U-Boot con le patch SPI-NAND per sunxi. **Non verificato**, nessuno dei due è
  stato provato su questa board.
* **Rootfs in NAND con U-Boot da SD.** Questa strada non richiede niente fuori
  mainline — servono `CONFIG_MTD_SPI_NAND`, `CONFIG_MTD_UBI`, `CONFIG_UBIFS_FS`
  nel kernel — ma non è ancora stata implementata qui.
* **Identità esatta del chip NAND.** Il DTS usa il `compatible` generico
  `spi-nand`; il modello (W25N01GV o altro) non è stato letto dal silicio.
  Irrilevante finché la NAND non viene usata.
* **LCD 40 pin, CSI 24 pin, audio.** Non configurati: servirebbero i timing del
  pannello e `sun4i-drm`, ora disattivato nel frammento.
