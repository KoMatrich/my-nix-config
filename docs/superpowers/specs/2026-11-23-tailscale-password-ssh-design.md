# Tailscale Password SSH Design

## Intent

Enable remote SSH login to the existing `komatrich` account over Tailscale using the account password, without exposing SSH to the LAN.

## Goals

- Run standard OpenSSH with password authentication enabled.
- Accept TCP/22 only on `tailscale0`.
- Keep root password login disabled.
- Preserve SSH host identity across reboots despite the ephemeral root filesystem.
- Validate the change with `nh os build`.

## Non-goals

- Do not enable Tailscale SSH, which uses tailnet identity instead of Linux passwords.
- Do not open SSH on LAN, ZeroTier, or other interfaces.
- Do not change unrelated SSH authentication defaults or perform a live system switch.

## Constraints

- Tailscale already opens UDP/41641 through `services.tailscale.openFirewall`.
- `services.openssh.openFirewall` defaults to true and must therefore be disabled explicitly.
- Password hashes already persist under `/persist/passwords`.
- Firewall openings are centralized in `system/firewall.nix`.
- Persistent state outside `/home`, `/nix`, `/games`, and `/persist` belongs in `apps/impermanence.nix`.

## Approaches

1. **Standard OpenSSH plus an interface-scoped firewall rule (selected).** It provides Linux password authentication while restricting exposure to the tailnet and requires no fixed Tailscale address.
2. **Globally open OpenSSH.** Rejected because it unnecessarily exposes TCP/22 to untrusted networks.
3. **Bind OpenSSH to a Tailscale IP.** Rejected because interface-scoped firewalling is simpler and avoids address/startup coupling.
4. **Tailscale SSH.** Rejected because it does not implement the requested Linux account-password login.

## Implementation decisions

- Configure OpenSSH in `apps/tailscale.nix`, colocating it with the remote-access feature.
- Set `services.openssh.enable = true`, `services.openssh.openFirewall = false`, and `services.openssh.settings.PasswordAuthentication = true`.
- Preserve the default `PermitRootLogin = "prohibit-password"`, which denies password login for root.
- Add TCP/22 to the existing `tailscale0`-only allowed ports in `system/firewall.nix`.
- Persist the default RSA and Ed25519 host keys and their public keys in `apps/impermanence.nix`.

The builder should preserve all defaults not explicitly changed above and should not create new abstractions for this small configuration change.
