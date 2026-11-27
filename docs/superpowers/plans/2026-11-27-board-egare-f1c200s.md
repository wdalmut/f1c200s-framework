# Board EGARE F1C200S — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** un secondo defconfig `egare_f1c200s_defconfig` che costruisce la board EGARE (W25N02KV, M24C02 su i2c0) sopra i file della FTVOGUE, senza cambiare gli artefatti della FTVOGUE.

**Architecture:** `external/board/egare-f1c200s/` contiene solo le differenze (DTS che include quello Lctech, fragment che si applicano dopo quelli FTVOGUE, `genimage.cfg`). `check-image.sh` smette di avere il nome del DTB scritto dentro; la CI verifica che i file copiati restino equivalenti a quelli FTVOGUE.

**Tech Stack:** Buildroot 2026.02.3 (submodule, non si tocca), Linux 6.12.111, U-Boot 2026.07, bash, GitHub Actions.

**Spec:** [docs/superpowers/specs/2026-11-27-board-egare-f1c200s-design.md](../specs/2026-11-27-board-egare-f1c200s-design.md)

## Global Constraints

- `buildroot/` non si modifica mai.
- Nei defconfig i percorsi si scrivono con `$(BR2_EXTERNAL_F1C200S_PATH)`, mai relativi.
- Ogni defconfig deve uscire invariato da `savedefconfig` (lo controlla la CI).
- Nessun file in `external/board/ftvogue-f1c200s/` e `external/configs/ftvogue_f1c200s_defconfig` cambia.
- Nomi fissi: directory `external/board/egare-f1c200s/`, DTS `dts/allwinner/suniv-f1c200s-egare.dts`, DTB `suniv-f1c200s-egare.dtb`, `model = "EGARE F1C200S"`, hostname `egare-f1c200s`, issue `EGARE F1C200S - mainline`, output `output-egare/`.
- `BR2_TARGET_ROOTFS_UBIFS_MAXLEBCNT=2040` solo per EGARE.
- EEPROM: `eeprom@50`, `compatible = "st,24c02", "atmel,24c02"`, `reg = <0x50>`, `pagesize = <16>`; pin `PE11`, `PE12`, funzione `i2c0`.
- Documenti e commenti in italiano, stile del repo; commit che finiscono con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Build FTVOGUE dopo la modifica a `check-image.sh`**: deve dare gli stessi `ok` di prima più il nuovo controllo sul DTB nel bootcmd. Coperto dal confronto con la baseline nel Task 1.
2. **Due DTB in `images/`** (per esempio `INTREE_DTS_NAME` lasciato insieme a `CUSTOM_DTS_DIR`): `check-image.sh` deve fallire con un messaggio chiaro, non sceglierne uno a caso. Test nel Task 1.
3. **`bootcmd` EGARE che carica ancora il DTB Lctech**: si scoprirebbe solo sulla board. Coperto da `check-image.sh` (Task 1) e dal controllo di equivalenza in CI (Task 3, con prova negativa).
4. **Build EGARE lanciata senza `O=`**: sovrascriverebbe `output/` della FTVOGUE. Non si impedisce, ma ogni comando documentato usa `O=output-egare` (Task 2 e 4).
5. **`MAXLEBCNT` troppo basso o troppo alto rispetto ai LEB reali**: si vede solo con `df` sulla board. Verifica nel Task 5.

---

### Task 1: `check-image.sh` senza nome del DTB scritto dentro

**Files:**
- Modify: `docs/check-image.sh` (sezioni 3, 6, 7, 11; nuova sezione 12)

**Interfaces:**
- Produces: `check-image.sh <images>` ricava il DTB come unico `*.dtb` in `<images>`; per `suniv-f1c200s-egare.dtb` esegue la sezione 12 (i2c0/EEPROM/AT24). Usato dai Task 2 e 5.

- [ ] **Step 1: baseline sulla build FTVOGUE esistente**

Run: `./docs/check-image.sh output/images > /tmp/check-before.txt; echo rc=$?`
Expected: `rc=0`, `tutto a posto.`

- [ ] **Step 2: implementare**

