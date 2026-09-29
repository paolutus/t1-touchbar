# MacBookPro14,2: Touch Bar e tastiera dopo sospensione su Kubuntu

Stato al **28 settembre 2026**: soluzione confermata dall'utente sul Mac di
riferimento, con più cicli manuali e successiva integrazione permanente.
È un workaround di sospensione, non una correzione della causa firmware dimostrata.
Questa guida serve a riprodurre la stessa configurazione su un altro **MacBookPro14,2**;
lo stesso nome commerciale «MacBook Pro 2017» non è sufficiente.

## 1. Risultato e limiti

Prima: Touch Bar funzionante al boot, nera dopo `deep`/S3, anche se i comandi USB
di accensione terminavano senza errore.

Dopo: sospensione `s2idle` con protezione energetica NVMe, rimozione temporanea dei
rami Thunderbolt prima della sospensione e nuova enumerazione al risveglio.
La Touch Bar si riaccende. La retroilluminazione della tastiera fisica viene salvata,
spenta prima della sospensione e ripristinata al valore originale, anche se era zero.

**Limiti importanti:**

- Verificato su un solo esemplare; altri 14,2 vanno convalidati, non presunti compatibili.
- Non applicare direttamente a 13,2, 14,3, T2 o Apple Silicon. Gli indirizzi PCI sono specifici.
- La versione permanente **rifiuta la sospensione se rileva periferiche nei rami
  USB-C/Thunderbolt o monitor esterni**. Anche un disco non montato causa il rifiuto.
- Il Mac può quindi restare sveglio con il coperchio chiuso. Prima di metterlo in
  una borsa verificare che sia davvero sospeso; in caso di dubbio spegnerlo.
- Non collegare periferiche durante il ciclo di sospensione/ripristino.
- Ibernazione e suspend-then-hibernate non sono coperti. KDE deve richiedere la
  normale sospensione, non una di queste modalità.
- Consumo notturno, autonomia, cicli prolungati e compatibilità con altri kernel
  non sono stati misurati. Non assumere l'autonomia di `deep`.
- Il codice può ancora bloccarsi su hardware/firmware diverso. Salvare il lavoro.

## 2. Mac di riferimento

| Voce | Valore osservato |
| --- | --- |
| Modello DMI | `MacBookPro14,2`, 13 pollici 2017, T1 |
| Sistema | Kubuntu; base `Ubuntu 26.04.1 LTS` |
| Kernel | `7.0.0-34-generic` |
| systemd | `259.5-0ubuntu3.4` |
| BIOS/firmware | `529.140.2.0.0` |
| Parametri kernel presenti | `pcie_port_pm=off pcie_ports=compat` |
| iBridge | USB `05ac:8600`, percorso `00:14.0/usb1/1-3` |
| SSD | Apple S3X `106b:2003`, `0000:01:00.0` |
| Rami Thunderbolt | `0000:03:00.0`, `0000:79:00.0`, Intel `8086:1578` |
| Porte PCI genitrici | `0000:00:1c.4`, `0000:00:1d.0` |
| NHI Thunderbolt | `0000:05:00.0`, `0000:7b:00.0` |
| xHCI Thunderbolt | `0000:06:00.0`, `0000:7c:00.0` |
| LED tastiera | `/sys/class/leds/spi::kbd_backlight`, massimo `255` |
| Pacchetto DKMS | `apple-ib-drv/0.1` |
| `apple_ibridge` caricato, srcversion | `EA3883CC7FE2B9994D38BB1` |
| `apple_touchbar` caricato, srcversion | `E8CEB54C26CE50C4955BFCA` |

Il firmware è riportato per confronto, **non è un invito ad aggiornarlo o modificarlo**.
Non è dimostrato che entrambi i parametri PCIe siano necessari: erano presenti
nella configurazione riuscita e vengono mantenuti per riprodurla.

## 3. Distribuire la copia giusta

Usare **questa copia modificata del progetto**, includendo `apple-ib-drv/`,
`tools/` (compresa `tools/permanent/`), `docs/` e le licenze. Non basta copiare
i due `.c`, né clonare il repository upstream e presumere che contenga le patch.
Distribuire lo snapshot di questo branch e registrare il suo commit con
`git rev-parse HEAD`; non fare affidamento sul solo nome del repository.
La pubblicazione di un fork è un passaggio separato dalla preparazione locale.

