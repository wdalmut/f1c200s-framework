# EEPROM di identificazione: schema dei 64 byte e tool `som-id` — design

## Intento

Ogni SoM della famiglia (SODIMM 260 pin oggi, SMARC 2.1 domani) ha su I2C0,
indirizzo `0x50`, una EEPROM da 24C02 o più grande che dice **che cos'è
quel modulo e quale esemplare è**: codice prodotto, revisione, variante,
seriale, MAC delle porte Ethernet, e i pochi dati che servono all'SPL prima
della DRAM. Il device tree resta l'unica fonte di verità sulle periferiche:
l'EEPROM non descrive l'hardware.

Questo è il punto 2 del lavoro previsto in
[EGARE-F1C200S.md](../../EGARE-F1C200S.md) ("Lavoro futuro", passo 1:
schema dei 64 byte e tool per scriverli). La lettura da U-Boot (`ethaddr`,
`eth1addr`, `serial#`, fixup del DT) è il giro successivo, con il suo
design.

Il contenuto si scrive **una sola volta in produzione**, dalla board stessa
sotto Linux, e poi si protegge con il pin WP. Test, riparazioni e
aggiornamenti stanno nel database di produzione, indicizzati dal seriale.

## Obiettivi

- Lo schema v1.0 scritto in un documento che si possa incollare nella
  specifica della famiglia (`SPEC.md` della repo `som-id`).
- Un tool `som-id` nel rootfs EGARE che compone, scrive, rilegge e verifica
  il record, e lo stampa in forma leggibile da uno script di collaudo.
- Il parser del record in un file C senza dipendenze da Linux, da riusare
  tale e quale in U-Boot (proper e SPL) nel giro successivo.
- Da Linux, i campi esposti come celle nvmem in sysfs.
- Test del parser e del tool che girano in CI senza build Buildroot, su
  armv5, armv7, arm64 e x86_64.
- `make O=output-egare check` che verifica celle nvmem e tool nella build.

## Non-obiettivi

- U-Boot che legge l'EEPROM: variabili d'ambiente, fixup del DT, fallback
  dal SID. Giro successivo.
- Lettura nell'SPL e uso del campo Configurazione DDR. Sulla F1C200s la
  DRAM è nel package: il campo vale `0x00` e l'SPL non legge l'EEPROM.
- Collegamento al database di produzione, assegnazione di seriali e MAC,
  acquisto del blocco IEEE.
- La EEPROM della carrier e la scelta degli overlay.
- La FTVOGUE: non ha la EEPROM a `0x50`, e resta solo riferimento.

## Anti-obiettivi

- **`nvmem-cells` sui nodi Ethernet.** I MAC a Linux li darà U-Boot, dopo
  aver verificato magic e CRC, con `local-mac-address`. Una cella nvmem
  sul nodo Ethernet entrerebbe in gioco proprio quando U-Boot ha giudicato
  il record non valido, e Linux userebbe un indirizzo non verificato.
- **`read-only` nel DT dell'EEPROM.** Impedirebbe la scrittura di
  produzione da Linux. La protezione è solo il pin WP.
- Un tool che riscrive in silenzio un'EEPROM già programmata.
- Un parser che usa un campo di un record con magic o CRC sbagliati.
- Qualunque cambiamento negli artefatti FTVOGUE: `make check` sulla build
  FTVOGUE deve dare gli stessi `ok` di prima.

## Approcci

Il nodo era **chi scrive l'EEPROM in produzione e da dove**.

- **A. Dalla board, sotto Linux, con un tool C — scelto.** Il tool è un
  package Buildroot nel rootfs; il collaudo lo lancia in console. Il parser
  C si riusa in U-Boot. Costo: niente `read-only` nel DT, la protezione è
  solo il WP.
- B. Dalla stazione di collaudo con un adattatore I2C esterno: tool sul PC,
  board passiva. Richiede accesso fisico al bus I2C0 in produzione.
- C. Da U-Boot con `i2c`/`eeprom`: oggi U-Boot non ha né il driver
  `mvtwsi` né i comandi; comporre il record e il CRC nella shell di U-Boot
  è scomodo.

Tool, parser e specifica vivono in una repo propria, `som-id`, perché
servono a tutta la famiglia (scelta dell'utente: pubblica, MIT, in
inglese).

