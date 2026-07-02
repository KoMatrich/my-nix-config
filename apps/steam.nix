{ config, lib, pkgs, ... }:
{
  # Game library lives on the big/slow SSD (zstorage/games -> /games).
  # One-time setup after install: Steam -> Settings -> Storage -> Add Drive
  # -> /games (the choice is stored in ~/.steam, which is persisted).
  systemd.tmpfiles.rules = [
    "z /games 0775 komatrich users -"
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };
}
