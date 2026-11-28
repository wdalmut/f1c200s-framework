# MAC dell'ETH0 EGARE dall'EEPROM via nvmem — design breve

## Intento

Oggi il LAN9512 della EGARE usa un MAC casuale. Il record v1.0 dell'EEPROM
([EEPROM-ID.md](../../EEPROM-ID.md)) ha il MAC ETH0 a `0x10`. Questo giro lo
porta all'interfaccia Linux, nel modo più semplice: il kernel lo legge
dalla cella nvmem, senza toccare U-Boot.

## Approcci

- **1. Solo Linux, `nvmem-cells` sul nodo Ethernet — scelto dall'utente.**
  Nessuna modifica a U-Boot. Con due slot espliciti non serve l'offset di
  `mac-base` (che la `fixed-layout` del 6.12 non applica), e Linux scarta
  da solo `FF…FF`, zero e multicast (`is_valid_ether_addr` in
  `of_get_mac_address_nvmem`).
- 2. U-Boot legge il record (`CONFIG_ID_EEPROM`, patch con copia del
  parser, driver `mvtwsi`), imposta `ethaddr`/`serial#` e scrive
  `local-mac-address`. Verifica magic e CRC e dà `serial#`, ma costa patch,
  driver e controlli. Rimandato a quando U-Boot avrà bisogno dei dati lui
  (SPL con più configurazioni DDR, carrier).

## Cosa si accetta di perdere

- Magic e CRC non sono verificati prima di usare il MAC. Il rischio è un
  record corrotto ma con un MAC ancora plausibile, in un'EEPROM protetta
  dal WP e verificata in produzione.
- Niente `serial#`, niente `/proc/device-tree/serial-number`: il seriale si
  legge con `som-id show` o dalla cella `serial-number@1c,0`.
- EEPROM vergine o MAC non valido: MAC casuale, diverso a ogni avvio (come
  oggi).
- `smsc95xx` non rinvia il probe se nvmem non è pronto: se l'EEPROM si
  registrasse dopo l'enumerazione USB, MAC casuale. Atteso di no (I2C
  built-in, USB enumerata dopo); si verifica sulla board.

## Design

**DTS EGARE** (`suniv-f1c200s-egare.dts`):

- la cella ETH0 prende un'etichetta: `mac_eth0: mac-address@10`;
- sotto `&usb_otg`, il LAN9512 come sul Raspberry Pi B:

  ```dts
  #address-cells = <1>;
  #size-cells = <0>;

  hub@1 {
  	compatible = "usb424,9512";
  	reg = <1>;
  	#address-cells = <1>;
  	#size-cells = <0>;

  	ethernet: ethernet@1 {
  		compatible = "usb424,ec00";
  		reg = <1>;
  		nvmem-cells = <&mac_eth0>;
  		nvmem-cell-names = "mac-address";
  	};
  };
  ```
- `aliases`: `ethernet0 = &ethernet;`.

La cella ETH1 (`mac-address@16`) resta senza riferimenti: la EGARE ha una
sola porta.

**`docs/check-image.sh`**, sezione 12: il controllo "nessun phandle sulle
celle MAC" diventa:

- `ethernet0` punta a un nodo `usb424,ec00` con `nvmem-cell-names =
  "mac-address"`, e il suo `nvmem-cells` è il phandle di
  `mac-address@10`;
- `mac-address@16` senza phandle (nessuno usa ETH1);
- restano offset delle celle e niente `read-only`/`wp-gpios`.

**Documenti**

- `docs/EEPROM-ID.md`, `docs/EGARE-SPEC-SODIMM.md` ("MAC dell'ETH0"),
  `docs/SCELTE-DI-PROGETTO.md`, `docs/EGARE-F1C200S.md` ("Lavoro futuro"):
  il MAC arriva via `nvmem-cells`, con quello che si perde; U-Boot resta
  lavoro futuro, per quando servirà a lui.
- Il design precedente
  ([2026-11-28-eeprom-id-design.md](2026-11-28-eeprom-id-design.md)) aveva
  l'opposto come anti-obiettivo: una nota in testa rimanda a questo.
- Repo `som-id`, `SPEC.md`, "Reader rules": la regola "Linux does not read
  MACs through nvmem-cells" diventa: Linux può leggerli con `nvmem-cells`
  (nvmem scarta `FF…FF`, zero e multicast ma non controlla magic e CRC);
  un bootloader che verifica il record e scrive `local-mac-address` ha la
  precedenza. Commit di sola documentazione su `master`: il package resta
  al tag `v1.0.0`, e `EEPROM-ID.md` rimanda a `SPEC.md` su `master`.

**Fuori:** U-Boot, FTVOGUE, carrier, SPL.

## Verifica

1. `make O=output-egare linux-rebuild && make O=output-egare`, poi
   `make O=output-egare check` tutto `ok`; prova negativa: con
   `nvmem-cells` tolto dal nodo Ethernet il controllo dà `KO`.
2. Sulla board (EEPROM già scritta con `02:00:00:00:00:01`):
   `ip link show eth0` mostra `02:00:00:00:00:01`, stabile fra due
   riavvii; `dmesg` senza errori nvmem.
