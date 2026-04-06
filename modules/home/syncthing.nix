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
# Peers are derived from hostDefs: only hosts marked as introducers
# (syncthing.introducer = true) are declared as peers. The introducer
# hub (e.g. a VPS) handles discovery — clients don't need to know about
# each other directly.
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
  # Pinning is gated on deviceId only. The sops.secrets declarations always
  # go through — in public builds the stub nix-secrets accepts and discards
  # them; in private builds the real sops-nix module processes them.
  pinned = selfDeviceId != null;

  # Only introducer hubs are declared as peers. They handle discovery of
  # other devices automatically — no need to list every host here.
  peers =
    filterAttrs
    (name: def: name != hostname && (def.syncthing.introducer or false) && (def.syncthing.deviceId or null) != null)
    hostDefs;

  peerDevices =
    lib.mapAttrs
    (name: def: {
      id = def.syncthing.deviceId;
      addresses = ["dynamic"];
      introducer = def.syncthing.introducer or false;
    })
    peers;

  home = config.home.homeDirectory;
  vaultDir = "${home}/vault";
in
  {
    home.packages = with pkgs; [
      keepassxc
    ];

    # Ensure the vault directory exists before syncthing starts.
    home.activation.createSyncDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p ${lib.escapeShellArg vaultDir}
      run mkdir -p ${lib.escapeShellArg "${home}/Media"}
      run mkdir -p ${lib.escapeShellArg "${home}/Media/Phone"}
      run mkdir -p ${lib.escapeShellArg "${home}/Media/Pictures"}
      run mkdir -p ${lib.escapeShellArg "${home}/Media/Videos"}
      run mkdir -p ${lib.escapeShellArg "${home}/Media/Audio"}
      run mkdir -p ${lib.escapeShellArg "${home}/Documents"}
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
          folders.media = {
            id = "media";
            label = "Media";
            path = "${home}/Media";
            devices = lib.attrNames peerDevices;
            # Exclude the phone ingest dir — it has its own folder.
            ignorePatterns = ["/Phone"];
          };
          folders.documents = {
            id = "documents";
            label = "Documents";
            path = "${home}/Documents";
            devices = lib.attrNames peerDevices;
          };
          # Phone DCIM ingest — receive-only. Phone is set to send-only.
          # Files land here, get sorted into Media/{Pictures,Videos,...}
          # by the phone-media-sort service, then the phone can delete
          # its copies freely without affecting the sorted files.
          folders.phone-dcim = {
            id = "phone-dcim";
            label = "Phone DCIM";
            path = "${home}/Media/Phone";
            devices = lib.attrNames peerDevices;
            type = "receiveonly";
          };
        };
      }
      // optionalAttrs pinned {
        cert = config.sops.secrets."syncthing-cert-${hostname}".path;
        key = config.sops.secrets."syncthing-key-${hostname}".path;
      };
  }
  # Declare the sops secrets that hold this host's pinned syncthing identity.
  # These names are produced during `nix run .#enroll`, which generates a
  # fresh cert/key on the admitting peer and writes them into nix-secrets'
  # secrets.yaml under exactly these keys. Guarded so this module still
  # evaluates on public builds where the sops home-manager module is absent.
  // optionalAttrs pinned {
    sops.secrets."syncthing-cert-${hostname}" = {};
    sops.secrets."syncthing-key-${hostname}" = {};
  }
