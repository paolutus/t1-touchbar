#!/usr/bin/env bash
# Install the candidate into the existing DKMS package, without live reloading.
set -euo pipefail

if (( EUID != 0 )); then
    echo "Eseguire con sudo bash tools/install-display-fix.sh" >&2
    exit 1
fi

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
kernel_release=$(uname -r)
dkms_source=/usr/src/apple-ib-drv-0.1
for driver in apple-ibridge.c apple-touchbar.c; do
    test -f "$project_dir/apple-ib-drv/$driver"
    test -f "$dkms_source/$driver"
done
test -d "/lib/modules/$kernel_release/build"
command -v dkms >/dev/null
command -v update-initramfs >/dev/null

backup_dir=$(mktemp -d /var/tmp/t1-display-backup.XXXXXX)
cp -a -- "$dkms_source/apple-ibridge.c" "$dkms_source/apple-touchbar.c" "$backup_dir/"
printf 'Sorgenti precedenti salvati in: %s\n' "$backup_dir"
printf 'Per ripristinarli: sudo install -m 644 %q/apple-ibridge.c %q/apple-touchbar.c %q/\n' \
    "$backup_dir" "$backup_dir" "$dkms_source"
echo 'Poi ricompilare/reinstallare DKMS e aggiornare initramfs come sotto.'

install -m 644 -- "$project_dir/apple-ib-drv/apple-ibridge.c" \
    "$project_dir/apple-ib-drv/apple-touchbar.c" "$dkms_source/"
dkms build --force -m apple-ib-drv -v 0.1 -k "$kernel_release"
dkms install --force -m apple-ib-drv -v 0.1 -k "$kernel_release"
update-initramfs -u -k "$kernel_release"

echo 'Installazione completata. Versioni su disco (non ancora caricate):'
for driver in apple_ibridge apple_touchbar; do
    printf '%s: ' "$driver"
    modinfo -k "$kernel_release" -F srcversion "$driver"
done
echo 'Salvare il lavoro e riavviare per caricare entrambi i nuovi moduli.'
