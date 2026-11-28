# f1c200s-framework — riferimento operativo

Repository per costruire un'immagine SD per la **FTVOGUE F1C200S**
(= Lctech Pi F1C200s, Allwinner F1C200s / `suniv`) con Buildroot upstream
tenuto come submodule.

**I fatti sull'hardware stanno in [docs/BOARD-FACTS.md](docs/BOARD-FACTS.md);
le ragioni delle scelte in [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md).**
Questo file è il riferimento operativo: dove stanno le cose e come si cambiano.

---

## Regola prima

`buildroot/` è un submodule di upstream e **non va mai modificato**. Tutto si
esprime nel defconfig e nei fragment dentro `external/`. Una patch a Buildroot
sarebbe invisibile nei diff di questo repo e sparirebbe al primo bump del
submodule.

---

## Struttura

```
buildroot/                                  submodule, LTS 2026.02.3 — non toccare
external/
  external.desc                             name: F1C200S -> $(BR2_EXTERNAL_F1C200S_PATH)
  external.mk                               include dei package propri
  Config.in                                 menu Kconfig dell'albero: source dei package
  package/som-id/                           tool EEPROM di identificazione (repo egaree/som-id, tag in som-id.mk)
  configs/ftvogue_f1c200s_defconfig         il defconfig della board di riferimento
  configs/egare_f1c200s_defconfig           la EGARE (vedi docs/EGARE-F1C200S.md)
  board/ftvogue-f1c200s/
    linux.fragment                          opzioni kernel sopra sunxi_defconfig
    uboot.fragment                          opzioni U-Boot sopra lctech_pi_f1c200s_defconfig
    genimage.cfg                            layout dell'immagine SD
    patches/uboot/                          patch SPL SPI NAND (serie Icenowy, portata)
    patches/linux/                          FIFO MUSB suniv entro 4 KiB (RX USB in host)
    readme.txt
  board/egare-f1c200s/                      solo le differenze, sopra ftvogue-f1c200s/
    dts/allwinner/suniv-f1c200s-egare.dts   DTS Lctech + i2c0 PE11/PE12 + EEPROM 0x50 + USB host/PE4
    linux.fragment                          dopo quello FTVOGUE: EEPROM_AT24, smsc95xx, usbmon
    uboot.fragment                          dopo quello FTVOGUE: console uart0 (CONS_INDEX=1), bootcmd con il DTB EGARE
    uboot/suniv-f1c200s-egare-u-boot.dtsi   accodato al DT U-Boot Lctech: serial0 = uart0
    genimage.cfg                            copia FTVOGUE con il DTB EGARE
    readme.txt
docs/
  BOARD-FACTS.md                            fatti verificati, con le fonti
  SCELTE-DI-PROGETTO.md                     perché è fatto così
  EGARE-F1C200S.md                          la board EGARE: differenze verificate
  EGARE-SPEC-SODIMM.md                      EGARE contro la specifica SODIMM 260-pin: cosa manca nel DT
  EEPROM-ID.md                              EEPROM di identificazione: cosa vale qui (lo schema è in som-id)
  check-image.sh                            verifica gli artefatti (make check)
  flash-nand.sh                             scrive la SPI NAND via xfel
  test-flash-nand.sh                        prova flash-nand.sh con un xfel finto (anche in CI)
Makefile                                    wrapper su Buildroot
setup.sh                                    submodule + dipendenze host
output/                                     generato, in .gitignore
output-egare/                               idem, build EGARE (O=output-egare)
```

Nei defconfig i percorsi si scrivono con `$(BR2_EXTERNAL_F1C200S_PATH)`, mai
relativi: Buildroot espande quella variabile quando include il `.config`.

---

## Comandi

Il `Makefile` in radice è solo un wrapper: evita di ripetere
`-C buildroot O=... BR2_EXTERNAL=...`. Qualunque target sconosciuto viene
inoltrato a Buildroot.

