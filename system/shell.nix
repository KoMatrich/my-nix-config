# Day-to-day tooling: nh (nix helper) and shell aliases for the common
# operations. Full command reference lives in docs/CHEATSHEET.md.
{ config, lib, pkgs, ... }:
{
  # nh = modern wrapper around nixos-rebuild / nix-collect-garbage with
  # diffs between generations and nicer output. clean.enable replaces the
  # old nix.gc setup (do not enable both).
  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  environment.shellAliases = {
    # System management
    rebuild = "nh os switch";
    update = "nh os switch --update";
    gc = "nh clean all --keep-since 7d --keep 5";

    # ZFS health & snapshots
    zhealth = "zpool status -x";
    zsnaps = "zfs list -t snapshot -o name,used,creation -s creation";
    zbackup-status = "systemctl list-timers sanoid.timer 'syncoid-*' --all && zfs list -r -t snapshot -o name,creation zstorage/backup | tail -n 6";
  };

  environment.systemPackages = [
    # Lists every file on / that is NOT persisted, i.e. everything that will
    # be erased on the next reboot. Run it before rebooting to catch state
    # you forgot to add to apps/impermanence.nix.
    (pkgs.writeShellScriptBin "fsdiff" ''
      zfs diff zroot/local/root@blank "$@" | grep -Ev '/tmp/' | less
    '')
  ];
}
