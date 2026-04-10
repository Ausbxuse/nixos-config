set shell := ["bash", "-uc"]

# GENERATION := $$(nixos-rebuild list-generations --flake ".\#" | grep current)

gitgc:
  git reflog expire --expire-unreachable=now --all
  git gc --prune=now

dconf:
	rsync -av ~/.config/dconf/ ./hosts/base/home/gnome/dconf

sys:
	nixos-rebuild switch --flake .#$(hostname) --sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000 $(user_home="$HOME"; if [ -n "${SUDO_USER:-}" ]; then user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"; fi; if [ -d "$user_home/src/private/nix-secrets" ]; then echo "--override-input nix-secrets path:$user_home/src/private/nix-secrets"; fi)

home:
  home-manager switch --flake .#$(if [ -n "${SUDO_USER:-}" ]; then printf '%s' "$SUDO_USER"; else whoami; fi)@$(hostname) $(user_home="$HOME"; if [ -n "${SUDO_USER:-}" ]; then user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"; fi; if [ -d "$user_home/src/private/nix-secrets" ]; then echo "--override-input nix-secrets path:$user_home/src/private/nix-secrets"; fi)

debug:
	nixos-rebuild switch --flake . --sudo --show-trace --verbose $(user_home="$HOME"; if [ -n "${SUDO_USER:-}" ]; then user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"; fi; if [ -d "$user_home/src/private/nix-secrets" ]; then echo "--override-input nix-secrets path:$user_home/src/private/nix-secrets"; fi)

# Update specific input
# usage: make upp i=home-manager
upp:
	nix flake lock --update-input $(i)

history:
	nix profile history --profile /nix/var/nix/profiles/system

repl:
	nix repl -f flake:nixpkgs

fmt:
	alejandra .

precommit-install:
	pre-commit install

precommit:
	pre-commit run --all-files

clean:
	# Remove all generations older than 7 days
	sudo nix profile wipe-history --profile /nix/var/nix/profiles/system  --older-than 7d

gc:
	# Garbage collect all unused nix store entries
	sudo nix-collect-garbage --delete-old

# Regenerate nix-secrets/.sops.yaml from private hosts.nix
# and re-encrypt secrets.yaml. Run after editing either file.
rotate-secrets:
	nix run .#admit-host

# enroll a fresh NixOS host into the secrets trust mesh.
# Runs admit-host locally, rsyncs nix-secrets to the target, and triggers
# nixos-rebuild switch on the target with --override-input nix-secrets.
# Usage:
#   just enroll custom-nixos zhenyu@127.0.0.1:2224
#   just enroll dev-box zhenyu@dev.example.com
enroll HOSTNAME SSHDEST:
	nix run .#enroll -- {{HOSTNAME}} {{SSHDEST}}

# Trigger a recovery backup manually (requires RECOVERY USB plugged in).
backup-bundle:
	sudo systemctl start recovery-backup.service

# Write the NixOS installer ISO to the USB installer partition.
# Usage: just refresh-installer-usb /dev/sdX1
refresh-installer-usb PARTITION:
	nix build .#gnome-iso
	sudo dd if=$(ls ./result/iso/*.iso) of={{PARTITION}} bs=64M status=progress oflag=sync