Eseguire i comandi dalla radice della copia ricevuta, in una directory scelta
dall'utente: non è necessario usare lo stesso nome utente o percorso del Mac originale.

```bash
sha256sum --check docs/macbookpro14-2-tested.sha256
```

Le impronte identificano sorgenti e script di questa procedura; non autenticano
il mittente. Esaminare il codice prima di eseguirlo con `sudo`.
Una revisione successiva deve aggiornare manifest e risultati solo dopo nuova verifica.

## 4. Prerequisiti e inventario prima di cambiare qualcosa

La Touch Bar deve poter funzionare al boot e l'iBridge deve essere `05ac:8600`.
Se è assente o in recovery (`05ac:1281`), questa procedura non risolve il problema.
Non formattare partizioni EFI/macOS e non usare programmi di ripristino firmware
come parte di questa guida.

```bash
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/bios_version
cat /etc/os-release
uname -r
systemctl --version
cat /proc/cmdline
cat /sys/power/mem_sleep
lspci -nn
lsusb
dkms status
```

Confrontare modello, kernel e topologia con la tabella. Su un kernel diverso
la compilazione e il resume richiedono una nuova verifica. Gli script controllano
anche una specifica `srcversion`: **non rimuovere il controllo per far passare
una versione differente senza esaminarla**.

Prima di installare: esaminare e salvare eventuali configurazioni già presenti in
`/etc/modprobe.d/apple-touchbar.conf`, `/etc/modules-load.d/apple-touchbar.conf`,
`/etc/udev/rules.d/99-ibridge.rules`, i file GRUB e i sorgenti DKMS esistenti.
Se ci sono altri driver Touch Bar, hook di sospensione o pacchetti con nomi diversi,
fermarsi e risolvere il conflitto; non installare due stack concorrenti.

Dipendenze sulla famiglia Ubuntu usata qui:

```bash
sudo apt-get update
sudo apt-get install build-essential dkms "linux-headers-$(uname -r)" pciutils usbutils util-linux python3
```

Non proseguire se mancano gli header del kernel in esecuzione. Non cambiare
kernel alla cieca per soddisfare questo comando.

### Parametri di boot del caso verificato

Se mancano, salvare una copia di `/etc/default/grub`, aprirlo con
`sudoedit /etc/default/grub` e **aggiungere, senza cancellare gli altri parametri**, a
`GRUB_CMDLINE_LINUX_DEFAULT`:

```text
pcie_port_pm=off pcie_ports=compat
```

Quindi eseguire `sudo update-grub` e riavviare dopo aver salvato il lavoro.
Verificare i parametri in `/proc/cmdline`. Questo passaggio riguarda installazioni
che usano GRUB; non applicarlo a un bootloader diverso senza adattarlo.
Non aggiungere `mem_sleep_default=s2idle`: la procedura seleziona s2idle solo
nel percorso protetto, dopo i controlli.

## 5. Installare il driver modificato, senza ricaricarlo a caldo

### A. Prima installazione, senza un precedente stack Touch Bar

Questi comandi inizializzano i file richiesti dagli script del progetto. Usarli
solo dopo aver verificato che le destinazioni non contengano configurazioni da
preservare. Non sono una migrazione automatica da altri fork.

```bash
sudo install -m 644 apple-ib-drv/packaging/apple-touchbar.modprobe.conf /etc/modprobe.d/apple-touchbar.conf
sudo install -m 644 apple-ib-drv/packaging/apple-touchbar.modules-load.conf /etc/modules-load.d/apple-touchbar.conf
sudo install -m 644 apple-ib-drv/packaging/99-ibridge.rules /etc/udev/rules.d/99-ibridge.rules
sudo install -d /usr/src/apple-ib-drv-0.1
sudo install -m 644 apple-ib-drv/Makefile apple-ib-drv/dkms.conf apple-ib-drv/apple-ibridge.c apple-ib-drv/apple-ibridge.h apple-ib-drv/apple-touchbar.c apple-ib-drv/hid-ids.h /usr/src/apple-ib-drv-0.1/
sudo dkms add -m apple-ib-drv -v 0.1
```

Fermarsi al primo errore. Non eseguire `modprobe`, unbind/rebind, `udevadm trigger`
o scaricamenti dei moduli per provare subito il risultato. Passare al punto C.
Il percorso di prima installazione è ricavato dai requisiti del codice;
l'esemplare di riferimento aveva già il pacchetto DKMS installato.

