{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                content = {
                  type = "btrfs";
                  extraArgs = [ "-L" "nixos-root" ];
                  mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
                  subvolumes = {
                    "@root" = {
                      mountpoint = "/";
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                    };
                    "@swap" = {
                      mountpoint = "/swap";
                      mountOptions = [ "noatime" "nodatacow" "nodev" "nosuid" ];
                    };
                    "@persist" = {
                      mountpoint = "/persist";
                    };
                  };
                };
              };
            };
          };
        };
      };

      data = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptdata";
                content = {
                  type = "btrfs";
                  extraArgs = [ "-L" "nixos-data" ];
                  mountOptions = [ "compress=zstd" "noatime" "ssd" "space_cache=v2" ];
                  subvolumes = {
                    "@home" = {
                      mountpoint = "/home";
                    };
                    "@cache" = {
                      mountpoint = "/cache";
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
