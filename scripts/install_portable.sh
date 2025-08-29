#!/bin/bash

set -ex
export PATH=$PATH:$HOME/.local/bin
mkdir -p .local/bin
cd .local/bin

# Download nix-portable
curl -L "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m)" > ./nix-portable

# Generate symlinks for seamless integration
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
NP_RUNTIME=bwrap nix-portable nix shell nixpkgs#{bashInteractive,nix} <<EOF
nix run github:nix-community/home-manager -- switch --flake .#zhenyu@earthy
EOF

# Make new sessions use the shell automatically
cat >~/.bashrc <<EOF
export PATH=\$PATH:\$HOME/.local/bin

if [ -z "\$__NIX_PORTABLE_ACTIVATED" ]; then
        export __NIX_PORTABLE_ACTIVATED=1
        NP_RUNTIME=bwrap nix-portable nix run nixpkgs#bashInteractive --offline
        exit
else
        . \$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
fi

# If not running interactively, don't do anything
[[ \$- != *i* ]] && return

# Set something for the cmd line
PS1='[\u@\h \W]\\\$ '
EOF

echo 'Please remember to relogin so that the environment gets activated'