```bash
./setup.sh                          # submodule + controllo dipendenze host
make ftvogue_f1c200s_defconfig      # configura
make                                # costruisce
make check                          # verifica gli artefatti prodotti
./docs/flash-nand.sh                # board in FEL: scrive SPL, U-Boot e rootfs.ubi in NAND
make defconfigs                     # elenca i defconfig
make help

make O=output-egare egare_f1c200s_defconfig   # la EGARE, in un'altra directory
make O=output-egare                            # ogni comando EGARE vuole O=output-egare
make O=output-egare check
./docs/flash-nand.sh output-egare/images
```

Senza `O=` si lavora su `output/`, cioè sulla FTVOGUE: un
`egare_f1c200s_defconfig` lanciato lì sovrascrive la sua configurazione.

Non usare `-jN` sul make di primo livello: Buildroot parallelizza da sé
(`BR2_JLEVEL`).

### Dopo aver modificato un fragment

**Buildroot non se ne accorge da solo.**

```bash
make linux-reconfigure      # dopo aver toccato linux.fragment
make uboot-reconfigure      # dopo aver toccato uboot.fragment
make                        # rigenera le immagini
```

Se cambi solo `genimage.cfg` basta `make`: lo script post-image rigira sempre.

### Modificare kernel e U-Boot interattivamente

```bash
make linux-menuconfig       # oppure: make uboot-menuconfig
make linux-diff-config      # diff fra (defconfig + fragment) e il .config attuale
```

`*-diff-config` è il modo corretto di raccogliere le modifiche: stampa il diff,
e tu **riporti a mano** le righe nel fragment. Poi `make linux-reconfigure`.

> `make linux-update-defconfig` e `make uboot-update-defconfig` **non esistono**
> in questa configurazione. In `package/pkg-kconfig.mk` sono definiti solo
> dentro `ifeq ($$($(2)_KCONFIG_DEFCONFIG),)`, cioè quando si usa un *custom
> config file*; noi usiamo un *board defconfig* + fragment. Invocandoli si
> ottiene "No rule to make target". Esistono invece `*-savedefconfig` e
> `*-diff-config`.

### Modificare la configurazione Buildroot

```bash
make menuconfig
make savedefconfig          # riscrive external/configs/ftvogue_f1c200s_defconfig
```

`make ftvogue_f1c200s_defconfig` imposta `BR2_DEFCONFIG` nel `.config`, e il
Makefile di Buildroot fa `DEFCONFIG = $(call qstrip,$(BR2_DEFCONFIG))`: quindi
`savedefconfig` sa già dove riscrivere, senza passargli il percorso.

La CI verifica che `savedefconfig` non produca diff: se modifichi un defconfig
a mano, rigeneralo prima di committare.

### Pulizia

```bash
make clean                  # cancella output/, TIENE .config
make distclean              # cancella output/, .config E ANCHE la cache dl/
```

> `make distclean` fa `rm -rf $(TOPDIR)/dl`. Se usi la `dl/` di default (dentro
> il submodule) perdi tutti i sorgenti scaricati. Con `DL_DIR` puntato fuori
> dall'albero il problema non si pone — ed è il motivo per cui il wrapper
> espone quella variabile.

---

## Dove si cambia cosa

