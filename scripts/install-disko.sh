#!/usr/bin/env bash

set -e
host="spacy"

read -r pw
git clone https://github.com/ausbxuse/nix-conf --depth 1 -b dev
lsblk # sort out the most probable disk (fzf?)
# vim /tmp/secret.key
echo -n "$pw" > /tmp/secret.key
sudo nix run github:nix-community/disko -- --mode destroy,format,mount ./hosts/$host/disk.nix
# nix run github:nix-community/disko -- \
#   --mode disko --flake "${FLAKE}" --argstr disk "${DISK}"
sudo nixos-generate-config --no-filesystems --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix ./hosts/$host/
sudo nixos-install --root /mnt --flake .#spacy
#nixos-enter
