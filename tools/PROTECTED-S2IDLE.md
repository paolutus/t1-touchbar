# Prova temporanea s2idle — MacBookPro14,2

Italiano | [English](PROTECTED-S2IDLE-EN.md)

La combinazione è stata confermata funzionante sul MacBookPro14,2 di riferimento
il 28 settembre 2026, con cicli manuali e gestione permanente. Non è una garanzia
per ogni esemplare. Per replicarla dall'inizio su un altro Mac seguire la
[guida completa](../docs/MACBOOKPRO14-2-SUSPEND-IT.md).
Può ancora causare un blocco e richiedere lo spegnimento forzato, con perdita dei
dati non salvati. Salvare il lavoro e chiudere le applicazioni.

## Motivazione e limiti

Le prove del 27 settembre 2026 mostrano che mode/display OFF sono reversibili
a macchina sveglia, ma saltare display OFF durante S3 non ripristina la barra.
I log mostrano un reset dell'iBridge al resume da S3 e guasti distinti ai controller
Thunderbolt. L'iBridge è sul controller interno 00:14.0: i guasti Thunderbolt
non dimostrano la causa della Touch Bar nera.

Una [procedura pubblica per MacBookPro13,2](https://gist.github.com/bgausden/c7f8a3737c1e52a260dfcdb1fb2e90b2)
riporta una Touch Bar funzionante dopo s2idle con protezione NVMe e rimozione/
nuova enumerazione dei rami Thunderbolt. Quel modello è diverso dal 14,2.
Questo script adatta solo la prova energetica alla topologia locale controllata;
non esegue l'installer esterno, non sostituisce driver/firmware e non modifica Wi-Fi.

## Prima della prova

- Eseguire da un terminale locale con Touch Bar accesa dopo un riavvio.
- Scollegare tutte le periferiche USB-C/Thunderbolt (anche monitor e hub),
  lasciando eventualmente solo l'alimentatore.
- Non ricollegare dispositivi fino al completamento del ripristino.
- Lasciare disarmati sia il test SOCW sia quello display; lo script lo verifica.
- Non aggiornare il driver per questa prova: viene verificato il modulo già
  esaminato, srcversion `E8CEB54C26CE50C4955BFCA`.

```bash
# Dalla radice della copia modificata del progetto:
sudo bash tools/test-protected-s2idle.sh --check
```

Il controllo è in sola lettura. Se fallisce, fermarsi e riportare l'errore.
La richiesta viene controllata anche con `systemctl --dry-run`, eseguito come
utente che ha invocato `sudo`: la propria sessione grafica non deve essere
scambiata per quella di un altro utente. Gli inibitori restano rispettati, sia
nel controllo preliminare sia nella richiesta effettiva. Non usare `-i`.
Se passa, avviare la prova:

```bash
sudo bash tools/test-protected-s2idle.sh --run
```

Lo script richiede di digitare `PROVA` prima di modificare lo stato hardware.
Il coperchio resta aperto. Per risvegliare, premere un tasto; se non basta, una
breve pressione del pulsante di accensione. Attendere almeno un minuto prima
di concludere che il Mac è bloccato. Non chiudere il terminale durante la prova.

## Cosa cambia e come torna indietro

Solo fino al ripristino (o al riavvio):

1. `d3cold_allowed=0` su SSD `01:00.0` e NHI `05:00.0`, `7b:00.0`.
2. Selezione di `s2idle` in `/sys/power/mem_sleep`.
3. Rimozione dei rami PCI Thunderbolt `03:00.0` e `79:00.0`, non di SSD/iBridge.
4. Richiesta normale di sospensione tramite logind, senza ignorare gli inibitori.
5. Dopo il ciclo, scansione dei soli parent port `00:1c.4` e `00:1d.0` e ripristino
   dei valori energetici salvati.

La luminosità di `spi::kbd_backlight` viene inoltre salvata e azzerata prima
della sospensione, quindi ripristinata al valore esatto (anche zero) dopo il
resume o se la richiesta viene rifiutata.

Non vengono installati servizi/hook o modificate configurazioni GRUB, firmware,
modprobe, rete o ACPI. Il solo file di coordinamento è un lock in `/run`, eliminato
dal riavvio. Il codice non chiama SOCW né scarica i moduli iBridge.

Se il kernel si blocca, nessuno script può garantire il ripristino automatico.
Se il Mac è completamente bloccato, può servire tenere premuto il pulsante di
accensione finché si spegne. Non ripetere la prova dopo un blocco. Se il ripristino
segnala controller mancanti, salvare il lavoro e riavviare.

## Risultato da riportare

- Il Mac si è risvegliato?
- La Touch Bar è visibilmente accesa e risponde ai tasti?
- Copiare l'output completo dello script, compresi eventuali errori di ripristino.

Lo script stampa il log kernel pertinente prima del ripristino. I messaggi USB
positivi non sostituiscono la conferma visiva. L'esito valuta la combinazione dei
workaround: non identifica da solo la causa originale.

## Verifiche senza hardware

```bash
bash -n tools/test-protected-s2idle.sh
bash tools/test-protected-s2idle-mocks.sh
```

I test simulano attesa e scritture di ripristino; non dimostrano che sospensione,
ri-enumerazione PCI o display funzionino realmente.

## Installazione permanente opzionale

I cicli manuali s2idle e il funzionamento complessivo dopo l'aggiunta della
retroilluminazione sono stati confermati dall'utente. I log attestano anche due
cicli permanenti riusciti. Su un altro esemplare ripetere prima le prove manuali,
includendo luminosità iniziale della tastiera sia zero sia non zero.

```bash
sudo bash tools/install-permanent-sleep.sh --install
```

Richiede la conferma `INSTALLA`. Non esegue sospensioni né cambia GRUB, driver,
firmware, Wi-Fi o preferenze KDE. Usa un drop-in di `systemd-suspend.service`
con `ExecStartPre` (verifiche/preparazione) ed `ExecStopPost` (ripristino anche
dopo un fallimento iniziale), più `MemorySleepMode=s2idle` in sleep.conf.d.
Non installa un hook system-sleep, il cui errore non potrebbe annullare il suspend.
La normale azione di sospensione di KDE/coperchio passa da questo servizio.
Ibernazione e suspend-then-hibernate non sono coperti da questa configurazione.

**Con periferiche USB-C/Thunderbolt o monitor esterni rilevati la sospensione è
rifiutata, non forzata. Il Mac potrebbe restare sveglio con il coperchio chiuso:
non metterlo in una borsa senza verificarlo.** Non collegare dispositivi durante
il ciclo. I controlli sono prudenti, ma non possono eliminare tutte le possibili
corse con un collegamento fisico contemporaneo.

Il codice controlla anche il modello, il modulo Touch Bar esaminato, la topologia
PCI e l'esclusione di SOCW. Cambiamenti a driver/configurazioni possono quindi
bloccare la sospensione finché non vengono rivalutati. Un hard lock non consente
il ripristino software: salvare sempre il lavoro prima delle prime prove.

Dopo l'installazione non usare più `--run` dello script manuale: viene rifiutato
per evitare una doppia rimozione PCI. Provare la normale chiusura/riapertura del
coperchio senza periferiche collegate, verificando Touch Bar e luce tastiera.

```bash
journalctl -b -u systemd-suspend.service --no-pager -n 100
```

Disinstallazione reversibile:

```bash
sudo bash tools/install-permanent-sleep.sh --remove
```

L'installer rifiuta di sovrascrivere file esistenti. Il disinstallatore controlla
che i propri file non siano stati modificati e li sposta in una directory di
backup stampata a video, quindi ricarica systemd. Non rimuove driver o altri
file dell'utente. Le impostazioni normali precedenti tornano in vigore; la Touch
Bar potrebbe quindi tornare nera dopo il normale suspend.