- In cima, dopo il controllo su `$IMAGES`: `dtbs=("$IMAGES"/*.dtb)`; se zero file esistenti → `fail "nessun DTB in $IMAGES"`, se più d'uno → `fail "piu' DTB in $IMAGES: <elenco>"`; in entrambi i casi `exit 1`. Altrimenti `DTB_NAME="$(basename "${dtbs[0]}")"`.
- `expected_model` per `case "$DTB_NAME"`: `suniv-f1c200s-lctech-pi.dtb` → `Lctech Pi F1C200s`; `suniv-f1c200s-egare.dtb` → `EGARE F1C200S`; altro → `fail "DTB sconosciuto: $DTB_NAME"`.
- Sezioni 3, 7, 11: `suniv-f1c200s-lctech-pi.dtb` → `$DTB_NAME`; sezione 7 confronta con il model atteso.
- Sezione 4, nuovo controllo dentro il blocco `ucfg`: nella riga `CONFIG_BOOTCOMMAND=` il nome `$DTB_NAME` compare **2** volte (ramo SD e ramo NAND) → `pass "u-boot: bootcmd carica $DTB_NAME in entrambi i rami"`, altrimenti `fail` con il numero trovato. Usare `grep -o … | wc -l`, non `grep -c` (conta le righe).
- Sezione 4: `CONFIG_DEFAULT_DEVICE_TREE="allwinner/suniv-f1c200s-lctech-pi"` resta fisso: è il DT di U-Boot, uguale per le due board (commento che lo dice).
- Nuova sezione 12, solo se `DTB_NAME=suniv-f1c200s-egare.dtb`: con `dtc -I dtb -O dts`, il nodo `i2c@1c27000` ha `status = "okay"` e contiene `eeprom@50`; nel `.config` del kernel `CONFIG_EEPROM_AT24=y`. `skip` se `dtc` o il `.config` mancano, come nelle altre sezioni.
- Commento della sezione 10: "GD5F1GQ4xA" → "GD5F1GQ4xA e W25N02KV". Il limite di 127 MiB resta: vale per entrambe.

- [ ] **Step 3: confronto con la baseline**

Run: `./docs/check-image.sh output/images > /tmp/check-after.txt; echo rc=$?; diff /tmp/check-before.txt /tmp/check-after.txt`
Expected: `rc=0`; il diff mostra solo la riga aggiunta `ok    u-boot: bootcmd carica suniv-f1c200s-lctech-pi.dtb in entrambi i rami`.

- [ ] **Step 4: due DTB e nessun DTB**

Run:
```bash
T=$(mktemp -d); cp -a output/images "$T/"; cp "$T/images/suniv-f1c200s-lctech-pi.dtb" "$T/images/altro.dtb"
./docs/check-image.sh "$T/images"; echo rc=$?
rm "$T/images/"*.dtb; ./docs/check-image.sh "$T/images"; echo rc=$?; rm -rf "$T"
```
Expected: prima `KO    piu' DTB in …` e `rc=1`; poi `KO    nessun DTB in …` e `rc=1`.

- [ ] **Step 5: shellcheck e commit**

Run: `shellcheck -S warning docs/check-image.sh` → nessun output.

```bash
git add docs/check-image.sh
git commit -m "check-image: DTB ricavato da images/, controllo del DTB nel bootcmd"
```

---

### Task 2: board EGARE

**Files:**
- Create: `external/board/egare-f1c200s/dts/allwinner/suniv-f1c200s-egare.dts`
- Create: `external/board/egare-f1c200s/linux.fragment`
- Create: `external/board/egare-f1c200s/uboot.fragment`
- Create: `external/board/egare-f1c200s/genimage.cfg`
- Create: `external/board/egare-f1c200s/readme.txt`
- Create: `external/configs/egare_f1c200s_defconfig`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `check-image.sh` del Task 1.
- Produces: `make O=output-egare egare_f1c200s_defconfig && make O=output-egare` → `output-egare/images/{sdcard.img,u-boot-sunxi-with-spl.bin,rootfs.ubi,suniv-f1c200s-egare.dtb}`.

- [ ] **Step 1: file della board**

