#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

die() { echo "ERROR: $*" >&2; exit 1; }

lsblk -ndo PATH,TYPE,RM,SIZE,MODEL,TRAN | awk '$2=="disk" && $3==0 {print $0}'
read -rp "Enter target disk path (e.g. /dev/nvme0n1): " TARGET_DISK
[[ -n "${TARGET_DISK:-}" ]] || die "No input provided."
[[ -b "$TARGET_DISK" ]] || die "Not a block device: $TARGET_DISK"
[[ "$(lsblk -ndo TYPE "$TARGET_DISK")" == "disk" ]] || die "Not a whole disk: $TARGET_DISK"

DISK=$TARGET_DISK

sed -i "s|@DISK@|$DISK|" constants.nix
echo "Using: $DISK"


DEFAULT_TARGET=".#spacy"
DEFAULT_LUKS_PW="1"

read -e -i "$DEFAULT_TARGET" -rp "Enter flake target: " TARGET
HOST="${TARGET##*#}"
echo "Host is: $HOST"

read -e -i "$DEFAULT_LUKS_PW" -rp "Enter LUKS disk password: " LUKS_PW
echo "Using LUKS password: $LUKS_PW"

echo $LUKS_PW > /tmp/secret.key

sudo nix run github:nix-community/disko -- --mode destroy,format,mount --flake "${TARGET}"
sudo nixos-generate-config --no-filesystems --root /mnt
install -D -m 0644 /mnt/etc/nixos/hardware-configuration.nix "./hosts/${HOST}/hardware-configuration.nix"

sudo nixos-install --root /mnt --flake "${TARGET}"

mkdir -p /mnt/home/zhenyu/src/public/
rsync -avPz ./ /mnt/home/zhenyu/src/public/nixos-config
