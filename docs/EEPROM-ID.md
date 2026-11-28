# EEPROM di identificazione

Ogni SoM della famiglia ha su I2C0, indirizzo `0x50`, un'EEPROM che dice che
cos'è il modulo e quale esemplare è: codice prodotto, revisione, variante,
seriale, MAC delle porte Ethernet, configurazione DDR. Il device tree resta
l'unica fonte di verità sulle periferiche.

**Lo schema dei 64 byte non sta qui.** Vale per tutta la famiglia, quindi
vive con il parser e il tool nella repo
[egaree/som-id](https://github.com/egaree/som-id), in
[SPEC.md](https://github.com/egaree/som-id/blob/v1.0.0/SPEC.md) (schema
v1.0, tag `v1.0.0`). Questo documento dice solo cosa vale per la EGARE.
Perché è fatto così: [SCELTE-DI-PROGETTO.md](SCELTE-DI-PROGETTO.md),
"EEPROM di identificazione scritta da Linux"; il design completo è in
[superpowers/specs/2026-11-28-eeprom-id-design.md](superpowers/specs/2026-11-28-eeprom-id-design.md).

## Sulla EGARE

- EEPROM ST M24C02-FMN, 256 byte, su i2c0 (PE11/PE12), `0x50`. Il record
  occupa i primi 64 byte. Fatti e prove in
  [EGARE-F1C200S.md](EGARE-F1C200S.md).
- Il tool `som-id` è nel rootfs (`/usr/bin/som-id`), dal package
  `external/package/som-id/`, che fissa il tag della repo.
- Il DTS EGARE dichiara le celle nvmem del record, per leggerle da userspace:

  | Cella | Offset | Byte | In sysfs |
  |---|---|---|---|
  | `som-id` | `0x00` | 64 | `/sys/bus/nvmem/devices/*/cells/som-id@0,0` |
  | `mac-address` (ETH0) | `0x10` | 6 | `.../cells/mac-address@10,0` |
  | `mac-address` (ETH1) | `0x16` | 6 | `.../cells/mac-address@16,0` |
  | `serial-number` | `0x1c` | 12 | `.../cells/serial-number@1c,0` |

  Le celle leggono i byte così come sono, senza controllare magic e CRC:
  per un valore affidabile si usa `som-id show`.
- Nessun nodo Ethernet ha `nvmem-cells` verso i MAC. Il MAC arriverà da
  U-Boot, che verifica il record e scrive `local-mac-address` (non ancora
  fatto, vedi sotto).
- Il nodo `eeprom@50` non ha `read-only` né `wp-gpios`: la produzione scrive
  da Linux, e la protezione è solo il pin WP. `make check` lo verifica,
  insieme agli offset delle celle.

## Programmare l'EEPROM

Sulla board, in console:

```sh
som-id show                    # status=blank su un'EEPROM vergine
som-id write --product 0x0001 --rev 1 --ram 64 \
  --serial "$(som-id serial MA264800017)" \
  --mac0 00:11:22:33:44:55
som-id verify; echo $?         # 0 = record valido
```

- `write` rifiuta di sovrascrivere un'EEPROM non vergine senza `--force`, e
  dopo la scrittura rilegge e confronta.
- `verify` esce con 0 solo se il record è valido. Un MAC con il bit "locally
  administered" (prototipi) passa solo con `--allow-local`: la stazione di
  collaudo non lo passa.
- Se `write` dice `write rejected by the EEPROM`, il primo sospetto è il pin
  WP alto.
- Formato dell'output, codici d'uscita e opzioni: README della repo
  `som-id`.

## Fonte dei MAC

Blocco IEEE MA-S proprio: 4096 indirizzi, consumati solo dalle porte
montate (la EGARE ne ha una, il LAN9512). Oltre circa 2000 moduli a due
porte serve un MA-M. Il database di produzione li assegna con un vincolo di
unicità; mai ricavati dal seriale, mai riusati, nemmeno da schede scartate.

## Cosa manca

- U-Boot che legge il record e imposta `ethaddr`, `eth1addr`, `serial#` e
  `local-mac-address` (con il nodo dell'hub LAN9512 e l'alias `ethernet0`
  nel DT).
- L'SPL non legge l'EEPROM: sulla F1C200s la DRAM è nel package e il campo
  DDR vale `0x00`.

## Cambiare schema o tool

Si cambia nella repo `som-id` e si pubblica un nuovo tag; poi qui
`SOM_ID_VERSION` in `som-id.mk` e `som-id.hash`. Se cambiano gli offset,
anche le celle nel DTS EGARE e la sezione 12 di `check-image.sh`. Per
lavorare su un checkout locale senza tag:

```sh
echo 'SOM_ID_OVERRIDE_SRCDIR = /home/walter/git/som-id' > output-egare/local.mk
make O=output-egare som-id-rebuild && make O=output-egare
```