Il tool è in C (scelta di chi scrive il design): la shell BusyBox del
rootfs non calcola comodamente un CRC16, nel rootfs non c'è Python, e lo
stesso parser serve a U-Boot.

## Schema v1.0

### Layout (64 byte)

| Offset | Dim | Campo | Codifica | Note |
|---|---|---|---|---|
| 0x00 | 4 | Magic | ASCII `"SMID"` = `53 4D 49 44` | **fisso in tutte le versioni**; confronto byte per byte |
| 0x04 | 1 | Versione schema | nibble alto major, nibble basso minor | **fisso**; `0x10` = 1.0 |
| 0x05 | 1 | Revisione HW | uint8 | **fisso**; 1–254 |
| 0x06 | 2 | Codice prodotto | uint16 LE | **fisso**; `0x0000` e `0xFFFF` non validi; un intervallo per famiglia |
| 0x08 | 1 | Variante | uint8 | **fisso**; `0x00` = base; mai usata per la RAM |
| 0x09 | 1 | Configurazione DDR | uint8, indice nella tabella del prodotto | **fisso**; `0x00` = non usata |
| 0x0A | 2 | RAM | uint16 LE, MiB | **fisso**; valore dichiarato, confrontato con quello rilevato |
| 0x0C | 4 | Riservati intestazione | `0x00` | **fisso** |
| 0x10 | 6 | MAC ETH0 | 6 byte, ordine di rete | `FF…FF` = porta assente |
| 0x16 | 6 | MAC ETH1 | 6 byte, ordine di rete | come ETH0; nessuna contiguità presunta |
| 0x1C | 12 | Seriale | ASCII `0-9A-Z`, senza terminatore | `PPYYWWNNNNNC` |
| 0x28 | 22 | Riservati | `0x00` | campi futuri (minor): `0x00` = assente |
| 0x3E | 2 | CRC16 | uint16 LE | **fisso**; CRC-16/CCITT-FALSE su `0x00–0x3D` |
| 0x40 | 192 | Non usati | `0xFF` | fuori dal CRC |

"Fisso" vuol dire: posizione e significato non cambiano in nessuna
versione major. L'SPL legge solo l'intestazione e il CRC, quindi funziona
anche con una major che non conosce.

### Codifiche

- **Magic**: 4 byte confrontati come sequenza, mai come `uint32`.
- **Versione**: una minor nuova aggiunge campi solo nei byte riservati, con
  `0x00` = assente. Una major nuova può cambiare `0x10–0x3D`.
- **MAC**: nell'ordine in cui vanno sul cavo, eccezione alla regola
  "multibyte LE". Uno slot è valido se è unicast e non tutto zero. `FF…FF`
  vuol dire porta assente. Il bit "locally administered" è un errore in
  produzione (gli indirizzi vengono da un blocco IEEE MA-S proprio), ma è
  ammesso per i prototipi.
- **Seriale**: `PP` stabilimento o fornitore EMS, 2 lettere A–Z escluse I
  e O; `YYWW` anno e settimana ISO 8601; `NNNNN` progressivo nella
  settimana, 00001–99999; `C` carattere di controllo Luhn mod 36 sui primi
  11 caratteri, alfabeto `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ`. Esempio:
  `MA264800017C`.
- **CRC16**: polinomio `0x1021` non riflesso, valore iniziale `0xFFFF`,
  XOR finale `0x0000`; su `"123456789"` dà `0x29B1`. Copre `0x00–0x3D`,
  scritto little-endian a `0x3E`. Calcolo bit per bit, senza tabella: è
  quello che entrerà nell'SPL.

### Stati del record

L'ordine dei controlli è: lettura → vergine → magic → CRC → major →
campi.

| Stato | Quando |
|---|---|
| `absent` | la lettura del file fallisce (NACK, device assente) |
| `blank` | i 64 byte valgono tutti `0xFF` |
| `badmagic` | i primi 4 byte non sono `SMID` |
| `badcrc` | CRC calcolato diverso da quello scritto |
| `badversion` | major diversa da 1. Si usano solo i campi dell'intestazione `0x00–0x0F` |
| `ok` | tutto il resto. Campi singoli non validi si segnalano a parte (vedi "Campi non validi") e non cambiano lo stato |