### B. Aggiornamento dello stesso pacchetto già installato

Se esiste già **`apple-ib-drv/0.1`** con sorgenti in `/usr/src/apple-ib-drv-0.1`,
non eseguire di nuovo `dkms add`. Verificare le tre configurazioni indicate nel
punto A, in particolare `options apple_ibridge skip_acpi_power=1`.
Non usare questa scorciatoia per un pacchetto dal nome diverso.

### C. Compilazione, initramfs e riavvio

```bash
sudo bash tools/install-display-fix.sh
```

Nonostante il nome storico, questo script aggiorna entrambi i sorgenti C,
forza build/install DKMS per il kernel corrente e aggiorna initramfs. Salva i
sorgenti precedenti in `/var/tmp/t1-display-backup.*` e stampa il percorso.
Conservare quel percorso. Non carica moduli a caldo e non riavvia automaticamente.

Se l'installazione finisce senza errori, salvare il lavoro e riavviare. Poi:

```bash
dkms status
cat /sys/module/apple_ibridge/srcversion
cat /sys/module/apple_touchbar/srcversion
cat /sys/module/apple_ibridge/parameters/skip_acpi_power
sudo cat /sys/module/apple_ibridge/parameters/test_resume_acpi_once
sudo cat /sys/module/apple_touchbar/parameters/test_skip_suspend_display_off_once
journalctl -b -k --no-pager | grep -E 'apple-ibridge|apple-touchbar|SOCW'
```

Attesi: `srcversion` della tabella, `skip_acpi_power=1`, entrambi i test `N`,
Touch Bar visibilmente accesa e tasti funzionanti. I log devono indicare
`Touchbar activated with mode and display interfaces`.
`modinfo` descrive il modulo su disco; `/sys/module/.../srcversion` identifica
quello effettivamente caricato. Un trasferimento USB riuscito non prova che lo
schermo sia acceso. Se la barra è nera già al boot, non iniziare i test di resume.

**Mai armare `test_resume_acpi_once` e mai impostare `skip_acpi_power=0`: la
prova SOCW ha bloccato il Mac di riferimento.** I parametri diagnostici sono
ancora presenti nel codice per tracciabilità, non sono parte della soluzione.

## 6. Provare prima la configurazione temporanea

Salvare e chiudere le applicazioni. Scollegare tutte le periferiche USB-C/Thunderbolt
e i monitor esterni; può restare l'alimentatore. Usare un terminale locale della
propria sessione grafica, non SSH o una shell root aperta in precedenza.

```bash
sudo bash tools/test-protected-s2idle.sh --check
```

È in sola lettura. Qualsiasi `STOP` va risolto prima di procedere, senza rimuovere
i controlli. Se passa:

```bash
sudo bash tools/test-protected-s2idle.sh --run
```

Confermare con `PROVA`, tenere il coperchio aperto, poi risvegliare con un tasto
o una breve pressione del pulsante di accensione. Attendere la fine del ripristino
prima di ricollegare periferiche. Non usare `systemctl suspend -i`.

Criteri di riuscita:

1. Il Mac si risveglia senza spegnimento forzato.
2. La Touch Bar si riaccende e i tasti funzionano.
3. La luce della tastiera si spegne durante il sonno e torna al livello iniziale.
   Provare sia da luminosità non zero sia da zero.
4. I log contengono `PM: suspend entry (s2idle)`, `PM: suspend exit`,
   `ACPI test=0` e, nel caso verificato, `Touchbar restore queued (reset=0)`.
5. Lo script non segnala errori nel ripristino dei controller.

Ripetere almeno tre cicli e annotare gli esiti. Sul Mac originale sono stati
confermati più cicli riusciti. La prova rimette i valori energetici iniziali:
vedere nuovamente `[deep]` dopo il test è previsto, non un errore.
Fino all'installazione permanente la normale chiusura del coperchio non usa
necessariamente la configurazione protetta.

## 7. Rendere permanente la gestione del coperchio

Solo dopo le prove precedenti:

```bash
sudo bash tools/install-permanent-sleep.sh --install
```

