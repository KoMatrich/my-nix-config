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

  # Lets this machine's own key log in (T3 Code's "open in VS Code" goes over
  # SSH). Clients try the key first; password login stays as the fallback.
  users.users.${config.local.user}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGN3T82tT0jUoxEEj5I6b1AUtDCMrx+1/w/joNkyF6Y komatrich@Black-Box"
  ];

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/tailscale"
    ];
  };
}
