set shell := ["bash", "-uc"]

# GENERATION := $$(nixos-rebuild list-generations --flake ".\#" | grep current)

gitgc:
  git reflog expire --expire-unreachable=now --all
  git gc --prune=now

dconf:
	rsync -av ~/.config/dconf/ ./hosts/base/home/gnome/dconf

sys:
	nixos-rebuild switch --flake .#$(hostname) --use-remote-sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000

home:
  home-manager switch --flake .#$(whoami)@$(hostname)

debug:
	nixos-rebuild switch --flake . --use-remote-sudo --show-trace --verbose

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

# Regenerate nix-secrets/.sops.yaml from machines/defs.nix + machines/operators.nix
# and re-encrypt secrets.yaml. Run after editing either file.
rotate-secrets:
	nix run .#admit-host

# Provision a fresh NixOS host into the secrets trust mesh.
# Runs admit-host locally, rsyncs nix-secrets to the target, and triggers
# nixos-rebuild switch on the target with --override-input nix-secrets.
# Usage:
#   just provision adhoc-nixos zhenyu@127.0.0.1:2224
#   just provision dev-box zhenyu@dev.example.com
provision HOSTNAME SSHDEST:
	nix run .#provision -- {{HOSTNAME}} {{SSHDEST}}
