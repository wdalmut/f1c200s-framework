# Scelte di progetto

Perché questo albero è fatto così. Ogni voce dice anche cosa si romperebbe
cambiando idea, così che la prossima persona non debba riscoprirlo.

## Buildroot come submodule, pinnato a una LTS

`buildroot/` è un submodule di `gitlab.com/buildroot.org/buildroot.git`
pinnato a **2026.02.3**. Le LTS di Buildroot sono le release `YYYY.02.x`, e
`setup.sh` avvisa se il submodule non è su una di quelle.

Il vantaggio non è la stabilità in sé: è che un bug di build diventa
riproducibile. Con `master` la stessa revisione di questo repo produce
artefatti diversi a settimane di distanza.

Il pin **non** vincola le versioni di kernel e U-Boot: quelle sono scelte nel
defconfig con `BR2_LINUX_KERNEL_CUSTOM_VERSION` e
`BR2_TARGET_UBOOT_CUSTOM_VERSION`, e possono essere più recenti di quelle che
la LTS conosce. È esattamente il caso di U-Boot 2026.07 su Buildroot 2026.02.3.

## Niente container di build

`rk3506-framework` ha un `docker/Dockerfile` perché **deve**: il BSP Rockchip
usa U-Boot 2017.09, che non compila con gcc host ≥ 14 e pretende python2, e
Ubuntu 22.04 è l'ultima distro che impacchetta entrambi.

Qui non c'è niente del genere. Kernel e U-Boot sono mainline recenti e
compilano su qualunque distro corrente, quindi un container aggiungerebbe un
file da mantenere senza risolvere un problema reale. Al suo posto, `setup.sh`
controlla le dipendenze host e dice esattamente cosa installare.

Se in futuro servisse (per esempio per la CI), il Makefile è già strutturato
per ospitare la delega: si aggiunge un ramo `ifeq ($(IN_CONTAINER),)` come in
`rk3506-framework`.

## Niente submodule vendor

Questa board non ha blob. Niente init DDR proprietario, niente OP-TEE, niente
tool di packaging: l'SPL mainline inizializza la DDR1 da solo e l'immagine SD
è una tabella MBR con due partizioni. Per questo manca anche il `post-image.sh`
che in `rk3506-framework` assembla loader e `update.img`: qui basta `genimage`.

## Kernel 6.12.x LTS

Il bring-up è stato fatto su 6.5.9, che però è **EOL**. Il repo nasce
direttamente su 6.12 LTS per non partire con un debito già scaduto.

Il vincolo da ricordare è che **kernel e kernel-headers devono restare
allineati**: `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.12.111"` va insieme a
`BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_12=y`. Se si cambia solo il primo,
Buildroot si ferma con un errore esplicito — ma c'è un caso peggiore e
silenzioso: se la versione di headers scelta non esiste nella choice, Kconfig
può ripiegare su un'altra libc. La CI controlla che la toolchain resti glibc
proprio per questo.

## `bootcmd` esplicito invece di distro-boot

`CONFIG_BOOTCOMMAND` carica kernel e DTB con due `load mmc` e un `bootz`,
invece di affidarsi a bootstd / `extlinux.conf` / `boot.scr`.

È una scelta di diagnosticabilità, non di eleganza. Il bring-up di questa board
è stato bloccato a lungo da un guasto silenzioso (console sulla UART sbagliata,
vedi `BOARD-FACTS.md`), e in quella situazione un bootloader che "prova varie
strade" nasconde il punto in cui si rompe. Con il `bootcmd` esplicito, se il
file non c'è il messaggio lo dice.

Il prezzo è che cambiare i `bootargs` richiede `make uboot-reconfigure` invece
di editare un file sulla FAT. Per le prove estemporanee resta il prompt di
U-Boot.

## `CONS_INDEX=2` ripetuto nel fragment

`lctech_pi_f1c200s_defconfig` di U-Boot ha già `CONFIG_CONS_INDEX=2`, quindi la
riga nel nostro fragment è ridondante. È lì lo stesso perché è l'unico valore
che, se sbagliato, non produce **nessun** messaggio di errore: solo silenzio
sulla seriale. Ripeterlo esplicitamente lo rende visibile a chi legge il
fragment, e `docs/check-image.sh` lo verifica a ogni build.

## `make check` invece di test in CI

La CI non costruisce l'immagine: una build completa di Buildroot non sta nei
tempi di un runner gratuito. Quello che la CI verifica è ciò che si rompe in
silenzio — un defconfig non canonico, uno script con un errore di sintassi, un
link morto fra i documenti.

I controlli che richiedono artefatti stanno in `docs/check-image.sh`, che si
lancia a mano con `make check` dopo la build. Ogni suo controllo corrisponde a
un errore realmente commesso durante il bring-up.

## Boot da SPI NAND con patch SPL invece di un fork

