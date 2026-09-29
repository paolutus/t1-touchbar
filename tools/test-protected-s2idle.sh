#!/usr/bin/env bash
# Diagnostic for this MacBookPro14,2 only. No installed hooks, services or GRUB edits.
# Default is read-only. --run requires root, local terminal and explicit confirmation.
set -euo pipefail

roots=(0000:03:00.0 0000:79:00.0)
parents=(0000:00:1c.4 0000:00:1d.0)
endpoints=(0000:05:00.0 0000:06:00.0 0000:7b:00.0 0000:7c:00.0)
pm_devices=(0000:01:00.0 0000:05:00.0 0000:7b:00.0)
pci=/sys/bus/pci/devices
declare -A saved_pm=()
old_sleep=
changed=0
removed=0
sleep_requested=0
sleep_finished=0
sleep_before=0
request_user=
kbd_path=/sys/class/leds/spi::kbd_backlight/brightness
saved_kbd=
kbd_changed=0

die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
put() { printf '%s\n' "$2" > "$1"; }

save_settings() {
    local dev
    old_sleep=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/power/mem_sleep)
    [[ "$old_sleep" == deep || "$old_sleep" == s2idle ]] || die 'Modalità iniziale non riconosciuta.'
    for dev in "${pm_devices[@]}"; do saved_pm[$dev]=$(< "$pci/$dev/d3cold_allowed"); done
    saved_kbd=$(< "$kbd_path")
    [[ "$saved_kbd" =~ ^[0-9]+$ && "$saved_kbd" -le 255 ]] || die 'Luminosità tastiera non valida.'
}

prepare_hardware() {
    local dev
    changed=1
    for dev in "${pm_devices[@]}"; do
        put "$pci/$dev/d3cold_allowed" 0
        [[ $(< "$pci/$dev/d3cold_allowed") == 0 ]] || die "Impostazione D3cold fallita per $dev."
    done
    put /sys/power/mem_sleep s2idle
    [[ $(< /sys/power/mem_sleep) == *'[s2idle]'* ]] || die 'Selezione s2idle fallita.'
    check_peripherals
    for dev in "${roots[@]}"; do
        removed=1
        put "$pci/$dev/remove" 1
        [[ ! -e "$pci/$dev" ]] || die "Rimozione di $dev non completata."
    done
    check_acpi_and_driver
    kbd_changed=1
    put "$kbd_path" 0
    note "Retroilluminazione tastiera: $saved_kbd -> 0"
    sync
}

request_suspend() {
    # PCI writes need root; the sleep request belongs to the desktop user.
    # Keep inhibitor checks on without misidentifying that user's own session.
    runuser -u "$request_user" -- systemctl --check-inhibitors=yes "$@" suspend
}

in_thunderbolt_tree() {
    case "$1" in
        */0000:03:00.0|*/0000:03:00.0/*|*/0000:79:00.0|*/0000:79:00.0/*) return 0 ;;
        *) return 1 ;;
    esac
}

check_peripherals() {
    local node path name
    # Reject even unmounted disks: removal must not race open files or raw I/O.
    for node in /sys/class/block/* /sys/class/net/*; do
        [[ -e "$node/device" ]] || continue
        path=$(readlink -f "$node/device")
        if in_thunderbolt_tree "$path"; then
            die "Disco/rete nel ramo Thunderbolt: $node. Scollegare tutte le periferiche."
        fi
    done
    for node in /sys/bus/usb/devices/*; do
        name=${node##*/}
        [[ "$name" =~ ^[0-9]+-[0-9]+(\.[0-9]+)*$ ]] || continue
        path=$(readlink -f "$node")
        if in_thunderbolt_tree "$path"; then
            die "Periferica USB nel ramo Thunderbolt: $name. Scollegarla."
        fi
    done
    for node in /sys/class/drm/card*-*/status; do
        [[ -f "$node" ]] || continue
        [[ $(< "$node") == connected ]] || continue
        case "$node" in */card*-eDP-*/status|*/card*-LVDS-*/status) continue ;; esac
        die "Monitor esterno collegato: $node. Scollegarlo."
    done
    # Only the known built-in bridges/controllers may be removed by this test.
    for node in "$pci"/*; do
        path=$(readlink -f "$node")
        in_thunderbolt_tree "$path" || continue
        case "${node##*/}" in
            0000:03:00.0|0000:04:00.0|0000:04:01.0|0000:04:02.0|0000:04:04.0|\
            0000:05:00.0|0000:06:00.0|0000:79:00.0|0000:7a:00.0|0000:7a:01.0|\
            0000:7a:02.0|0000:7a:04.0|0000:7b:00.0|0000:7c:00.0) ;;
            *) die "Dispositivo PCI aggiuntivo nel ramo Thunderbolt: ${node##*/}" ;;
        esac
    done
}

