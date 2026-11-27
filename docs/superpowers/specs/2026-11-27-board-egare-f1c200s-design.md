# Board EGARE F1C200S accanto alla FTVOGUE — design

## Intento

La FTVOGUE F1C200S resta la **board di riferimento**: hardware noto e
funzionante, su cui una feature si prova senza dubitare del disegno.
La EGARE F1C200S è una board dell'utente, con lo stesso SoC, che si
costruisce **a parte** e si confronta con la FTVOGUE: se una cosa funziona
sulla FTVOGUE e non sulla EGARE, il sospetto va sull'hardware EGARE o sulle
differenze di configurazione, e queste devono essere poche e tutte in un
posto.

Questo è il punto 1 di tre. I punti 2 (schema dei 64 byte dell'EEPROM di
identificazione e tool di scrittura) e 3 (U-Boot che legge l'EEPROM e
sceglie DT e overlay) vengono dopo, ciascuno con il suo design.

## Differenze hardware rispetto alla FTVOGUE

Verificate su board il 2026-11-27:

- SPI NAND **Winbond W25N02KV** (`xfel spinand`: 268435456 byte), al posto
  del GD5F1GQ4xAYIG. Stessa pagina (2048 B, OOB 128) e blocco (128 KiB);
  dimensione doppia. Il kernel 6.12 la vede come `spi0.0` da 256 MiB.
  `flash-nand.sh` la scrive e rilegge senza errori (commit `9fe71c6`).
  **Boot da NAND non ancora verificato.**
- EEPROM **ST M24C02-FMN** su **i2c0**: SCK su PE11 (pin 38 del QFN88),
  SDA su PE12 (pin 37), indirizzo `0x50` (E0-E2 a GND). Letta con
  `i2cdump` (vergine, tutta `ff`) e scritta/riletta/ripristinata con
  `i2cset`/`i2cget` usando un DTB di prova.

## Obiettivi

- `make O=output-egare egare_f1c200s_defconfig && make O=output-egare`
  produce `sdcard.img`, `u-boot-sunxi-with-spl.bin` e `rootfs.ubi` per la
  EGARE.
- Su Linux la EEPROM è leggibile e scrivibile come file:
  `/sys/bus/i2c/devices/0-0050/eeprom`.
- UBIFS usa i 256 MiB della W25N02KV, non solo i primi 128.
- `make O=output-egare check` verifica la build EGARE, inclusi i2c0 ed
  EEPROM nel DTB.
- Boot da SD e da NAND con lo stesso `bootcmd` a due rami della FTVOGUE.

## Non-obiettivi

- Schema dei dati in EEPROM, tool di provisioning (punto 2).
- U-Boot che legge l'EEPROM, scelta di DT/overlay (punto 3). U-Boot resta
  identico a quello della FTVOGUE, DT di U-Boot compreso.
- Rete su gadget USB, hostname o altre personalizzazioni della SD che
  gira oggi sulla EGARE: non sono in questo repo e restano fuori.
- LCD, CSI, audio.

## Anti-obiettivi

- **Qualunque cambiamento negli artefatti della FTVOGUE.** Il suo
  defconfig, i suoi fragment, `genimage.cfg` e `bootcmd` non si toccano;
  `make check` sulla build FTVOGUE deve dare gli stessi `ok` di prima.
- Una copia dei file FTVOGUE che diverge in silenzio.

## Approcci

- **A. Directory propria sopra quella della FTVOGUE — scelto.**
  `external/board/egare-f1c200s/` contiene solo le differenze; patch SPL,
  fragment di base e U-Boot vengono dalla directory FTVOGUE. La differenza
  fra le due board è il contenuto di quella directory. Contro: una modifica
  ai file FTVOGUE arriva anche alla EGARE, che per il confronto è voluto.
- B. Copia completa: indipendenza totale, ma patch SPL e configurazione
  duplicate, correzioni da fare due volte, divergenza silenziosa. Contrario
  allo scopo del confronto.
- C. `external/board/common/` condivisa: la più ordinata con molti moduli,
  ma sposta file FTVOGUE verificati e i percorsi dei documenti. Da
  rivalutare con il punto 3.

## Design

### File nuovi

```
external/configs/egare_f1c200s_defconfig
external/board/egare-f1c200s/
  dts/allwinner/suniv-f1c200s-egare.dts
  linux.fragment
  uboot.fragment
  genimage.cfg
  readme.txt
docs/EGARE-F1C200S.md
```

**`egare_f1c200s_defconfig`** — come quello FTVOGUE, con queste differenze:

| Opzione | Valore |
|---|---|
| `BR2_TARGET_GENERIC_HOSTNAME` | `"egare-f1c200s"` |
| `BR2_TARGET_GENERIC_ISSUE` | `"EGARE F1C200S - mainline"` |
| `BR2_ROOTFS_POST_SCRIPT_ARGS` | `-c .../egare-f1c200s/genimage.cfg` |
| `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` | `.../ftvogue-f1c200s/linux.fragment .../egare-f1c200s/linux.fragment` |
| `BR2_LINUX_KERNEL_INTREE_DTS_NAME` | vuoto |
| `BR2_LINUX_KERNEL_CUSTOM_DTS_DIR` | `.../egare-f1c200s/dts` |
| `BR2_TARGET_ROOTFS_UBIFS_MAXLEBCNT` | `2040` (256 MiB − 1 MiB di boot, in PEB da 128 KiB) |
| `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES` | `.../ftvogue-f1c200s/uboot.fragment .../egare-f1c200s/uboot.fragment` |

