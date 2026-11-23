# NixOS's built-in iptables-based firewall (enabled by default).
# Add ports here as new services need them, instead of editing configuration.nix.
#
# Dev servers (Vite on 5174, Node/Next on 3000, ...) are NOT open on the LAN:
# on public Wi-Fi that would expose them to everyone on the network.
#   - From your own devices over Tailscale/ZeroTier: always open (devPorts).
#   - From the LAN, temporarily: `devport open 3000` (sudo; until the next
#     reboot, rebuild or `devport close 3000`). `devport list` shows them.
#   - `devport check` lists everything that is listening and whether the LAN
#     can reach it. The devport-watch user service does the asking for you:
#     when a program starts listening on a TCP port that is not open to the LAN,
#     a notification offers "Open until reboot" (polkit, then `devport open`).
#     "Never ask for <program>" is remembered in ~/.local/state/devport/ignore.
#     tailnetOnlyTCPPorts never trigger an offer, and `devport open` refuses them.
#   - Permanently from the LAN: add the port to allowedTCPPorts below.
{ config, lib, pkgs, ... }:
let
  devPorts = [ 3000 5174 ];
  tailnetOnlyTCPPorts = [ 22 3773 ];

  devportHelper = pkgs.writers.writePython3Bin "devport-helper"
    { doCheck = false; }
    (builtins.readFile ./devport.py);

  # Inserts/removes ACCEPT rules at the top of NixOS's own nixos-fw chain,
  # tagged with a comment so they can be listed and are never confused with
  # the declarative ones. Both are rebuilt from scratch by firewall.service,
  # which is why these are temporary.
  devport = pkgs.writeShellApplication {
    name = "devport";
    runtimeInputs = [ config.networking.firewall.package pkgs.iproute2 pkgs.gnugrep pkgs.coreutils ];
    text = ''
      usage() {
        echo "usage: devport open|close <port> [tcp|udp]   |   devport list   |   devport check [--all]" >&2
        exit 2
      }
      # Store path, not the /run/current-system symlink: the NOPASSWD sudo
      # rule for `check` below names it.
      [ "$(id -u)" -eq 0 ] || exec sudo "$(readlink -f "$0")" "$@"

      cmd=''${1:-}
      case "$cmd" in
        list)
          for ipt in iptables ip6tables; do
            "$ipt" -S nixos-fw | grep -- '--comment devport' || true
          done
          exit 0
          ;;
        check)
          exec ${devportHelper}/bin/devport-helper check "''${@:2}"
          ;;
        open|close) ;;
        *) usage ;;
      esac

      port=''${2:-}
      proto=''${3:-tcp}
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || usage
      [[ "$proto" = tcp || "$proto" = udp ]] || usage

      if [ "$cmd" = open ] && [ "$proto" = tcp ]; then
        for protectedPort in ${lib.concatMapStringsSep " " toString tailnetOnlyTCPPorts}; do
          if [ "$port" -eq "$protectedPort" ]; then
            echo "devport: $proto/$port is restricted to tailscale0; refusing to open it on the LAN" >&2
            exit 2
          fi
        done
      fi

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

  # `devport check` only reads (listening sockets + firewall rules), so it
  # needs no password; devport-watch calls it unattended.
  security.sudo.extraRules = [{
    users = [ config.local.user ];
    commands = map (command: { inherit command; options = [ "NOPASSWD" ]; }) [
      "${devport}/bin/devport check"
      "${devport}/bin/devport check *"
    ];
  }];

  systemd.user.services.devport-watch = {
    description = "Ask before leaving a newly listening port blocked by the firewall";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    path = [ pkgs.iproute2 pkgs.libnotify ];
    environment.DEVPORT_BIN = "${devport}/bin/devport";
    environment.DEVPORT_NEVER_OPEN = lib.concatMapStringsSep " " toString tailnetOnlyTCPPorts;
    serviceConfig = {
      ExecStart = "${devportHelper}/bin/devport-helper watch";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  networking.firewall = {
    enable = true;

    # TCP ports open to anything that can reach this host (LAN included).
    # allowedTCPPorts = [ ];

    # allowedUDPPorts = [ ];

    # Dev server ports, reachable only over the overlay networks, i.e. from
    # your own authorized devices. `zt+` matches every ZeroTier interface.
    # SSH (22) accepts Linux password logins over Tailscale only. T3 Code
    # (3773) listens on 0.0.0.0 and drives an agent with shell access: both
    # are reachable over Tailscale only, never the LAN or ZeroTier.
    interfaces."tailscale0".allowedTCPPorts = devPorts ++ tailnetOnlyTCPPorts;
    interfaces."zt+".allowedTCPPorts = devPorts;

    # Ethernet port shared via NetworkManager ("Share to other computers",
    # ipv4.method=shared, 10.42.0.1/24): NM's dnsmasq must be reachable from
    # the device on the cable (a Raspberry Pi) for DHCP and DNS. Scoped to
    # eno1 so nothing is opened on Wi-Fi.
    interfaces."eno1" = {
      allowedUDPPorts = [ 53 67 ];
      allowedTCPPorts = [ 53 ];
    };

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

      # SSDP/UPnP discovery replies (casting, DLNA, screen sharing). We send
      # M-SEARCH to the multicast group 239.255.255.250:1900 and devices answer
      # by unicast from port 1900 to our ephemeral port. conntrack does not tie
      # a unicast answer to a multicast query, so without this they are
      # dropped. Limited to private (RFC 1918) source addresses, so it works
      # on whichever LAN the laptop is on, and to the ephemeral port range
      # (net.ipv4.ip_local_port_range) so "source port 1900" cannot be used to
      # reach arbitrary local UDP services.
      for lan in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
        iptables -A nixos-fw -p udp -s "$lan" --sport 1900 \
          --dport 32768:60999 -j nixos-fw-accept
      done
    '';

    # Log packets refused by the firewall (kernel ring buffer / journal),
    # so you can see what's being blocked:
    #   journalctl -k -g "refused" -f
    # or:
    #   dmesg -w | grep -i refused
    logRefusedPackets = true;
    # Also log refused broadcast/multicast packets (NixOS default: unicast
    # only). LAN discovery (games, casting, SSDP) is broadcast/multicast, and
    # with the default those drops never show up in the log. Noisier; set
    # back to true once nothing needs diagnosing.
    logRefusedUnicastsOnly = false;
  };
}