check_acpi_and_driver() {
    local p=/sys/module/apple_ibridge/parameters
    [[ $(< "$p/skip_acpi_power") == 1 ]] || die 'Richiesto skip_acpi_power=1.'
    [[ $(< "$p/test_resume_acpi_once") == N ]] || die 'Test ACPI armato: non procedere.'
    [[ $(< /sys/module/apple_touchbar/parameters/test_skip_suspend_display_off_once) == N ]] ||
        die 'Disarmare il precedente test display prima di procedere.'
    [[ $(< /sys/module/apple_touchbar/srcversion) == E8CEB54C26CE50C4955BFCA ]] ||
        die 'Modulo Touch Bar diverso dalla versione esaminata: ricontrollare prima della prova.'
}

check_all() {
    local i dev id config value
    [[ $(< /sys/class/dmi/id/product_name) == MacBookPro14,2 ]] || die 'Modello diverso da MacBookPro14,2.'
    [[ $(< /sys/power/mem_sleep) == *s2idle* ]] || die 's2idle non disponibile.'
    [[ " $(< /proc/cmdline) " == *' pcie_port_pm=off '* ]] || die 'Manca pcie_port_pm=off nel boot attuale.'
    [[ $(< "$pci/0000:01:00.0/vendor") == 0x106b && $(< "$pci/0000:01:00.0/device") == 0x2003 ]] ||
        die 'SSD diverso dall’Apple S3X atteso.'
    [[ $(readlink -f /sys/bus/usb/devices/1-3) == /sys/devices/pci0000:00/0000:00:14.0/usb1/1-3 ]] ||
        die 'Percorso iBridge diverso da quello esaminato.'
    [[ $(< /sys/bus/usb/devices/1-3/idVendor) == 05ac && $(< /sys/bus/usb/devices/1-3/idProduct) == 8600 ]] ||
        die 'iBridge normale non presente.'
    for i in 0 1; do
        dev=${roots[i]}
        [[ $(readlink -f "$pci/$dev") == "/sys/devices/pci0000:00/${parents[i]}/$dev" ]] ||
            die "Topologia inattesa per $dev."
        [[ $(< "$pci/$dev/vendor") == 0x8086 && $(< "$pci/$dev/device") == 0x1578 ]] ||
            die "Identità inattesa per $dev."
        [[ -w "$pci/$dev/remove" && -w "$pci/${parents[i]}/rescan" ]] || die "Accesso insufficiente a $dev."
    done
    for dev in "${roots[@]}" "${endpoints[@]}"; do
        [[ -e "$pci/$dev" ]] || die "$dev assente: riavviare prima della prova."
        id=$(setpci -s "$dev" VENDOR_ID)
        [[ "$id" == 8086 ]] || die "$dev non risponde correttamente ($id): riavviare."
    done
    for dev in "${pm_devices[@]}"; do
        [[ -w "$pci/$dev/d3cold_allowed" ]] || die "Parametro D3cold non disponibile per $dev."
        value=$(< "$pci/$dev/d3cold_allowed")
        [[ "$value" == 0 || "$value" == 1 ]] || die "Valore D3cold inatteso per $dev."
    done
    check_peripherals
    check_acpi_and_driver
    [[ -w "$kbd_path" && $(< /sys/class/leds/spi::kbd_backlight/max_brightness) == 255 ]] ||
        die 'Controllo della retroilluminazione tastiera non disponibile.'
    config=$(systemd-analyze cat-config systemd/sleep.conf)
    # Fail conservatively on explicit overrides rather than silently testing deep.
    while IFS= read -r value; do
        [[ -z "$value" || "$value" == s2idle ]] || die "MemorySleepMode=$value sovrascriverebbe la prova."
    done < <(printf '%s\n' "$config" | sed -nE 's/^[[:space:]]*MemorySleepMode[[:space:]]*=[[:space:]]*(.*)/\1/p')
    while IFS= read -r value; do
        [[ -z "$value" || "$value" == mem || "$value" == freeze ]] || die "SuspendState=$value da esaminare prima della prova."
    done < <(printf '%s\n' "$config" | sed -nE 's/^[[:space:]]*SuspendState[[:space:]]*=[[:space:]]*(.*)/\1/p')
    if [[ ${1:-manual} != service ]]; then
        case $(systemctl show systemd-suspend.service -p ActiveState --value) in
            inactive|failed) ;;
            *) die 'Servizio di sospensione occupato.' ;;
        esac
        request_suspend --dry-run || die 'Controllo preventivo della sospensione rifiutato; nessuna modifica hardware.'
    fi
    note 'Controlli superati. Nessuna impostazione modificata.'
}

