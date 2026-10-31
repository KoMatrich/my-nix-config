# NixOS's built-in iptables-based firewall (enabled by default).
# Add ports here as new services need them, instead of editing configuration.nix.
{ config, pkgs, ... }:

{
  networking.firewall = {
    enable = true;

    # TCP ports open to anything that can reach this host.
    allowedTCPPorts = [ 5174 3000 ];

    # allowedUDPPorts = [ ];

    # micro-ROS agent (docker, --net=host) on UDP 8888, reachable only from
    # the XIAO ESP32-S3 vehicles (~/Repos/ros-test). Their addresses are DHCP
    # leases: if one changes, update it here (or reserve it in the router).
    # extraCommands, not extraInputRules: the backend is iptables (not
    # nftables), and extraInputRules only exists for nftables.
    extraCommands = ''
      for vehicle in \
        192.168.11.112 \
        192.168.1.54 \
        192.168.1.26; do
        iptables -A nixos-fw -p udp -s "$vehicle" --dport 8888 -j nixos-fw-accept
      done
    '';

    # Log packets refused by the firewall (kernel ring buffer / journal),
    # so you can see what's being blocked:
    #   journalctl -k -g "refused" -f
    # or:
    #   dmesg -w | grep -i refused
    logRefusedPackets = true;
  };
}
