# Disk layout: two ZFS pools, "erase your darlings" style.
# See docs/DISK-LAYOUT.md for the full picture and docs/INSTALL.md for the runbook.
#
#   nvme0n1 (256G, fast)  -> ESP (/boot) + pool `zroot`
#   sda     (512G, slow)  -> pool `zstorage`
#
# Both pools use ZFS native encryption with the SAME passphrase:
#   - zroot asks for it at boot (keylocation=prompt)
#   - zstorage reads it from a keyfile that lives on zroot (/persist/zfs/zstorage.key)
#     At format time disko needs a non-interactive key, so the keyfile is staged at
#     /tmp/zstorage.key; INSTALL.md moves it into /persist and updates keylocation.
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
                type = "zfs";
                pool = "zroot";
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
                type = "zfs";
                pool = "zstorage";
              };
            };
          };
        };
      };
    };

    zpool = {
      zroot = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          dnodesize = "auto";
          normalization = "formD";
          mountpoint = "none";
          canmount = "off";
          "com.sun:auto-snapshot" = "false";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          keylocation = "prompt";
        };
        datasets = {
          # local/* = disposable or rebuildable, never replicated
          "local" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
            # The blank snapshot the initrd rolls back to on every boot.
            postCreateHook = "zfs list -t snapshot zroot/local/root@blank || zfs snapshot zroot/local/root@blank";
          };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };
          # Ollama model blobs: large, re-downloadable, never replicated. Must
          # stay on the NVMe (zstorage is a QLC SATA drive) because llama.cpp
          # mmaps the GGUF and pages it in on demand.
          # recordsize=1M matches those large sequential reads; compression=off
          # because GGUF/MXFP4 weights are already compressed and zstd would
          # burn CPU on every page fault; primarycache=metadata stops the ARC
          # from caching the model a second time alongside mmap's page cache
          # (the ARC is capped at 12 GiB in system/zfs.nix, of 32 GiB total).
          # The path is /var/lib/private/ollama, not /var/lib/ollama: the module
          # runs ollama with DynamicUser, so systemd owns /var/lib/ollama as a
          # symlink into private/ and puts the real StateDirectory there.
          # Without this dataset the models live on local/root and are erased
          # by the blank-snapshot rollback on every boot, then re-downloaded.
          "local/ollama" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/private/ollama";
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
              compression = "off";
              primarycache = "metadata";
            };
          };
          # safe/* = the data that matters; snapshotted + replicated to zstorage
          "safe" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "safe/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };
          "safe/persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.mountpoint = "legacy";
          };
          # ZFS misbehaves near 100% full; this reservation can be shrunk in an
          # emergency to free space: zfs set refreservation=none zroot/reserved
          "reserved" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              refreservation = "10G";
            };
          };
        };
      };

      zstorage = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          dnodesize = "auto";
          normalization = "formD";
          mountpoint = "none";
          canmount = "off";
          "com.sun:auto-snapshot" = "false";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          # Install-time location; INSTALL.md switches this to
          # file:///persist/zfs/zstorage.key after the first mount.
          keylocation = "file:///tmp/zstorage.key";
        };
        datasets = {
          "games" = {
            type = "zfs_fs";
            mountpoint = "/games";
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
          # ComfyUI model checkpoints: huge, re-downloadable, not replicated.
          # Mounts on top of the /persist-backed /var/lib/comfyui bind mount.
          "comfyui-models" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/comfyui/models";
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
          # Replication targets. syncoid creates backup/home and backup/persist
          # on its first run; they receive raw (still-encrypted) streams and are
          # never mounted.
          "backup" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "reserved" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              refreservation = "20G";
            };
          };
        };
      };
    };
  };
}
