#!/bin/sh
# Install or remove the late-boot T1 Touch Bar binding service.
set -eu

readonly here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
readonly source_helper="$here/t1-touchbar-enable.sh"
readonly source_unit="$here/t1-touchbar-enable.service"
readonly helper=/usr/local/libexec/t1-touchbar/t1-touchbar-enable
readonly unit=/etc/systemd/system/t1-touchbar-enable.service
readonly state=/var/lib/t1-touchbar-enable

die() { printf '%s\n' "STOP: $*" >&2; exit 1; }
usage() { printf '%s\n' "Usage: sudo $0 --install | --update | --remove" >&2; }

[ "$(id -u)" -eq 0 ] || die 'Run this installer with sudo.'
[ "$#" -eq 1 ] || { usage; exit 2; }

case "$1" in
	--install)
		[ -r "$source_helper" ] && [ -r "$source_unit" ] || die 'Installer files are incomplete.'
		[ ! -e "$helper" ] && [ ! -e "$unit" ] && [ ! -e "$state" ] ||
			die 'An existing Touch Bar boot-fix installation was found; refusing to overwrite it.'
		install -d -m 755 /usr/local/libexec/t1-touchbar /etc/systemd/system "$state"
		install -o root -g root -m 755 "$source_helper" "$helper"
		install -o root -g root -m 644 "$source_unit" "$unit"
		sha256sum "$helper" "$unit" > "$state/manifest"
		systemctl daemon-reload
		systemctl enable t1-touchbar-enable.service
		printf '%s\n' 'Installed outside the source tree. Reboot normally to test it.'
		;;
	--update)
		[ -r "$source_helper" ] && [ -r "$source_unit" ] || die 'Installer files are incomplete.'
		[ -f "$state/manifest" ] || die 'Managed installation not found.'
		sha256sum --check "$state/manifest" >/dev/null || die 'Installed files changed; refusing automatic update.'
		install -o root -g root -m 755 "$source_helper" "$helper"
		install -o root -g root -m 644 "$source_unit" "$unit"
		sha256sum "$helper" "$unit" > "$state/manifest"
		systemctl daemon-reload
		systemctl reset-failed t1-touchbar-enable.service
		printf '%s\n' 'Installed files updated outside the source tree. The next boot uses the new helper.'
		;;
	--remove)
		[ -f "$state/manifest" ] || die 'Managed installation not found.'
		sha256sum --check "$state/manifest" >/dev/null || die 'Installed files changed; refusing automatic removal.'
		backup=$(mktemp -d /var/tmp/t1-touchbar-enable-removed.XXXXXX)
		systemctl disable --now t1-touchbar-enable.service
		mv "$unit" "$helper" "$state/manifest" "$backup/"
		rmdir "$state"
		rmdir /usr/local/libexec/t1-touchbar 2>/dev/null || true
		systemctl daemon-reload
		printf '%s\n' "Removed files were preserved in $backup"
		;;
	*)
		usage
		exit 2
		;;
esac
