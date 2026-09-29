#!/usr/bin/env bash
# Explicit install/remove only; never suspends or reloads kernel modules.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
action=${1:-}
state=/var/lib/t1-sleep-guard
targets=(
    /usr/local/libexec/t1-sleep-common.sh
    /usr/local/libexec/t1-sleep-guard
    /etc/systemd/sleep.conf.d/90-t1-s2idle.conf
    /etc/systemd/system/systemd-suspend.service.d/90-t1-sleep-guard.conf
)
sources=(
    "$here/test-protected-s2idle.sh"
    "$here/permanent/t1-sleep-guard"
    "$here/permanent/90-t1-s2idle.conf"
    "$here/permanent/90-t1-sleep-guard.conf"
)
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
[[ $# == 1 && ( "$action" == --install || "$action" == --remove ) ]] ||
    die 'Uso: sudo bash tools/install-permanent-sleep.sh --install|--remove'
(( EUID == 0 )) || die 'Eseguire con sudo.'
case $(systemctl show systemd-suspend.service -p ActiveState --value) in
    inactive|failed) ;;
    *) die 'Il servizio suspend è occupato. Non cambiare configurazione durante una sospensione.' ;;
esac
[[ ! -e /run/t1-sleep-guard ]] || die 'Ripristino hardware pendente: riavviare prima di installare/rimuovere.'
[[ ! -L /run/t1-protected-s2idle.lock ]] || die 'Lock inatteso.'
exec 9>/run/t1-protected-s2idle.lock
flock -n 9 || die 'Una prova è in corso.'

if [[ "$action" == --remove ]]; then
    [[ -f "$state/manifest" && ! -L "$state" ]] || die 'Installazione gestita non trovata.'
    sha256sum --check "$state/manifest" || die 'File modificati dopo l’installazione: non li rimuovo automaticamente.'
    backup=$(mktemp -d /var/tmp/t1-sleep-removed.XXXXXX)
    # Remove the activation drop-in first. Preserve every file for recovery.
    for i in 3 2 1 0; do mv -- "${targets[i]}" "$backup/"; done
    mv -- "$state/manifest" "$backup/manifest"
    rmdir "$state"
    systemctl daemon-reload
    printf 'Gestione permanente rimossa. File recuperabili in %s\n' "$backup"
    echo 'La normale sospensione torna alla configurazione precedente; il problema Touch Bar può tornare.'
    exit 0
fi

for file in "${targets[@]}"; do
    [[ ! -e "$file" && ! -L "$file" ]] || die "File già presente: $file. Non sovrascrivo configurazioni."
done
[[ ! -e "$state" && ! -L "$state" ]] || die 'Directory di gestione già presente.'
bash -n "${sources[0]}" "${sources[1]}"
bash "$here/test-protected-s2idle.sh" --check
echo 'Installerò la gestione automatica per le normali richieste suspend (anche dal coperchio).'
echo 'Con periferiche USB-C/Thunderbolt o monitor esterni rilevati, la sospensione sarà RIFIUTATA.'
echo 'Non riporre il Mac chiuso in una borsa senza verificare che sia realmente sospeso.'
echo 'Non vengono cambiati GRUB, driver, firmware, Wi-Fi o le impostazioni KDE del coperchio.'
[[ -t 0 ]] || die 'Confermare da un terminale locale.'
read -r -p 'Scrivere INSTALLA per continuare: ' answer
[[ "$answer" == INSTALLA ]] || die 'Annullato.'

written=()
rollback() {
    local rc=$? file backup
    trap - EXIT
    if (( rc != 0 && ${#written[@]} )); then
        backup=$(mktemp -d /var/tmp/t1-sleep-install-failed.XXXXXX)
        for file in "${written[@]}"; do [[ ! -f "$file" ]] || mv -- "$file" "$backup/"; done
        if [[ -f "$state/manifest" ]]; then mv -- "$state/manifest" "$backup/manifest"; fi
        rmdir "$state" 2>/dev/null || true
        systemctl daemon-reload || true
        printf 'Installazione annullata; file conservati in %s\n' "$backup" >&2
    fi
    exit "$rc"
}
trap rollback EXIT
install -d -m 755 /usr/local/libexec /etc/systemd/sleep.conf.d /etc/systemd/system/systemd-suspend.service.d
install -d -m 700 "$state"
for i in 0 1 2 3; do
    # Record the exact target before copying, to cover a partial copy failure.
    written+=("${targets[i]}")
    mode=644
    [[ "$i" != 1 ]] || mode=755
    install -o root -g root -m "$mode" "${sources[i]}" "${targets[i]}"
done
sha256sum "${targets[@]}" > "$state/manifest"
systemctl daemon-reload
trap - EXIT
echo 'Installazione completata. Nessuna sospensione eseguita; non serve ricompilare o riavviare.'
echo 'Primo controllo: salvare il lavoro, scollegare periferiche, chiudere e riaprire il coperchio.'
echo 'Log: journalctl -b -u systemd-suspend.service --no-pager -n 100'
echo 'Rimozione: sudo bash tools/install-permanent-sleep.sh --remove'
