{ config, lib, pkgs, ... }:
{
  services.tailscale.enable = true;

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/tailscale"
    ];
  };
}
