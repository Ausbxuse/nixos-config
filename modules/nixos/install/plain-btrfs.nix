{
  hostDef,
  lib,
  ...
}: let
  install = hostDef.install or {};
  hasRequiredInstall =
    install ? disk
    && install.disk != ""
    && install ? swapSize
    && install.swapSize != "";
in {
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = install ? disk && install.disk != "";
          message = "hosts using the plain-btrfs install layout must set hostDef.install.disk.";
        }
        {
          assertion = install ? swapSize && install.swapSize != "";
          message = "hosts using the plain-btrfs install layout must set hostDef.install.swapSize.";
        }
      ];
    }
    (lib.mkIf hasRequiredInstall {
      disko.devices.disk.main = {
        type = "disk";
        device = install.disk;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = install.swapSize;
                  };
                };
              };
            };
          };
        };
      };
    })
  ];
}