- DTS: header SPDX/Copyright come gli altri file; `#include "suniv-f1c200s-lctech-pi.dts"`; `/ { model = "EGARE F1C200S"; };`; gruppo `i2c0_pe_pins: i2c0-pe-pins` in `&pio`; `&i2c0` con `pinctrl-names`, `pinctrl-0`, `status = "okay"` e il nodo EEPROM delle Global Constraints. Commento con pin del package (PE11 = pin 38 SCK, PE12 = pin 37 SDA) e data della verifica.
- `linux.fragment`: commento + `CONFIG_EEPROM_AT24=y`.
- `uboot.fragment`: commento ("si applica dopo quello FTVOGUE e cambia solo il DTB; la CI ne verifica l'equivalenza") + la riga `CONFIG_BOOTCOMMAND=` copiata da `external/board/ftvogue-f1c200s/uboot.fragment` con `suniv-f1c200s-lctech-pi.dtb` → `suniv-f1c200s-egare.dtb` (2 occorrenze).
- `genimage.cfg`: copia di quello FTVOGUE con lo stesso cambio di nome.
- `readme.txt`: come quello FTVOGUE, con i comandi `O=output-egare`, `./docs/flash-nand.sh output-egare/images`, e il rimando a `docs/EGARE-F1C200S.md`.
- `.gitignore`: `/output-*/` sotto `/output/`.

- [ ] **Step 2: defconfig**

Partire da una copia di `ftvogue_f1c200s_defconfig` e applicare la tabella del design (hostname, issue, genimage, due fragment kernel, niente `INTREE_DTS_NAME`, `BR2_LINUX_KERNEL_CUSTOM_DTS_DIR="$(BR2_EXTERNAL_F1C200S_PATH)/board/egare-f1c200s/dts"`, `MAXLEBCNT=2040`, due fragment U-Boot). Poi:

Run: `make O=output-egare egare_f1c200s_defconfig && make O=output-egare savedefconfig && git diff --stat external/configs/`
Expected: il defconfig EGARE riscritto in forma canonica; nessun diff su `ftvogue_f1c200s_defconfig`.

Run: `grep -E '^BR2_(LINUX_KERNEL_CUSTOM_DTS_DIR|LINUX_KERNEL_INTREE_DTS_NAME|TARGET_ROOTFS_UBIFS_MAXLEBCNT|TARGET_UBOOT_CONFIG_FRAGMENT_FILES|LINUX_KERNEL_CONFIG_FRAGMENT_FILES)=' output-egare/.config`
Expected: `CUSTOM_DTS_DIR` sulla directory EGARE, `INTREE_DTS_NAME=""`, `MAXLEBCNT=2040`, due fragment ciascuno con FTVOGUE prima di EGARE.

- [ ] **Step 3: build**

Run (lunga: toolchain inclusa; con `DL_DIR` condiviso si evita di riscaricare): `make O=output-egare`
Expected: termina senza errori; `ls output-egare/images/*.dtb` → solo `suniv-f1c200s-egare.dtb`.

- [ ] **Step 4: check**

Run: `make O=output-egare check`
Expected: `tutto a posto.`, con `ok    DTB: model = "EGARE F1C200S"`, `ok    u-boot: bootcmd carica suniv-f1c200s-egare.dtb in entrambi i rami`, e la sezione 12 tutta `ok`.

- [ ] **Step 5: FTVOGUE intatta**

Run: `git status --short external/board/ftvogue-f1c200s external/configs/ftvogue_f1c200s_defconfig`
Expected: nessun output.

- [ ] **Step 6: commit**

```bash
git add .gitignore external/board/egare-f1c200s external/configs/egare_f1c200s_defconfig
git commit -m "board: EGARE F1C200S, con EEPROM M24C02 su i2c0 e UBIFS su 256 MiB"
```

---

### Task 3: CI per due board

**Files:**
- Modify: `.github/workflows/checks.yml` (step "il kernel resta ARMv5/suniv"; nuovo step nel job `defconfig`)

**Interfaces:**
- Consumes: i file del Task 2.

- [ ] **Step 1: ARMv5 per defconfig, non per fragment**

Sostituire il ciclo `for f in external/board/*/linux.fragment` con: per ogni `out-$name/.config`, leggere `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`, espandere `$(BR2_EXTERNAL_F1C200S_PATH)` in `$PWD/external`, e richiedere che **almeno uno** dei file contenga `# CONFIG_ARCH_MULTI_V7 is not set` e almeno uno `CONFIG_MACH_SUNIV=y`. Errore: `::error::$name: nessun fragment disattiva ARCH_MULTI_V7` (e analogo).

- [ ] **Step 2: equivalenza EGARE/FTVOGUE**

