# NixOS's built-in nftables-based firewall (enabled by default).
# Add ports here as new services need them, instead of editing configuration.nix.
{ config, pkgs, ... }:

{
  networking.firewall = {
    enable = true;

    # TCP ports open to anything that can reach this host.
    allowedTCPPorts = [ 5174 3000 ];

    # allowedUDPPorts = [ ];

    # Log packets refused by the firewall (kernel ring buffer / journal),
    # so you can see what's being blocked:
    #   journalctl -k -g "refused" -f
    # or:
    #   dmesg -w | grep -i refused
    logRefusedPackets = true;
  };
}
