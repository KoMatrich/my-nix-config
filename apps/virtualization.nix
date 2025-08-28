{ config, lib, pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  environment.systemPackages = with pkgs; [
    pkgs.distrobox
  ];
}
