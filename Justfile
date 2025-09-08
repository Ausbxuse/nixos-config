set shell := ["bash", "-uc"]

# GENERATION := $$(nixos-rebuild list-generations --flake ".\#" | grep current)

gitgc:
  git reflog expire --expire-unreachable=now --all
  git gc --prune=now

dconf: 
	rsync -av ~/.config/dconf/ ./hosts/base/home/gnome/dconf

build-host:
	nixos-rebuild switch --flake .#$(hostname) --use-remote-sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000

build-home:
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

clean:
	# Remove all generations older than 7 days
	sudo nix profile wipe-history --profile /nix/var/nix/profiles/system  --older-than 7d

gc:
	# Garbage collect all unused nix store entries
	sudo nix-collect-garbage --delete-old

