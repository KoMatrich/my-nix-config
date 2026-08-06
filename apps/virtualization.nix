{ config, lib, pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    # Socket-activated instead: dockerd starts on the first `docker` command
    # (~2s once), rather than costing 2.1s on every boot.
    enableOnBoot = false;
  };

  environment.systemPackages = with pkgs; [
    docker-compose
    distrobox
  ];
}