Confermare con `INSTALLA`. L'installer non sovrascrive file già presenti, non
sospende, non cambia GRUB/driver/Wi-Fi e non modifica le preferenze KDE.
Non serve ricompilare o riavviare. In KDE l'azione del coperchio deve essere
**Sospendi**; l'installer non la imposta al posto dell'utente.

| File installato | Funzione |
| --- | --- |
| `/usr/local/libexec/t1-sleep-common.sh` | Controlli e operazioni comuni alla prova manuale |
| `/usr/local/libexec/t1-sleep-guard` | Preparazione e ripristino automatici |
| `/etc/systemd/system/systemd-suspend.service.d/90-t1-sleep-guard.conf` | `ExecStartPre` e `ExecStopPost` |
| `/etc/systemd/sleep.conf.d/90-t1-s2idle.conf` | `SuspendState=mem`, `MemorySleepMode=s2idle` |
| `/var/lib/t1-sleep-guard/manifest` | Impronte per disinstallazione senza rimuovere file alterati |

Lo snapshot di un ciclo sta in `/run/t1-sleep-guard`, accessibile solo a root.
Viene rimosso dopo un ripristino riuscito. Se il ripristino fallisce, resta per
impedire di continuare alla cieca; in quel caso salvare il lavoro e riavviare.

