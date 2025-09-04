{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.clamav
    pkgs.clamtk
  ];

  services.clamav = {
    daemon.enable = true;
    scanner.enable = true;
    updater.enable = true;
  };
}
