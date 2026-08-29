# ZeroTier: peer-to-peer overlay network, joined at boot.
#
# The node's identity (and therefore its ZeroTier address) lives in
# /var/lib/zerotier-one. Root is rolled back on every boot (see
# apps/impermanence.nix), so that directory MUST be persisted - otherwise the
# node comes up with a fresh identity after every reboot and has to be
# re-authorized in ZeroTier Central each time.

{ config, pkgs, ... }:

{
  services.zerotierone = {
    enable = true;
    # BLACK-BOX joins on startup. Networks are only ever joined here, never
    # left: to leave one, drop it from this list AND run
    # `sudo zerotier-cli leave <network-id>`.
    joinNetworks = [
      "272f5eae1695d6e4"
    ];
  };

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