`ExecStartPre` fallito impedisce l'esecuzione del comando di sospensione;
`ExecStopPost` consente il ripristino anche dopo un errore iniziale. Un semplice
hook `system-sleep` che termina con errore non offrirebbe lo stesso blocco.
[Semantica systemd 259](https://github.com/systemd/systemd/blob/v259/man/systemd.service.xml).

Dopo l'installazione non usare più `--run` manuale: viene rifiutato per evitare
due preparazioni concorrenti. Provare chiusura e riapertura del coperchio senza
periferiche e raccogliere:

```bash
journalctl -b -u systemd-suspend.service --no-pager -n 100
journalctl -b -k --no-pager | grep -E 'PM: suspend|Touchbar|Display command|iBridge platform|ACPI one-shot'
```

I log del Mac originale confermano due cicli permanenti il 28 settembre, alle
03:06 e 03:07, con preparazione, resume e ripristino terminati con successo.
In quei due log la luce tastiera era già a zero e viene correttamente conservata
a zero; l'utente ha confermato il funzionamento complessivo dopo l'aggiornamento.
Su ogni nuova macchina verificare anche il caso luminosità iniziale non zero.

## 8. Cosa modifica il workaround e cosa non dimostra

Per ogni ciclo viene applicata questa sequenza:

```text
controlli modello/moduli/periferiche e salvataggio valori
  -> D3cold escluso su SSD e NHI, selezione s2idle
  -> rimozione dei soli rami Thunderbolt, luce tastiera a zero
  -> sospensione e resume normale dell'iBridge
  -> scansione dei soli parent port Thunderbolt
  -> ripristino delle politiche energetiche e della luce tastiera
```

L'SSD non viene rimosso. Il controller interno `00:14.0` dell'iBridge non viene
rimosso. Non viene eseguito SOCW e non vengono scaricati i moduli Touch Bar.
La nuova enumerazione dei dispositivi non è una cancellazione dei loro dati,
ma può interrompere I/O: per questo i controlli rifiutano le periferiche collegate.

Le modifiche locali al driver comprendono: classificazione HID del dispositivo
virtuale Touch Bar per evitare il binding errato di `hid-sensor-hub`; uso di
entrambe le interfacce mode/display; invio e verifica dei report display;
normalizzazione del risultato delle scritture mode; ripristino forzato dello
stato e callback resume ordinaria/reset; registrazione PM della piattaforma
tramite `driver.pm`, mantenendo la protezione SOCW.

Le prove dimostrano il risultato della **combinazione**. Non dimostrano quale
singolo parametro sia indispensabile o che il reset USB sia la causa primaria.
Gli errori Thunderbolt osservati in S3 riguardavano controller diversi dall'iBridge.

## 9. Tentativi da non ripetere come se fossero soluzioni

| Tentativo sul Mac originale | Esito |
| --- | --- |
| Reinviare display ON dopo S3 | Trasferimento riuscito, barra ancora nera |
| Disattivare/riattivare modalità e display a Mac sveglio | Funzionante; non risolve il resume |
| Saltare solo display OFF prima di S3 | Nessun miglioramento |
| Aggiungere solo parametri PCIe | Non ha risolto la Touch Bar |
| s2idle senza la combinazione protetta | Tentativi senza risveglio riuscito |
| Test SOCW(1) realmente eseguito al resume | Blocco del Mac; abbandonato |
| s2idle con protezioni NVMe/Thunderbolt e driver corrente | Cicli riusciti |

Una precedente prova SOCW non era stata eseguita a causa delle vecchie callback:
il parametro restava `Y`. Solo dopo la correzione delle callback la prova è stata
realmente eseguita e ha bloccato il Mac. Non confondere quei due risultati.

## 10. Diagnosi, aggiornamenti e rollback

**`User ... is logged in on tty2`:** usare lo script aggiornato, che esegue la
richiesta come utente di `sudo`, conservando il controllo degli inibitori.
Non fare logout dalla propria sessione per aggirarlo e non usare `-i`.

**Rifiuto per periferiche:** scollegarle e riprovare dopo aver verificato che i
controller siano sani. Non eliminare il controllo sui dischi.

**Srcversion diversa, kernel aggiornato o controller mancanti:** fermarsi.
DKMS può ricompilare, ma questo non garantisce compatibilità funzionale.
Il controllo del modulo è intenzionalmente restrittivo: una nuova build deve
essere esaminata e riconvalidata prima di aggiornare la versione consentita.
Le copie installate sotto `/usr/local/libexec` non cambiano modificando il checkout.

**Blocco completo:** attendere e provare il risveglio; se il Mac non risponde può
servire lo spegnimento forzato. Il lavoro non salvato è a rischio. Non ripetere
la prova identica; dopo il riavvio raccogliere `journalctl -b -1 -k --no-pager`.

Per rimuovere la sola gestione permanente:

```bash
sudo bash tools/install-permanent-sleep.sh --remove
```

I file vengono spostati in `/var/tmp/t1-sleep-removed.*`, non cancellati. Se sono
stati modificati, la rimozione automatica si ferma. Non viene disinstallato il
driver e non vengono ripristinate eventuali modifiche GRUB fatte manualmente.
Rimuovere la gestione permanente **prima** di cambiare/rimuovere lo stack driver.
La sospensione precedente potrebbe tornare a lasciare la barra nera.

Per un rollback dei sorgenti DKMS, usare il percorso esatto del backup stampato
da `install-display-fix.sh`: ripristinare i due `.c` in `/usr/src/apple-ib-drv-0.1`,
poi eseguire `dkms build --force`, `dkms install --force` per il kernel corrente,
`update-initramfs -u -k ...` e riavviare. Lo script stampa il comando di copia
dei propri backup. Non eseguire nuovamente lo script di aggiornamento dopo il
ripristino, perché ricopierebbe i sorgenti nuovi. Conservare sempre
`skip_acpi_power=1` e non ricaricare i moduli a caldo.

## 11. Test del codice e resoconto di una nuova macchina

```bash
bash -n tools/test-protected-s2idle.sh tools/install-permanent-sleep.sh tools/permanent/t1-sleep-guard
bash tools/test-protected-s2idle-mocks.sh
python3 tools/test-touchbar-update.py
python3 tools/test-touchbar-suspend.py
python3 tools/test-ibridge-resume.py
```

Questi test non sospendono il Mac e non eseguono SOCW. I test simulati non
sostituiscono le verifiche visive e hardware.

Per ogni nuova installazione registrare modello, BIOS, distro/kernel/systemd,
parametri di boot, `srcversion`, esito del manifest, numero di cicli riusciti,
stato della luce tastiera prima/durante/dopo, funzionamento Touch Bar e log
completi di preparazione/ripristino. Non pubblicare identificativi personali,
UUID dei dischi o altri dati non necessari.

Riferimenti di partenza, non installer da eseguire in aggiunta:

- [Procedura s2idle su MacBookPro13,2](https://gist.github.com/bgausden/c7f8a3737c1e52a260dfcdb1fb2e90b2): ha suggerito la combinazione; non è una prova sul 14,2.
- [Configurazione T1 di nohzafk](https://github.com/nohzafk/omarchy-macbookpro-t1): confronto iniziale, non garanzia per questa installazione.
- [Note operative locali](../tools/PROTECTED-S2IDLE.md) e [driver](../apple-ib-drv/apple-touchbar.c).