`BR2_GLOBAL_PATCH_DIR` resta quello FTVOGUE: stesse patch SPL. Il file si
rigenera con `savedefconfig`, come richiede la CI.

`BR2_LINUX_KERNEL_CUSTOM_DTS_DIR` e non `_CUSTOM_DTS_PATH`: dal 6.12 il
secondo è deprecato in Buildroot, e il primo copia la sottodirectory
`allwinner/` sopra `arch/arm/boot/dts/`, così l'`#include` del DTS Lctech
funziona senza percorsi.

**`suniv-f1c200s-egare.dts`** — include `suniv-f1c200s-lctech-pi.dts` e
aggiunge solo:

- `model = "EGARE F1C200S"` (il `compatible` resta quello Lctech: un vendor
  prefix non registrato porterebbe solo warning);
- in `&pio` il gruppo `i2c0_pe_pins` (PE11, PE12, funzione `i2c0`): il
  `.dtsi` ha solo quello su PD0/PD12;
- `&i2c0` con quel gruppo, `status = "okay"`, e il figlio
  `eeprom@50 { compatible = "st,24c02", "atmel,24c02"; reg = <0x50>;
  pagesize = <16>; }`.

È lo stesso contenuto del DTB di prova verificato su board, più il
`model` e il compatible `st,`.

**`linux.fragment`** — solo `CONFIG_EEPROM_AT24=y` (built-in, come il resto
dei driver della board).

**`uboot.fragment`** — solo `CONFIG_BOOTCOMMAND`, identico a quello
FTVOGUE tranne il nome del DTB (`suniv-f1c200s-egare.dtb`) nei due rami.
Applicato dopo il fragment FTVOGUE, lo sovrascrive.

**`genimage.cfg`** — identico a quello FTVOGUE tranne il nome del DTB.

**`docs/EGARE-F1C200S.md`** — i fatti della sezione "Differenze hardware"
qui sopra, con fonte e data, e come costruire e flashare. BOARD-FACTS
resta della FTVOGUE.

### File condivisi modificati

**`docs/check-image.sh`**

- Il DTB non è più scritto nel codice: è l'unico `*.dtb` in `images/`
  (errore se zero o più d'uno). Le sezioni 3, 7 e 11 usano quel nome.
- Il `model` atteso si ricava dal nome del DTB: `lctech-pi` →
  `Lctech Pi F1C200s`, `egare` → `EGARE F1C200S`.
- Nuovo controllo: il `bootcmd` (in `.config` di U-Boot) carica quel DTB
  in entrambi i rami. Intercetta un fragment che punta al DTB di un'altra
  board, che altrimenti si scopre solo con `Bad Linux ARM zImage magic` o
  un boot senza DT.
- Nuova sezione solo per il DTB `egare`: nel DTB `i2c@1c27000` è `okay` e
  ha `eeprom@50`; nel kernel `CONFIG_EEPROM_AT24=y`.
- Sulla build FTVOGUE l'esito resta lo stesso di oggi.

**`.github/workflows/checks.yml`**

- Il controllo ARMv5/`MACH_SUNIV` passa da "ogni `linux.fragment`" a "per
  ogni defconfig, almeno uno dei suoi fragment", leggendo
  `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` dal `.config` risultante.
- Nuovo controllo: `uboot.fragment` e `genimage.cfg` EGARE sono uguali a
  quelli FTVOGUE dopo aver sostituito il nome del DTB. Se uno dei due
  cambia senza l'altro, la CI fallisce.

**`.gitignore`** — `/output-*/`.

**`CLAUDE.md`, `README.md`** — struttura, comandi con `O=output-egare`,
riga in "Dove si cambia cosa".

## Verifica

1. Build FTVOGUE invariata: `make check` con gli stessi `ok`, defconfig
   FTVOGUE senza diff.
2. Build EGARE: `make O=output-egare check` tutto `ok`.
3. CI locale: `savedefconfig` senza diff per entrambi i defconfig, i due
   nuovi controlli passano, e falliscono se si altera a mano il `bootcmd`
   EGARE.
4. Su board EGARE, da SD: `hexdump -C /sys/bus/i2c/devices/0-0050/eeprom`
   legge 256 byte; una scrittura su un byte si rilegge e si ripristina.
5. Su board EGARE, da NAND (senza SD) dopo
   `./docs/flash-nand.sh output-egare/images`: `boot: NAND`, login,
   `ubi0:rootfs` su `/`, `df -h /` intorno ai 230-240 MiB.

## Lasciato a chi implementa

- Ordine dei commit e testo dei messaggi.
- Forma esatta del controllo di equivalenza in CI (`sed` + `diff` va bene).
- Se la prima build EGARE debba condividere `DL_DIR` con quella FTVOGUE:
  consigliato, non richiesto.
