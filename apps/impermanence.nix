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
      "/etc/nixos"
      "/var/log"
      "/var/lib/AccountsService" # GNOME user avatar, language, session choice
      "/var/lib/bluetooth"
      "/var/lib/docker"
      "/var/lib/cups"
      "/var/lib/fwupd"
      "/var/lib/nixos"
      "/var/lib/power-profiles-daemon" # remembered power mode (else resets every boot)
      "/var/lib/systemd/backlight" # screen brightness restored at boot
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/timers"
      "/var/lib/upower"
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
