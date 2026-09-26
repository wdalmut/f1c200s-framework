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