wait_for_resume() {
    local stamp state
    # systemctl suspend returns when queued, not necessarily after wake.
    # The persistent start timestamp catches even a very short suspend cycle.
    while :; do
        stamp=$(systemctl show systemd-suspend.service -p InactiveExitTimestampMonotonic --value) || return 1
        state=$(systemctl show systemd-suspend.service -p ActiveState --value) || return 1
        if [[ "$stamp" != "$sleep_before" && "$stamp" != 0 && ( "$state" == inactive || "$state" == failed ) ]]; then
            sleep_finished=1
            return 0
        fi
        sleep 1
    done
}

restore() {
    local rc=$? dev pass failures=0
    trap - EXIT
    # Do not interrupt restoration or race the outstanding suspend operation.
    trap '' INT TERM HUP
    set +e
    if (( sleep_requested && !sleep_finished )); then
        note 'Attendo la conclusione della sospensione prima del ripristino...'
        if ! wait_for_resume; then
            note 'STOP: stato della sospensione sconosciuto. Evito scritture PCI concorrenti.'
            note 'Salvare il lavoro e riavviare per ripristinare le impostazioni temporanee.'
            exit 1
        fi
    fi
    restore_hardware || rc=1
    exit "$rc"
}

restore_hardware() {
    local dev pass failures=0
    if (( changed )); then
        note 'Ripristino delle impostazioni temporanee...'
        if (( removed )); then
            # Rescan only the two parent ports, not unrelated PCI buses.
            for pass in 1 2; do
                for dev in "${parents[@]}"; do
                    put "$pci/$dev/rescan" 1 || failures=1
                done
                sleep 2
            done
        fi
        for dev in "${pm_devices[@]}"; do
            put "$pci/$dev/d3cold_allowed" "${saved_pm[$dev]}" || failures=1
        done
        put /sys/power/mem_sleep "$old_sleep" || failures=1
        if (( kbd_changed )); then
            put "$kbd_path" "$saved_kbd" || failures=1
            note "Retroilluminazione tastiera ripristinata a $saved_kbd."
        fi
        for dev in "${roots[@]}" "${endpoints[@]}"; do
            [[ -e "$pci/$dev" ]] || { note "ATTENZIONE: $dev non è ricomparso."; failures=1; }
        done
        if (( failures )); then
            note 'Ripristino incompleto: salvare il lavoro e riavviare. Non ripetere il test.'
        else
            note 'Impostazioni ripristinate; i controller risultano presenti. Verificare il funzionamento reale.'
        fi
    fi
    return "$failures"
}