Lo stato `ok` con minor maggiore di 0 è normale: si leggono i campi noti.

### Campi non validi

Con stato `ok` (o `badversion`, solo per i campi dell'intestazione) il
parser segna come non validi, uno per uno:

| Campo | Non valido se |
|---|---|
| `product` | `0x0000` o `0xFFFF` |
| `rev` | `0` o `255` |
| `ram_mib` | `0` |
| `mac0`, `mac1` | multicast o tutto zero (`FF…FF` è "assente", non "non valido"); con il bit locale solo se chi legge non lo ammette |
| `serial` | caratteri fuori da `0-9A-Z`, `PP` con cifre, I o O, settimana fuori da 01–53, `NNNNN` = `00000`, carattere di controllo sbagliato |
| `reserved` | con minor = 0, un byte diverso da `0x00` in `0x0C–0x0F` o `0x28–0x3D`; con minor > 0 i riservati non si controllano |

Quali porte un prodotto deve avere non lo sa il parser: lo dice il DT
(U-Boot) o lo script di collaudo, che conosce il prodotto.

Il confronto fra RAM dichiarata e RAM rilevata lo fanno SPL e U-Boot con
`get_ram_size()`, non il tool: da Linux `MemTotal` è sempre minore della
RAM fisica.

### Regole per chi legge (per la specifica)

Il tool le applica per quanto lo riguarda; U-Boot e SPL le applicheranno
nel giro successivo.

- Nessun campo di un record che non è `ok` (o `badversion`, solo per
  l'intestazione) va usato.
- U-Boot proper non blocca mai il boot per l'EEPROM.
- L'SPL, quando un prodotto ha più configurazioni DDR, fa fallback sulla
  configurazione di default dell'immagine verificata con `get_ram_size()`;
  si ferma solo se nessuna voce della tabella passa la verifica, o se il
  codice prodotto non è quello dell'immagine.
- Un indice DDR vale solo dentro il suo codice prodotto e non cambia mai
  significato. Un taglio di RAM diverso non è mai una Variante.

## Design

### Dove vive il codice

Parser, tool, specifica dello schema e test servono a tutta la famiglia,
anche a board con altri SoC e altri sistemi di build. Vivono quindi in una
repo propria, **`som-id`**:

- remote `git@github.com:egaree/som-id.git`, pubblica;
- checkout locale `/home/walter/git/som-id`, accanto a questo progetto;
- licenza **MIT**, `Copyright (c) 2026 Walter Dal Mut`;
- **in inglese**: README, `SPEC.md`, commenti, messaggi del tool;
- un tag per rilascio, `v1.0.0` per il primo (schema 1.0).

In questo repo restano il package Buildroot, il DTS EGARE, `make check` e
i documenti, che rimandano a `som-id` per lo schema.

### Repo `som-id`

```
LICENSE              MIT
README.md            cos'è, come si compila, come si usa, architetture provate
SPEC.md              schema v1.0 (la sezione "Schema v1.0" di questo design, in inglese)
Makefile             target: all (som-id), test, check, install, clean
src/som_id.h         record, stati, prototipi
src/som_id.c         parser, builder, CRC, carattere di controllo, MAC
src/main.c           CLI
tests/test.c         test unitari del parser
tests/test-cli.sh    test del tool su un file al posto dell'EEPROM
.github/workflows/ci.yml
```

**Makefile.** Rispetta `CC`, `CFLAGS`, `LDFLAGS`, `DESTDIR`, `PREFIX`
(default `/usr/local`); aggiunge sempre `-std=c99 -Wall -Wextra -Werror`.
`install` mette `som-id` in `$(DESTDIR)$(PREFIX)/bin`. `check` esegue
`tests/test` e `tests/test-cli.sh` sui binari appena compilati. Così lo
usano allo stesso modo Buildroot, Yocto o una compilazione a mano.

**Portabilità.** Il record si legge e si scrive byte per byte: niente
struct sovrapposte al buffer, niente letture non allineate, niente
ipotesi su endianness o dimensione delle parole (la matrice prova
ARM a 32 e 64 bit; il big-endian non è un obiettivo). Il codice deve compilare
senza warning con glibc e con musl.

**CI (`ci.yml`), matrice:**

| Architettura | Compilatore | Esecuzione dei test |
|---|---|---|
| x86_64 | `gcc` nativo | diretta |
| armv5 (ARM926) | `arm-linux-gnueabi-gcc -march=armv5te -marm` | qemu-user |
| armv7 | `arm-linux-gnueabihf-gcc` | qemu-user |
| arm64 | `aarch64-linux-gnu-gcc` | qemu-user |

Per i target incrociati i binari sono statici (`LDFLAGS=-static`), così
qemu-user li esegue senza le librerie del target (con `qemu-user-static`
e binfmt si lanciano direttamente). Su ogni architettura girano sia
`tests/test` sia `tests/test-cli.sh`. In più, nel job x86_64:
`shellcheck` su `tests/test-cli.sh` e il controllo degli include di
`som_id.[ch]`.

### `src/som_id.c` / `src/som_id.h`

C99, MIT. Include solo `<stdint.h>`, `<stddef.h>`, `<string.h>`: niente
`stdio`, `malloc`, `errno`, così il file si compila anche dentro U-Boot
(la MIT è compatibile con la sua GPL). Interfaccia:

- `struct som_id`: i campi decodificati (versione, revisione, prodotto,
  variante, DDR, RAM, due MAC come `uint8_t[6]`, seriale come
  `char[13]` con terminatore).
- `enum som_id_status`: `SOM_ID_OK`, `SOM_ID_BLANK`, `SOM_ID_BADMAGIC`,
  `SOM_ID_BADCRC`, `SOM_ID_BADVERSION`. `absent` è del chiamante, che sa
  se la lettura è fallita.
- `som_id_parse(const uint8_t buf[64], struct som_id *out)` → stato.
- `som_id_build(const struct som_id *in, uint8_t buf[64])`: scrive
  riservati a `0x00` e CRC.
- `som_id_crc16(const uint8_t *buf, size_t len)`.
- `som_id_serial_check(const char *s11)` → carattere di controllo, e
  `som_id_serial_valid(const char *s12)`.
- `som_id_mac_valid(const uint8_t mac[6])`, `som_id_mac_absent(...)`,
  `som_id_mac_local(...)`.

### Il tool `som-id`

```
som-id [-d PATH] show
som-id [-d PATH] verify [--allow-local]
som-id [-d PATH] write --product N --rev N --ram MIB --serial S
                       [--variant N] [--ddr N]
                       [--mac0 xx:xx:xx:xx:xx:xx] [--mac1 ...]
                       [--allow-local] [--force]
som-id serial PPYYWWNNNNN
```

- `-d`: per default `/sys/bus/i2c/devices/0-0050/eeprom`. Qualunque file
  da almeno 64 byte va bene: i test usano un file normale.
- `show`: stampa righe `chiave=valore`, una per campo, in quest'ordine:
  `status`, `version`, `product`, `rev`, `variant`, `ddr`, `ram_mib`,
  `mac0`, `mac1`, `serial`, `invalid`. Prodotto in esadecimale `0x0001`,
  MAC assente come `none`. `invalid` è l'elenco, separato da virgole, dei
  campi non validi della tabella "Campi non validi" (vuoto se nessuno);
  per ognuno anche una riga su stderr. Con stato diverso da `ok` stampa
  solo `status` (e l'intestazione più `invalid` per `badversion`). Esce
  con 0 se ha letto il file, anche se il record non è valido.
- `verify [--allow-local]`: come `show`, ma esce con 0 solo se lo stato è
  `ok` e `invalid` è vuoto; 1 se il record non va; 2 per errori di uso o
  di lettura. Senza `--allow-local` un MAC con il bit locale è non valido:
  così la stazione di collaudo, che non lo passa, scarta un MAC di
  prototipo. È quello che usa il collaudo.
- `write`:
  - controlla gli argomenti: prodotto 1–0xFFFE, revisione 1–254, variante
    e DDR 0–255 (default 0), RAM 1–65535 obbligatoria, seriale valido
    (`som_id_serial_valid`), MAC unicast e non zero; MAC con il bit locale
    rifiutati senza `--allow-local`; una porta senza `--macN` resta
    `FF…FF`;
  - legge i primi 64 byte: se non sono tutti `0xFF` rifiuta, a meno di
    `--force`;
  - scrive i 64 byte all'offset 0, rilegge e confronta byte per byte;
  - se la scrittura fallisce o la rilettura è diversa, lo dice e suggerisce
    il pin WP come prima causa; esce con 1.
- `serial`: stampa il seriale completo di carattere di controllo. Serve al
  collaudo e ai test.
- Messaggi d'errore su stderr, in inglese.

### `tests/test-cli.sh`

Compila (o riceve) `som-id` e `test`, poi:

1. `test` passa: CRC `0x29B1` su `"123456789"`; carattere di controllo
   `C` per `MA264800017`; parse di un record costruito.
2. Su un file da 256 byte tutti `0xFF`: `show` dà `status=blank`,
   `verify` esce con 1.
3. `write` con valori noti; il file risultante è uguale byte per byte a un
   record costruito **indipendentemente** in Python 3 (`struct`,
   `binascii.crc_hqx(data, 0xffff)`) dentro lo script; i byte da `0x40` in
   poi restano `0xFF`.
4. Un secondo `write` senza `--force` fallisce e non tocca il file; con
   `--force` riesce.
5. Un byte cambiato nel record: `status=badcrc`. Magic cambiato:
   `badmagic`. Versione `0x20` con CRC ricalcolato: `badversion`.
6. Argomenti rifiutati: seriale con carattere di controllo sbagliato, MAC
   multicast, MAC locale senza `--allow-local`, prodotto `0`.
7. Campi non validi con CRC giusto (record costruito in Python): ognuno
   della tabella "Campi non validi" compare in `invalid=` e fa uscire
   `verify` con 1; un MAC locale passa solo con `verify --allow-local`.

Python serve solo sulla macchina che esegue i test (in CI, il runner),
non sul target.

### Package Buildroot (questo repo)

- `som-id.mk`: `generic-package`, `SOM_ID_VERSION = 1.0.0`,
  `SOM_ID_SITE = $(call github,egaree,som-id,v$(SOM_ID_VERSION))`,
  `SOM_ID_LICENSE = MIT`, `SOM_ID_LICENSE_FILES = LICENSE`; build
  `$(MAKE) CC="$(TARGET_CC)" ...` e install con
  `$(MAKE) DESTDIR=$(TARGET_DIR) PREFIX=/usr install`.
- `som-id.hash`: sha256 dell'archivio del tag e di `LICENSE`. Si calcola
  dopo il push del tag: il package si completa solo dopo.
- Per lavorare su un checkout locale senza tag:
  `SOM_ID_OVERRIDE_SRCDIR = /home/walter/git/som-id` in
  `output-egare/local.mk` (non va nel repo).
- `Config.in`: `BR2_PACKAGE_SOM_ID`, con help di una riga.
- `external/Config.in`: `source` del package; via i commenti "nessun
  package". Commento di `external.mk` aggiornato.
- `egare_f1c200s_defconfig`: `BR2_PACKAGE_SOM_ID=y`, rigenerato con
  `savedefconfig`. Il defconfig FTVOGUE non cambia.

### DTS EGARE

Sotto `eeprom@50` (nient'altro cambia nel nodo):

```dts
nvmem-layout {
	compatible = "fixed-layout";
	#address-cells = <1>;
	#size-cells = <1>;

	som-id@0 { reg = <0x00 0x40>; };
	mac-address@10 { reg = <0x10 0x06>; };
	mac-address@16 { reg = <0x16 0x06>; };
	serial-number@1c { reg = <0x1c 0x0c>; };
};
```

Il kernel ha già `CONFIG_NVMEM_SYSFS=y` e `CONFIG_NVMEM_LAYOUTS=y`: i
fragment non cambiano. Le celle compaiono in
`/sys/bus/nvmem/devices/*/cells/`.

### `docs/check-image.sh`

Nella sezione 12 (solo DTB EGARE):

- `eeprom@50` ha `nvmem-layout` con `compatible = "fixed-layout"`;
- le quattro celle hanno i `reg` della tabella sopra;
- `eeprom@50` **non** ha `read-only` né `wp-gpios` (con `wp-gpios` nvmem
  sbloccherebbe il WP a ogni scrittura);
- nessun nodo del DTB ha `nvmem-cells` che punta a una cella MAC
  dell'EEPROM;
- il rootfs ha `/usr/bin/som-id` (stesso metodo della sezione 11).

### Documenti (questo repo, in italiano)

- `docs/EEPROM-ID.md`: breve. Rimanda a `SPEC.md` di `som-id` per lo
  schema; qui solo cosa vale per la EGARE (celle nvmem, come programmare
  con `som-id`, cosa fare se `write` fallisce), la scelta del blocco MA-S
  (4096 indirizzi, solo le porte montate li consumano) e cosa manca
  (U-Boot, SPL).
- [EGARE-SPEC-SODIMM.md](../../EGARE-SPEC-SODIMM.md), "MAC dell'ETH0":
  via la cella a `0x2D` e le `nvmem-cells` sul nodo Ethernet; il MAC
  arriverà da U-Boot con `local-mac-address` (giro successivo), il nodo
  dell'hub e dell'Ethernet nel DT resta da fare. Riga EEPROM nella tabella
  dei pin aggiornata.
- [EGARE-F1C200S.md](../../EGARE-F1C200S.md): "Lavoro futuro" con il passo
  1 fatto e il link a EEPROM-ID.md; la sezione EEPROM con le celle nvmem.
- `external/board/egare-f1c200s/readme.txt`: come programmare l'EEPROM.
- `CLAUDE.md`: struttura (`external/package/som-id/`, `docs/EEPROM-ID.md`),
  riga in "Dove si cambia cosa" (schema → repo `som-id`, nuovo tag, poi
  `SOM_ID_VERSION` e hash), riga in "Sintomi → causa" per `som-id write`
  che fallisce (pin WP).
- `docs/SCELTE-DI-PROGETTO.md`: un paragrafo sul perché (DT unica fonte,
  scrittura da Linux, repo separata, niente `nvmem-cells` sull'Ethernet,
  slot espliciti per i MAC).

## Verifica

1. In `som-id`: `make check` passa sul PC; la CI passa su tutta la
   matrice.
2. Build FTVOGUE: `make check` con gli stessi `ok` di prima; defconfig
   FTVOGUE senza diff.
3. Build EGARE: `make O=output-egare linux-rebuild && make
   O=output-egare`, poi `make O=output-egare check` tutto `ok`;
   `savedefconfig` senza diff.
4. Su board EGARE (l'EEPROM oggi è vergine e il WP non è attivo):
   - `som-id show` → `status=blank`;
   - `som-id write --product 0x0001 --rev 1 --ram 64 --serial
     $(som-id serial MA264800017) --mac0 02:00:00:00:00:01
     --allow-local` → scritto e verificato;
   - `som-id verify` esce con 1 (`invalid=mac0`), `som-id verify
    --allow-local` esce con 0;
   - `ls /sys/bus/nvmem/devices/*/cells/` mostra le quattro celle, e
     `hexdump -C` della cella `serial-number` dà `MA264800017C`.

   Codice prodotto e MAC sono valori di prova: l'EGARE non ha ancora un
   codice prodotto assegnato né un MAC dal blocco IEEE. Dopo la prova
   l'EEPROM si può lasciare scritta (verrà riscritta con `--force`) o
   rimettere a `0xFF`.

## Ipotesi

Confermate dall'utente con l'approvazione del documento, senza verifica:

- L'offset `0x2D` di EGARE-SPEC-SODIMM.md era un segnaposto: la specifica
  *Pinout SoM SODIMM 260-pin* non fissa una mappa dell'EEPROM, e la v1.0
  non deve restare compatibile con niente.
- Il collegamento del pin WP sulla EGARE non è documentato (il 27/11 la
  scrittura è riuscita, quindi oggi è basso). Il DT non lo descrive e il
  tool non lo pilota: in caso di scrittura fallita suggerisce solo di
  controllarlo.

## Lasciato a chi implementa

- Ordine dei commit e testo dei messaggi.
- Struttura interna di `main.c` e parsing degli argomenti (`getopt_long`
  va bene).
- Versioni delle action e dei pacchetti nella CI di `som-id`.
- Forma esatta dei messaggi d'errore.
- Come `check-image.sh` legge il DTB (`fdtget`/`dtc` come nelle sezioni
  esistenti).
