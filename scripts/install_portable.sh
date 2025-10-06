#!/bin/bash

set -ex
export PATH=$PATH:$HOME/.local/bin
mkdir -p ~/.local/bin
cd ~/.local/bin

curl -L "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m)" > ./nix-portable

chmod +x nix-portable
ln -s nix-portable nix
ln -s nix-portable nix-channel
ln -s nix-portable nix-copy-closure
ln -s nix-portable nix-env
ln -s nix-portable nix-instantiate
ln -s nix-portable nix-prefetch-url
ln -s nix-portable nix-store
ln -s nix-portable nix-build
ln -s nix-portable nix-collect-garbage
ln -s nix-portable nix-daemon
ln -s nix-portable nix-hash
ln -s nix-portable nix-shell

cd ~/src/public/nixos-config
rm ~/.bashrc ~/.profile
NP_RUNTIME=bwrap nix-portable nix shell nixpkgs#{bashInteractive,nix} <<EOF
nix run github:nix-community/home-manager -- switch --flake .#zhenyu@earthy
EOF

cat >~/hm-env <<EOF
#!/usr/bin/env bash

NP_RUNTIME=bwrap $HOME/.local/bin/nix-portable nix run nixpkgs#zsh
EOF

echo "exec zsh" >> ~/.bash_profile

chmod +x ~/hm-env
./hm-env
