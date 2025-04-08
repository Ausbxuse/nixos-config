set shell := ["bash", "-uc"]

# GENERATION := $$(nixos-rebuild list-generations --flake ".\#" | grep current)

gitgc:
  git reflog expire --expire-unreachable=now --all
  git gc --prune=now

dconf: 
	rsync -av ~/.config/dconf/ ./hosts/base/home/gnome/dconf

uni:
	nixos-rebuild switch --flake .#uni --use-remote-sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000

timy:
	nixos-rebuild switch --flake .#timy --use-remote-sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000

spacy:
	nixos-rebuild switch --flake .#spacy --use-remote-sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000

milkyway:
  nixos-rebuild switch --flake .#milkyway --use-remote-sudo --show-trace --print-build-logs --verbose --option max-call-depth 10000 --target-host root@zhenyuzhao.com

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

hm:
    home-manager switch --flake .#$(whoami)@$(hostname)
