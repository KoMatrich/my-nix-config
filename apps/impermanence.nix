{ config, lib, pkgs, ... }:
{
  # https://github.com/nix-community/impermanence
  #
  # The root filesystem is rolled back to a blank snapshot on EVERY boot
  # (see system/zfs.nix). Anything not listed here and not on /home, /nix,
  # /persist or /games is erased. Run `fsdiff` before rebooting to see what
  # would be lost; add missing state here.
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # The system flake itself - without this the config vanishes on reboot!
      # Owned by the user so the config can be edited and pushed without sudo
      # (rebuilding still needs root). Ownership only applies when the
      # directory is first created; on an existing install run once:
      #   su -c 'chown -R komatrich:users /persist/etc/nixos'
      { directory = "/etc/nixos"; user = "komatrich"; group = "users"; mode = "0755"; }
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/clamav"
      "/var/lib/containers"
      "/var/lib/cups"
      "/var/lib/fwupd"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/timers"
      "/var/db/sudo/lectured"
      "/etc/NetworkManager/system-connections"
      # ZFS keyfile for the second pool + user password hashes also live in
      # /persist (zfs/, passwords/) but are plain data, not bind mounts.
    ];
    files = [
      "/etc/machine-id"
    ];
  };
}