L'SPL mainline non legge la SPI NAND. Le alternative erano tre: portare le
patch di Icenowy Zheng (2022, cinque patch di codice, mai integrate), usare
come sorgente il fork `jookia_main` che le contiene già, oppure sostituire SPL
e U-Boot con awboot. Il fork è su v2025.04, porta 142 commit e l'hanno testato
solo su T113: cinque patch che conosciamo riga per riga costano meno di un
fork che non controlliamo. awboot fa perdere U-Boot come ambiente di recovery
e di debug.

Le patch stanno in `external/board/ftvogue-f1c200s/patches/uboot/`, **senza**
sottodirectory di versione. Con `uboot/2026.07/`, un bump di U-Boot farebbe
saltare le patch in silenzio, e uscirebbe un SPL che non legge la NAND. Senza
versione, un bump che le rende inapplicabili fa fallire la build al passo di
patch. `make check` controlla comunque che `spi_load_read_nand` compaia nella
map dell'SPL.

Su suniv U-Boot proper non sa da dove è partito l'SPL, per cui il `bootcmd`
sceglie fra SD e NAND con `test -e mmc 0:1 zImage` e si appoggia alla priorità
della BROM, che con una SD avviabile inserita parte sempre da lì. È una
selezione, non un fallback, coerente con il `bootcmd` esplicito: se il ramo
scelto fallisce, il boot si ferma. Per la stessa ragione l'environment è
`ENV_IS_NOWHERE`: vale quello compilato, e l'environment su SPI NOR del
defconfig upstream qui non avrebbe dove stare.

## EEPROM di identificazione scritta da Linux

Il device tree nell'immagine del modulo è l'unica fonte di verità sulle
periferiche: l'EEPROM a `0x50` contiene solo chi è il modulo (prodotto,
revisione, variante, seriale, MAC) e i pochi dati che servono all'SPL prima
della DRAM. Niente bitmap di capacità: due fonti sulle periferiche finiscono
per contraddirsi.

Il record si scrive dalla board sotto Linux, con `som-id`, perché il
collaudo ha già la console e non servono adattatori I2C esterni. Il costo è
che il DT non può dichiarare l'EEPROM `read-only`: la protezione è solo il
pin WP. Il tool è in C perché la shell BusyBox non calcola comodamente un
CRC16 e perché lo stesso parser andrà in U-Boot; vive in una repo propria
(`egaree/som-id`, MIT) perché serve a tutta la famiglia, SMARC compresi, e
qui si fissa solo il tag.

I MAC stanno in due slot espliciti, uno per porta, invece di base + numero:
nessun lettore deve supporre che siano contigui. Grazie agli slot Linux li
legge con `nvmem-cells` senza l'offset di `mac-base`, che la `fixed-layout`
del 6.12 non applica. Si è scelto questo invece di U-Boot che verifica il
record e scrive `local-mac-address`: costa molto meno (nessuna patch a
U-Boot, nessun driver I2C in più) e si perdono il controllo di magic e CRC
prima di usare il MAC e `serial#`. Il rischio residuo è un record corrotto
con un MAC ancora plausibile in un'EEPROM protetta dal WP e verificata in
produzione. U-Boot leggerà il record quando servirà a lui (SPL con più
configurazioni DDR, carrier). Design:
[superpowers/specs/2026-11-28-eeprom-id-design.md](superpowers/specs/2026-11-28-eeprom-id-design.md)
e [superpowers/specs/2026-11-28-eeprom-mac-nvmem-design.md](superpowers/specs/2026-11-28-eeprom-mac-nvmem-design.md).

## EGARE: DHCP di Buildroot e `ntpd` di BusyBox

Per la rete basta `BR2_SYSTEM_DHCP`: ifupdown e `udhcpc` di BusyBox ci sono
già, e le opzioni con cui Buildroot compila `udhcpc` (`-b`) non bloccano il
boot senza cavo. `dhcpcd` o `connman` porterebbero il riconoscimento del
cavo collegato e scollegato, che oggi non serve.

Per l'ora si usa `ntpd` di BusyBox invece di `ntp` o `chrony`: due righe in un
fragment, nessun pacchetto in più, e basta un client che a ogni avvio salti
dal 1970 all'ora corrente, perché la SoM non ha un RTC da disciplinare. Le
cose che mancano (server NTP presi dal DHCP con l'opzione 42, statistiche) si
aggiungono passando a `chrony` quando serviranno. Il fragment e l'overlay
stanno sotto `board/egare-f1c200s/`: la FTVOGUE non ha rete.

## EGARE: TLS con OpenSSL

La EGARE ha OpenSSL e `ca-certificates` fin dalla prima versione del
defconfig; `curl` usa lo stesso backend invece di mbedTLS o wolfSSL. Una
sola libreria TLS nell'immagine, un solo bundle CA, e la libreria che i
client più comuni (mosquitto, Python, paho, librerie MQTT in C) danno per
scontata. Il costo in spazio non pesa su 256 MiB di NAND. Il binario `openssl`
c'è per diagnosticare una connessione TLS (`openssl s_client`) prima di
sospettare l'applicazione.
