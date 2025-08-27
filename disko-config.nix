# https://github.com/nix-community/disko/blob/master/docs/quickstart.md
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
            zfs = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                content = {
                  type = "zfs";
                  pool = "zroot";
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
            zfs = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptdata";
                content = {
                  type = "zfs";
                  pool = "zdata";
                };
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          compression = "zstd";
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          "com.sun:auto-snapshot" = "false";
        };
        options.ashift = "12";

        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options."com.sun:auto-snapshot" = "false";
          };
          "persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
          };
        };
      };
      zdata = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          compression = "zstd";
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          "com.sun:auto-snapshot" = "true";
        };
        postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zdata@blank$' || zfs snapshot zdata@blank";

        datasets = {
          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
          };
          "cache" = {
            type = "zfs_fs";
            mountpoint = "/cache";
          };
        };
      };
    };
  };
}

