# Verifica prima dei commit locali — 28 settembre 2026

## Ambito

Revisione delle modifiche locali a driver, gestione suspend e documentazione.
Nessuna installazione, sospensione, modifica di firmware, configurazione GitHub
o pubblicazione è stata eseguita durante questa verifica.

La versione del driver e gli script operativi sono rimasti quelli della prova
riuscita: non sono state introdotte nuove modifiche hardware da considerare
implicitamente convalidate. Sono state aggiunte esclusioni Git per gli artefatti
kernel e resi indipendenti dall'hardware i test simulati del ripristino.

## Controlli eseguiti

- Compilazione dei due moduli per `7.0.0-34-generic`: riuscita.
- Avvisi di build: nome del compilatore differente, stessa versione GCC;
  `pahole`/`vmlinux` non disponibili per generare BTF. Non sono errori di build.
- Test C simulati: ripristino forzato dello stato Touch Bar, sospensione delle
  due interfacce e diagnostica ACPI one-shot: superati senza hardware I/O.
- Test shell simulati: utente richiedente/inibitori, ambito dei rami PCI,
  attesa del resume asincrono, ripristino e luminosità zero/nonzero/errore:
  superati. I controlli di presenza PCI usano directory temporanee fittizie.
- Sintassi shell e compilazione sintattica degli script Python: superate.
- Manifest SHA-256 dei 15 file operativi: tutte le impronte corrispondono.
- `git diff --check`: nessun errore di whitespace.
- Ricerca mirata di marcatori di chiavi private e token nei file da includere:
  nessuna corrispondenza. Non equivale a un audit di sicurezza completo.
- La struttura del drop-in systemd era stata verificata con il parser systemd,
  senza avviare la sospensione; i log e la conferma dell'utente documentano
  anche i successivi cicli reali riusciti.

## Limitazioni da mantenere visibili nel fork

- Il risultato hardware riguarda un MacBookPro14,2; non è una certificazione
  di tutti i T1 o di altri kernel.
- Il workaround è una combinazione: non è stata isolata la causa firmware.
- La sospensione è rifiutata con periferiche rilevate; un Mac chiuso può restare
  sveglio. Ibernazione e suspend-then-hibernate non sono coperti.
- Il parametro `test_resume_acpi_once` è ancora presente, disattivato per
  default e scrivibile solo da root. La prova ha provocato un blocco: non
  armarlo. Gli script richiedono `N` e `skip_acpi_power=1`.
- Anche `test_skip_suspend_display_off_once` è diagnostico e deve restare `N`.
- I diagnostici vengono conservati nello snapshot per mantenere identica la
  versione verificata, non per raccomandarne l'uso. Una futura versione senza
  quei parametri richiederà nuovi hash, adeguamento dei controlli e nuova verifica.
- Il controllo `srcversion` è restrittivo intenzionalmente; aggiornamenti di
  driver/kernel richiedono revisione e possono far rifiutare la sospensione.
- I test simulati non coprono guasti firmware, hotplug fisico concorrente o
  tutti i possibili errori dell'installer. Il ripristino non può funzionare se
  il kernel è bloccato.

## Separazione prevista dei commit

1. Driver iBridge/Touch Bar, test relativi, helper DKMS e diagnostico HID;
   esclusione degli artefatti di build.
2. Gestione protetta s2idle, retroilluminazione, installer/disinstallatore e
   test shell senza dipendenze dall'hardware.
3. Guida riproducibile, note operative, manifest, README e questa verifica.

Prima della pubblicazione scegliere un'identità autore Git appropriata:
nome ed email fanno parte dei commit, anche se vengono creati solo localmente.
