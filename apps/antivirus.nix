{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.clamav
  ];

  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;

  # clamd loads ~1 GB of signatures at startup, which cost ~10s of the boot
  # critical path (it is Before=multi-user.target, and drags clamav-freshclam
  # and network-online.target in with it). The module already ships
  # clamav-daemon.socket, so on-demand clients still work; this timer just
  # warms it up once the desktop is already usable.
  # Signature updates are unaffected: clamav-freshclam.timer runs hourly.
  systemd.services.clamav-daemon.wantedBy = lib.mkForce [ ];
  systemd.timers.clamav-daemon = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnBootSec = "2min";
  };
}