| Voglio... | Tocco | Poi |
|---|---|---|
| Cambiare i `bootargs` | `board/ftvogue-f1c200s/uboot.fragment` → `setenv bootargs` nel ramo giusto (SD o NAND) di `CONFIG_BOOTCOMMAND` | `make uboot-reconfigure && make` |
| Cambiare cosa carica U-Boot | stesso file → `CONFIG_BOOTCOMMAND` | `make uboot-reconfigure && make` |
| Abilitare un driver kernel | `board/ftvogue-f1c200s/linux.fragment` | `make linux-reconfigure && make` |
| Cambiare versione kernel | `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` **e** `BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_*` | `make` |
| Cambiare versione U-Boot | `BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE` | `make` |
| Aggiungere un pacchetto | `make menuconfig` | `make savedefconfig` |
| Cambiare layout SD | `board/ftvogue-f1c200s/genimage.cfg` | `make` |
| Aggiungere file nel rootfs | `BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_F1C200S_PATH)/board/ftvogue-f1c200s/rootfs_overlay"` | `make` |
| Aggiungere un package proprio | `external/package/<nome>/{Config.in,<nome>.mk}` + `source` in `external/Config.in` | `make menuconfig` |
| Cambiare il layout NAND | `CONFIG_SYS_SPI_U_BOOT_OFFS` e `CONFIG_MTDPARTS_DEFAULT` (uboot.fragment), `mtdparts=` nel bootcmd, `docs/flash-nand.sh`, sezione 9 di `check-image.sh` | `make uboot-reconfigure && make` |
| Toccare le patch SPL | `board/ftvogue-f1c200s/patches/uboot/` | `make uboot-dirclean && make` |
| Cambiare il DTS EGARE | `board/egare-f1c200s/dts/allwinner/suniv-f1c200s-egare.dts` — Buildroot lo copia nel kernel solo in fase di build: un `make` semplice tiene il DTB vecchio | `make O=output-egare linux-rebuild && make O=output-egare` |
| Cambiare il DT di U-Boot EGARE | `board/egare-f1c200s/uboot/suniv-f1c200s-egare-u-boot.dtsi` — Buildroot lo copia in `arch/arm/dts/` a ogni build di U-Boot | `make O=output-egare uboot-rebuild && make O=output-egare` |
| Cambiare qualcosa solo per la EGARE | `board/egare-f1c200s/` (DTS, fragment applicati dopo quelli FTVOGUE) | stesso flusso, con `O=output-egare` |
| Cambiare il `bootcmd` o `genimage.cfg` FTVOGUE | anche la copia in `board/egare-f1c200s/`: la CI controlla che restino uguali a parte il DTB | ricostruire entrambe le board |
| Cambiare lo schema EEPROM o il tool `som-id` | repo `egaree/som-id` (nuovo tag), poi `SOM_ID_VERSION` e `som-id.hash` in `external/package/som-id/`; se cambiano gli offset anche le celle nel DTS EGARE e la sezione 12 di `check-image.sh`. Su un checkout locale: `SOM_ID_OVERRIDE_SRCDIR` in `output-egare/local.mk` | `make O=output-egare som-id-dirclean && make O=output-egare` |
| Bumpare Buildroot | `cd buildroot && git checkout <tag LTS>` + commit del submodule | build completa |

I fragment e le patch di `board/ftvogue-f1c200s/` valgono **anche per la EGARE**,
che li applica prima dei suoi: una modifica lì va ricostruita su entrambe.

**Kernel e kernel-headers devono restare allineati.** Ora: `6.12.111` +
`BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_12=y`.

---

## Le cinque trappole, in breve

Dettagli e fonti in [docs/BOARD-FACTS.md](docs/BOARD-FACTS.md). Qui solo il
promemoria, perché sono gli errori che costano giornate:

1. **La flash è SPI NAND, non NOR.** Niente `sf probe` / `sf read`, niente
   `flash.bin`, niente rootfs JFFS2 con `mtdparts`.
2. **L'SPL mainline non legge la SPI NAND.** Lo fanno le nostre patch in
   `patches/uboot/`: se un bump di U-Boot le rompe, va rifatto il porting, non
   tolte le patch.
3. **La console è UART1 (PA2/PA3)** → `CONFIG_CONS_INDEX=2`. Se è sbagliato non
   esce *nessun* carattere e la board sembra morta. Vale per la FTVOGUE: la
   **EGARE** usa uart0 (PE0/PE1, UART0 del connettore SODIMM) → `CONS_INDEX=1`
   **e** `serial0 = &uart0` nel DT di U-Boot e del kernel, sempre insieme.
4. **Il kernel va forzato su ARMv5.** `sunxi_defconfig` è ARMv7 multiplatform;
   deve risultare `CONFIG_CPU_ARM926T=y`.
5. **`CONFIG_BOOTCOMMAND` disattiva `boot.scr` ed `extlinux.conf`.**

Quasi tutte le guide in rete sono per la **LicheePi Nano** (F1C100s), che ha
SPI NOR, 32 MB di DRAM e console su UART0. Non sono applicabili.

---

## Verifica

```bash
make check
```

