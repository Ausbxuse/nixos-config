#!/usr/bin/env bash

nix build .#gnome-iso

sudo dd if=./result/iso/gnome.iso of=/dev/sdX bs=64M status=progress oflag=sync
