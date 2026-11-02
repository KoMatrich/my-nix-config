# NixOS's built-in iptables-based firewall (enabled by default).
# Add ports here as new services need them, instead of editing configuration.nix.
#
# Dev servers (Vite on 5174, Node/Next on 3000, ...) are NOT open on the LAN:
# on public Wi-Fi that would expose them to everyone on the network.
#   - From your own devices over Tailscale/ZeroTier: always open (devPorts).
#   - From the LAN, temporarily: `devport open 3000` (sudo; until the next
#     reboot, rebuild or `devport close 3000`). `devport list` shows them.
#   - Permanently from the LAN: add the port to allowedTCPPorts below.
{ config, lib, pkgs, ... }:
let
  devPorts = [ 3000 5174 ];

  # Inserts/removes ACCEPT rules at the top of NixOS's own nixos-fw chain,
  # tagged with a comment so they can be listed and are never confused with
  # the declarative ones. Both are rebuilt from scratch by firewall.service,
  # which is why these are temporary.
  devport = pkgs.writeShellApplication {
    name = "devport";
    runtimeInputs = [ config.networking.firewall.package pkgs.gnugrep pkgs.coreutils ];
    text = ''
      usage() {
        echo "usage: devport open|close <port> [tcp|udp]   |   devport list" >&2
        exit 2
      }
      [ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

      cmd=''${1:-}
      case "$cmd" in
        list)
          for ipt in iptables ip6tables; do
            "$ipt" -S nixos-fw | grep -- '--comment devport' || true
          done
          exit 0
          ;;
        open|close) ;;
        *) usage ;;
      esac

      port=''${2:-}
      proto=''${3:-tcp}
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || usage
      [[ "$proto" = tcp || "$proto" = udp ]] || usage

      rule=(nixos-fw -p "$proto" --dport "$port" -m comment --comment devport -j nixos-fw-accept)
      for ipt in iptables ip6tables; do
        if [ "$cmd" = open ]; then
          "$ipt" -C "''${rule[@]}" 2>/dev/null || "$ipt" -I "''${rule[@]}"
        else
          while "$ipt" -C "''${rule[@]}" 2>/dev/null; do "$ipt" -D "''${rule[@]}"; done
        fi
      done
      if [ "$cmd" = open ]; then
        echo "devport: $proto/$port open to the LAN until reboot/rebuild (devport close $port $proto)"
      else
        echo "devport: $proto/$port closed"
      fi
    '';
  };
in
{
  environment.systemPackages = [ devport ];

  networking.firewall = {
    enable = true;

    # TCP ports open to anything that can reach this host (LAN included).
    # allowedTCPPorts = [ ];

    # allowedUDPPorts = [ ];

    # Dev server ports, reachable only over the overlay networks, i.e. from
    # your own authorized devices. `zt+` matches every ZeroTier interface.
    interfaces."tailscale0".allowedTCPPorts = devPorts;
    interfaces."zt+".allowedTCPPorts = devPorts;

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
