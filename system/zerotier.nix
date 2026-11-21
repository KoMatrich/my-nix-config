# ZeroTier: peer-to-peer overlay network, joined at boot.
#
# The node's identity (and therefore its ZeroTier address) lives in
# /var/lib/zerotier-one. Root is rolled back on every boot (see
# apps/impermanence.nix), so that directory MUST be persisted - otherwise the
# node comes up with a fresh identity after every reboot and has to be
# re-authorized in ZeroTier Central each time.

{ config, pkgs, ... }:
let
  zerotierPorts = {
    secondary = 36505;
    tertiary = 47204;
  };
in
{
  services.zerotierone = {
    enable = true;
    # BLACK-BOX joins on startup. Networks are only ever joined here, never
    # left: to leave one, drop it from this list AND run
    # `sudo zerotier-cli leave <network-id>`.
    joinNetworks = [
      "272f5eae1695d6e4"
    ];

    # Besides the primary port (9993, opened by the module) ZeroTier listens
    # on a secondary port (derived from the node address) and a tertiary one
    # (randomly picked, used for UPnP/NAT-PMP mapping). Unpinned, the firewall
    # dropped peers and roots reaching them directly over IPv6, so traffic
    # got relayed. Pinned here to the values the node was already using and
    # opened below. Written to /var/lib/zerotier-one/local.conf (an existing
    # hand-edited one is backed up by the module).
    localConf.settings = {
      secondaryPort = zerotierPorts.secondary;
      tertiaryPort = zerotierPorts.tertiary;
    };
  };

  networking.firewall.allowedUDPPorts = [
    zerotierPorts.secondary
    zerotierPorts.tertiary
  ];

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/zerotier-one";
      user = "root";
      group = "root";
      mode = "0700"; # holds identity.secret
    }
  ];

  # Mounting SMB/CIFS shares reachable over the overlay (Nautilus uses gvfs,
  # which needs no kernel helper; this is for `mount -t cifs` from the CLI).
  environment.systemPackages = [ pkgs.cifs-utils ];
}
