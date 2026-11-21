{ config, lib, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
    # UDP 41641 (WireGuard): lets peers reach us directly instead of relying
    # on NAT hole punching or falling back to DERP relays.
    openFirewall = true;
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/tailscale"
    ];
  };
}
