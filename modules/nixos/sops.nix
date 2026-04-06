{
  inputs,
  pkgs,
  username,
  ...
}: {
  # Forwards to the nix-secrets flake input's NixOS module.
  # - In public builds the stub at ./secrets/nix-secrets is a no-op.
  # - Override nix-secrets at build time to inject real secrets. See
  #   secrets/nix-secrets/README.md.
  imports = [inputs.nix-secrets.nixosModules.default];

  # Derive a user-level age identity from /etc/ssh/ssh_host_ed25519_key so
  # the home-manager sops module can decrypt secrets.yaml using the same
  # recipient the system module already uses.
  #
  # Background: nix-secrets/home.nix points home-manager sops at
  # ${XDG_CONFIG_HOME}/sops/age/keys.txt. On a freshly installed host that
  # file doesn't exist, home activation fails, and the enroll rebuild
  # aborts. Home activation runs as the user and can't read the root-owned
  # host key directly, so we materialize the derived key here — root can
  # read /etc/ssh/ssh_host_ed25519_key, and this runs before home-manager
  # activation.
  system.activationScripts.userSopsAgeKey = {
    deps = ["users" "groups"];
    text = ''
      if [ -f /etc/ssh/ssh_host_ed25519_key ] && [ -d /home/${username} ]; then
        install -d -m 0700 -o ${username} -g users \
          /home/${username}/.config/sops/age
        tmp=$(mktemp)
        if ${pkgs.ssh-to-age}/bin/ssh-to-age \
             -private-key -i /etc/ssh/ssh_host_ed25519_key -o "$tmp" 2>/dev/null
        then
          install -m 0600 -o ${username} -g users "$tmp" \
            /home/${username}/.config/sops/age/keys.txt
        fi
        rm -f "$tmp"
      fi
    '';
  };
}
