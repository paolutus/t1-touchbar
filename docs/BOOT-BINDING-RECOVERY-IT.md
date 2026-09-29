# Recupero Touch Bar al boot — MacBookPro14,2

Italiano | [English](BOOT-BINDING-RECOVERY-EN.md)

## Problema e causa

Sul MacBookPro14,2 di riferimento la Touch Bar era nera già al boot, prima della sospensione, con driver DKMS e iBridge `05ac:8600` corretti.

`hid-sensor-hub` aveva associato l'interfaccia display interna:

```text
hid-sensor-hub ... HID_PHYS=usb-0000:00:14.0-3/input3
apple-ibridge-hid ... HID_PHYS=usb-0000:00:14.0-3/input2
```

Il driver iBridge riceveva solo la tastiera virtuale e mancava `Touchbar activated with mode and display interfaces`. I numeri HID `.0002`, `.0006`, ecc. cambiano tra avvii e non vanno fissati in configurazione.

## Correzione permanente

Il servizio tardivo trova l'iBridge dal percorso fisico `00:14.0-3/input3`; se posseduto da `hid-sensor-hub`, lo scollega e lo assegna a `apple-ibridge-hid`. Non cambia firmware, GRUB, DKMS o impostazioni di suspend.

```bash
cd /percorso/della/copia/t1-touchbar
bash -n tools/t1-touchbar-enable.sh tools/install-touchbar-boot-fix.sh
sudo bash tools/install-touchbar-boot-fix.sh --install
```

I file operativi, indipendenti dalla checkout, sono:

| File | Scopo |
| --- | --- |
| `/usr/local/libexec/t1-touchbar/t1-touchbar-enable` | Helper eseguito al boot |
| `/etc/systemd/system/t1-touchbar-enable.service` | Unità systemd abilitata |
| `/var/lib/t1-touchbar-enable/manifest` | Impronte per aggiornamento/rimozione protetti |

La checkout può essere spostata dopo l'installazione. Riavviare normalmente e verificare:

```bash
systemctl status t1-touchbar-enable.service --no-pager
journalctl -b -u t1-touchbar-enable.service --no-pager
journalctl -b -k --no-pager | grep -E 'Touchbar activated|Display command' | tail -20
```

Attesi: `active (exited)`, `SUCCESS`, l'attivazione Touch Bar nel kernel e barra visibilmente accesa. La conferma visiva resta necessaria.

Aggiornamento delle copie installate non modificate:

```bash
sudo bash tools/install-touchbar-boot-fix.sh --update
```

Rimozione reversibile:

```bash
sudo bash tools/install-touchbar-boot-fix.sh --remove
```

La rimozione sposta i file in una directory `/var/tmp/t1-touchbar-enable-removed.*` stampata a video; non disinstalla il driver e la Touch Bar può tornare nera al boot.

## Limiti

Testato su un solo MacBookPro14,2. Non applicarlo ad altri modelli o topologie USB senza nuova verifica. Se il servizio vede un driver inatteso, non tocca l'interfaccia. Non fare unbind/rebind casuali, non scaricare moduli a caldo e non armare il test SOCW.

Integra, ma non sostituisce, la [guida completa di suspend](MACBOOKPRO14-2-SUSPEND-IT.md).
