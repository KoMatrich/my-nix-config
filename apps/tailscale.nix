{ config, lib, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
    # UDP 41641 (WireGuard): lets peers reach us directly instead of relying
    # on NAT hole punching or falling back to DERP relays.
    openFirewall = true;
  };

  services.openssh = {
    enable = true;
    # Linux password login over the tailnet. system/firewall.nix opens TCP/22
    # on tailscale0 only, so do not open sshd's global firewall rule.
    openFirewall = false;
    settings.PasswordAuthentication = true;
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/tailscale"
    ];
  };
}
