{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.gnome-network-displays
  ];
}