main() {
    local action=${1:---check} dev answer stamp result
    [[ $# -le 1 && ( "$action" == --check || "$action" == --run ) ]] || die 'Uso: sudo bash tools/test-protected-s2idle.sh [--check|--run]'
    (( EUID == 0 )) || die 'Servono privilegi root anche per leggere i parametri protetti: usare sudo bash.'
    [[ ${SUDO_UID:-} =~ ^[0-9]+$ && ${SUDO_UID:-0} != 0 && -n ${SUDO_USER:-} ]] ||
        die 'Avviare con sudo dal proprio terminale grafico, non da una shell root.'
    request_user=$SUDO_USER
    [[ $(id -u -- "$request_user") == "$SUDO_UID" ]] || die 'Identità dell’utente sudo incoerente.'
    for dev in setpci systemctl systemd-analyze journalctl flock runuser; do
        command -v "$dev" >/dev/null || die "Comando mancante: $dev"
    done
    check_all
    [[ "$action" == --run ]] || return 0
    [[ ! -e /etc/systemd/system/systemd-suspend.service.d/90-t1-sleep-guard.conf ]] ||
        die 'Gestione permanente installata: usare la normale sospensione, non questo test.'
    [[ -t 0 && -t 1 && -z ${SSH_CONNECTION:-} ]] || die 'Eseguire da un terminale locale, non da SSH.'
    # /run is root-writable only (unlike /run/lock on some distributions).
    [[ ! -L /run/t1-protected-s2idle.lock ]] || die 'Lock inatteso.'
    exec 9>/run/t1-protected-s2idle.lock
    flock -n 9 || die 'Una prova è già in corso.'
    note 'PROVA SPERIMENTALE: può ancora bloccare il Mac. Nessuna garanzia di riaccensione della Touch Bar.'
    note 'Salvare e chiudere le applicazioni. Scollegare TUTTE le periferiche USB-C/Thunderbolt salvo alimentatore.'
    note 'La Touch Bar deve essere accesa. Lasciare il coperchio APERTO; per svegliare usare un tasto o una breve pressione del pulsante di accensione.'
    note 'Non collegare periferiche e non chiudere questo terminale fino al termine del ripristino.'
    read -r -p 'Per confermare queste condizioni e avviare la sospensione, scrivere PROVA: ' answer
    [[ "$answer" == PROVA ]] || die 'Annullato senza modifiche hardware.'
    check_all
    stamp=$(date '+%Y-%m-%d %H:%M:%S')
    save_settings
    sleep_before=$(systemctl show systemd-suspend.service -p InactiveExitTimestampMonotonic --value)
    [[ "$sleep_before" =~ ^[0-9]+$ ]] || die 'Impossibile leggere il riferimento temporale della sospensione.'
    trap restore EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    prepare_hardware
    note 'Richiedo la sospensione s2idle. Non chiudere il coperchio.'
    sleep_requested=1
    if ! request_suspend; then
        sleep_requested=0
        die 'Richiesta di sospensione rifiutata; ripristino senza forzarla.'
    fi
    wait_for_resume
    result=$(systemctl show systemd-suspend.service -p Result --value)
    note "Servizio di sospensione terminato: $result"
    journalctl -b -k --no-pager --since "$stamp" |
        grep -E 'PM:|iBridge platform|ACPI one-shot|Touchbar|Display command|Suspend test|D3cold|not ready|usb 1-3' || true
    [[ "$result" == success ]] || die 'La sospensione ha riportato un errore.'
    # EXIT restores both the PCI topology and the original power policy.
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