Esegue `docs/check-image.sh`: header `eGON.BT0` a 8 KiB, layout partizioni,
contenuto della FAT, `CONS_INDEX` della board e stessa UART in SPL, U-Boot e
kernel, DRAM 64 MB, kernel ARMv5/`suniv`,
assenza di `sf read` nel `bootcmd`, `bootcmd` davvero compilato in
`u-boot.bin`, `model` del DTB; per la NAND: patch SPL applicate, U-Boot che
non sfora in UBI, geometria di `rootfs.ubi`, kernel e DTB in `/boot`. Aggiungi un controllo qui ogni volta che scopri
un guasto silenzioso nuovo.

La CI (`.github/workflows/checks.yml`) non costruisce: verifica solo ciò che si
rompe in silenzio senza bisogno di artefatti.

---

## Sintomi → causa

| Sintomo | Causa quasi certa |
|---|---|
| **Niente** sulla seriale, mai | `CONS_INDEX` sbagliato (FTVOGUE 2, EGARE 1), TX/RX non incrociati, o GND non in comune |
| EGARE: esce l'SPL, poi silenzio da U-Boot | `CONS_INDEX` e `serial0` del DT di U-Boot su UART diverse (sezione 7b di check) |
| Caratteri illeggibili | baudrate diverso da 115200 |
| SPL parte poi si blocca | mappa DRAM da 32 MB (manca `SUNXI_MINIMUM_DRAM_MB=64`) |
| `sf probe` fallisce | normale: la flash è NAND, non NOR |
| `boot.scr` / `extlinux.conf` ignorati | c'è `CONFIG_BOOTCOMMAND`, che ha la precedenza |
| Nessun output dopo "Starting kernel" | DTB sbagliato, o kernel ARMv7 invece che ARMv5 |
| `VFS: Unable to mount root fs` | `root=` non corrisponde a `genimage.cfg` |
| Modifiche a un fragment ignorate | manca `make linux-reconfigure` / `uboot-reconfigure` |
| `No rule to make target 'linux-update-defconfig'` | quel target non esiste qui: usa `linux-diff-config` |
| La toolchain diventa uClibc | versione di linux-headers non presente nella choice |
| Senza SD: `U-Boot SPL` poi `Trying to boot from FEL` | patch 0005 non applicata (boot source NAND non mappata) |
| Senza SD: SPL parte ma non trova U-Boot | `.bin` non scritto a 0x40000 (`splwrite` con indirizzo 0 scarta tutto tranne l'SPL) |
| `lsusb` vede `1f3a:efe8` ma `xfel` dice `No FEL device found` | permessi sul device USB: manca la regola udev (README, "Flash su SPI NAND") |
| La board non va in FEL (SPL valido in NAND, nessun pulsante) | dal prompt di U-Boot `mtd erase spi-nand0 0 0x40000`, poi accensione senza SD |
| `flash-nand: rilettura diversa` | bad block nella zona scritta: xfel non li salta (vedi BOARD-FACTS, "Layout SPI NAND") |
| `ubi part ubi` / attach UBI fallisce | flash non cancellata per intero, o geometria UBI errata (sezione 10 di check) |
| `boot: SD` senza SD avviabile | SD non avviabile ma con la nostra FAT inserita |
| EGARE: `eth0` link su, `tx_packets` sale, `rx_packets` e `rx_errors` fermi a 0 | FIFO MUSB oltre 4 KiB: `patches/linux/0001-*` non applicata (sezione 8b di check) |
| EGARE: `lsusb` vede solo il root hub | PE4 (`USB_SEL`) basso o MUSB non in host: hog e `dr_mode` nel DTS EGARE |
| EGARE: `eth0` con MAC casuale, diverso a ogni avvio | EEPROM vergine o slot ETH0 non valido (`som-id show`), oppure `nvmem-cells`/alias `ethernet0` mancanti nel DTB (sezione 12 di check) |
| `som-id: write rejected by the EEPROM` o `read-back differs` | pin WP dell'EEPROM alto (docs/EEPROM-ID.md) |
| `rootfs: manca /boot/zImage` in `make check` | `BR2_LINUX_KERNEL_INSTALL_TARGET` attivato dopo la build del kernel: `make linux-reinstall && make` |
