#
# Syncthing — personal vault folder sync.
#
# Declarative layout:
#
#   ~/vault/                  user-facing; this is THE password vault + notes
#     vault.kdbx              KeePassXC database
#     vault.kdbx.key          keyfile (second factor)
#     notes/                  plain markdown
#
# Identity model:
#
# Each host has an optional `syncthing.deviceId` field in machines/defs.nix.
# When set, this module pins the host's syncthing identity by loading
# cert/key from sops secrets (syncthing-cert-${hostname},
# syncthing-key-${hostname}). That way a reinstall that restores the host's
# SSH key also restores its syncthing identity — consistent with how sops
# age identities already work. The sops.secrets declarations live in
# nix-secrets/home.nix (private flake input); this module only references
# their paths, and only when pinning is active.
#
# If deviceId is null, syncthing generates a fresh cert on first run; grab
# the device ID, encrypt the generated cert/key into nix-secrets, set
# deviceId in defs.nix, and rebuild.
#
# Peers are derived from hostDefs: every host with `syncthing.deviceId` set
# is automatically a trusted peer of every other host. No manual pairing.
#
# See docs/reproducing-from-scratch.md §"Phase F: vault bootstrap" for the
# one-time cert generation procedure.
#
{
  config,
  lib,
  pkgs,
  hostname,
  hostDef,
  hostDefs,
  ...
}: let
  inherit (lib) filterAttrs optionalAttrs;

  selfDeviceId = hostDef.syncthing.deviceId or null;
  pinned = selfDeviceId != null;

  # Every host in defs.nix that has a syncthing.deviceId is a trusted peer.
  peers =
    filterAttrs
    (name: def: name != hostname && (def.syncthing.deviceId or null) != null)
    hostDefs;

  peerDevices =
    lib.mapAttrs
    (name: def: {
      id = def.syncthing.deviceId;
      addresses = ["dynamic"];
    })
    peers;

  vaultDir = "${config.home.homeDirectory}/vault";
in
  {
    home.packages = with pkgs; [
      keepassxc
    ];

    # Ensure the vault directory exists before syncthing starts.
    home.activation.createVaultDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p ${lib.escapeShellArg vaultDir}
    '';

    services.syncthing =
      {
        enable = true;
        settings = {
          gui.address = "127.0.0.1:8384";
          options = {
            urAccepted = -1; # decline usage reporting
            relaysEnabled = true;
            natEnabled = true;
            globalAnnounceEnabled = true;
          };
          devices = peerDevices;
          folders.vault = {
            id = "vault";
            label = "vault";
            path = vaultDir;
            devices = lib.attrNames peerDevices;
            versioning = {
              type = "simple";
              params.keep = "10";
            };
          };
        };
      }
      # cert/key pinning only when (a) the host has a recorded deviceId and
      # (b) the sops home-manager module is actually loaded (private build).
      // optionalAttrs (pinned && (config ? sops)) {
        cert = config.sops.secrets."syncthing-cert-${hostname}".path;
        key = config.sops.secrets."syncthing-key-${hostname}".path;
      };
  }
  # Declare the sops secrets that hold this host's pinned syncthing identity.
  # These names are produced during `nix run .#provision`, which generates a
  # fresh cert/key on the admitting peer and writes them into nix-secrets'
  # secrets.yaml under exactly these keys. Guarded so this module still
  # evaluates on public builds where the sops home-manager module is absent.
  // optionalAttrs (pinned && (config ? sops)) {
    sops.secrets."syncthing-cert-${hostname}" = {};
    sops.secrets."syncthing-key-${hostname}" = {};
  }