Nuovo step "i file EGARE copiati da FTVOGUE restano equivalenti": per `genimage.cfg`, e per la sola riga `CONFIG_BOOTCOMMAND=` di `uboot.fragment`, il file EGARE con `suniv-f1c200s-egare.dtb` → `suniv-f1c200s-lctech-pi.dtb` deve essere identico (genimage) o uguale alla riga FTVOGUE (bootcmd). `diff` stampa la differenza; errore `::error::…diverge da FTVOGUE`.

- [ ] **Step 3: provare in locale**

Run: eseguire i blocchi `run:` dei due step con `bash -euo pipefail` dopo aver generato `out-*_defconfig/.config` come fa il job (`make -C buildroot O="$PWD/out-$name" BR2_EXTERNAL="$PWD/external" "$name"` per ciascun defconfig).
Expected: entrambi `ok`.

- [ ] **Step 4: prove negative**

Run: cambiare a mano `0x81800000` in `0x81900000` nel `bootcmd` EGARE e rieseguire lo step 2; poi `git checkout` del file. Ripetere togliendo temporaneamente `CONFIG_MACH_SUNIV=y` dal fragment FTVOGUE e rieseguire lo step 1; poi `git checkout`.
Expected: entrambe le volte errore e uscita ≠ 0; dopo il ripristino `git status` pulito su quei file.

- [ ] **Step 5: commit**

```bash
git add .github/workflows/checks.yml
git commit -m "ci: controlli per defconfig, equivalenza dei file EGARE con FTVOGUE"
```

---

### Task 4: documentazione

**Files:**
- Create: `docs/EGARE-F1C200S.md`
- Modify: `CLAUDE.md` (Struttura, Comandi, "Dove si cambia cosa")
- Modify: `README.md` (Struttura; sezione breve "Altre board")

- [ ] **Step 1: scrivere**

- `docs/EGARE-F1C200S.md`: perché esiste (board confrontata con la FTVOGUE di riferimento), differenze hardware con fonte e data dal design (W25N02KV, M24C02 con pin, indirizzo, prove fatte), cosa ancora non è verificato (boot da NAND finché il Task 5 non lo conferma), comandi con `O=output-egare`, rimando ai punti 2 e 3 come lavoro futuro.
- `CLAUDE.md`: in Struttura `configs/egare_f1c200s_defconfig` e `board/egare-f1c200s/` con una riga per file; in Comandi le due righe `O=output-egare`; in "Dove si cambia cosa" la riga "Cambiare qualcosa solo per la EGARE | `external/board/egare-f1c200s/` | stesso flusso, con `O=output-egare`" e una nota che un fragment FTVOGUE vale per entrambe.
- `README.md`: in Struttura le stesse voci; sezione "Altre board" di poche righe con link a `docs/EGARE-F1C200S.md`.

- [ ] **Step 2: link**

Run: il controllo dei link della CI (blocco `run:` del job `docs`) in locale.
Expected: `rc=0`.

- [ ] **Step 3: commit**

```bash
git add docs/EGARE-F1C200S.md CLAUDE.md README.md
git commit -m "docs: board EGARE F1C200S"
```

---

### Task 5: verifica su board EGARE

Richiede la board e l'utente. Nessun file cambia, salvo l'esito in `docs/EGARE-F1C200S.md`.

- [ ] **Step 1: SD.** `sdcard.img` di `output-egare` su SD, boot. Sulla seriale `boot: SD`. Poi:
  `hexdump -C /sys/bus/i2c/devices/0-0050/eeprom | head` → 256 byte leggibili;
  scrivere un byte all'offset 255 con `printf '\xa5' | dd of=/sys/bus/i2c/devices/0-0050/eeprom bs=1 seek=255 conv=notrunc`, rileggerlo, rimettere `\xff`.
- [ ] **Step 2: NAND.** Board in FEL, `./docs/flash-nand.sh output-egare/images`, poi senza SD: `U-Boot SPL` → `boot: NAND` → login; `mount` mostra `ubi0:rootfs on / type ubifs`; `df -h /` circa 230-240 MiB; la EEPROM si legge anche da qui.
- [ ] **Step 3: registrare.** In `docs/EGARE-F1C200S.md` i punti confermati diventano fatti con data; se `df` è lontano dall'atteso, annotarlo e rivedere `MAXLEBCNT`. Commit `docs: board EGARE verificata su hardware`.
