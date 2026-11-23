# Tailscale Password SSH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable password-authenticated OpenSSH for the existing `komatrich` account over Tailscale only, with stable host keys after reboot.

**Architecture:** Configure standard OpenSSH alongside Tailscale, keep its global firewall opening disabled, and add TCP/22 to the existing `tailscale0` rules. Persist the generated host keypairs with impermanence.

**Tech Stack:** NixOS modules, OpenSSH, NixOS firewall, impermanence, `nh`.

**Spec:** `docs/superpowers/specs/2026-11-23-tailscale-password-ssh-design.md`

## Global Constraints

- Use Linux account-password authentication, not Tailscale SSH.
- Expose TCP/22 only on `tailscale0`; do not open it on LAN or ZeroTier.
- Explicitly enable `settings.PasswordAuthentication` and set `openFirewall = false`.
- Preserve the default `PermitRootLogin = "prohibit-password"` behavior.
- Do not change unrelated SSH settings or perform a live system switch.
- Validation is evaluation plus `nh os build`; no test suite is configured.

## Review Focus

- Empty persistent dataset at first activation: Task 1 checks the key persistence declarations and builds the activation configuration.
- LAN or ZeroTier peer attempting TCP/22: Task 1 checks that only `tailscale0` gains the port and global SSH firewall opening stays disabled.
- Host-key mismatch after reboot: Task 1 checks the four default private/public key paths.
- Password login disabled by a changed default: Task 1 explicitly asserts the effective value is `true`.
- Tailscale SSH configured instead of OpenSSH: Task 1 checks `services.openssh.enable` and leaves Tailscale SSH settings untouched.

---

### Task 1: Configure and validate tailnet-only password SSH

**Files:**
- Modify: `apps/tailscale.nix`
- Modify: `system/firewall.nix`
- Modify: `apps/impermanence.nix`

**Interfaces:**
- Consumes: the existing Tailscale service, interface-scoped firewall rules, and impermanence file list.
- Produces: enabled OpenSSH, tailnet-only TCP/22 access, and persistent RSA/Ed25519 host keypairs.

- [ ] **Step 1: Capture the failing pre-change state**

Run:

```bash
nix eval --json .#nixosConfigurations.BLACK-BOX.config.services.openssh.enable
nix eval --json .#nixosConfigurations.BLACK-BOX.config.environment.persistence.'"'"/persist"'"'.files
nix eval --json .#nixosConfigurations.BLACK-BOX.config.networking.firewall.interfaces.'"'tailscale0'"'.allowedTCPPorts
```

Expected: `false`; only an `/etc/machine-id` file entry (Nix normalizes persistence strings to attribute sets); and `[3000,3773,5174]` (Nix sorts the ports). The desired SSH, key-persistence, and port assertions therefore fail before implementation.

- [ ] **Step 2: Configure OpenSSH in `apps/tailscale.nix`**

Enable `services.openssh`, set `openFirewall = false`, and set `settings.PasswordAuthentication = true`. Leave Tailscale, root-login behavior, keyboard-interactive authentication, and all other SSH settings unchanged.

- [ ] **Step 3: Scope TCP/22 to Tailscale in `system/firewall.nix`**

Add `22` to `networking.firewall.interfaces."tailscale0".allowedTCPPorts` and update the adjacent comment to mention SSH. Do not add it globally or to `zt+`.

- [ ] **Step 4: Persist host keys in `apps/impermanence.nix`**

Add `/etc/ssh/ssh_host_rsa_key`, `/etc/ssh/ssh_host_rsa_key.pub`, `/etc/ssh/ssh_host_ed25519_key`, and `/etc/ssh/ssh_host_ed25519_key.pub` to `environment.persistence."/persist".files`. Do not persist the whole directory.

- [ ] **Step 5: Check effective settings and firewall scoping**

Run:

```bash
nix eval --json .#nixosConfigurations.BLACK-BOX.config.services.openssh.enable
nix eval --json .#nixosConfigurations.BLACK-BOX.config.services.openssh.openFirewall
nix eval --json .#nixosConfigurations.BLACK-BOX.config.services.openssh.settings.PasswordAuthentication
nix eval --json .#nixosConfigurations.BLACK-BOX.config.services.openssh.settings.PermitRootLogin
nix eval --json .#nixosConfigurations.BLACK-BOX.config.environment.persistence.'"'"/persist"'"'.files
nix eval --json .#nixosConfigurations.BLACK-BOX.config.networking.firewall.interfaces.'"'tailscale0'"'.allowedTCPPorts
nix eval --json .#nixosConfigurations.BLACK-BOX.config.networking.firewall.interfaces.'"'zt+'"'.allowedTCPPorts
```

Expected, in order: `true`; `false`; `true`; `"prohibit-password"`; normalized file entries for `/etc/machine-id` plus the four key paths; `[22,3000,3773,5174]`; `[3000,5174]`.

- [ ] **Step 6: Build without switching**

Run: `nh os build`

Expected: the complete system closure and activation scripts build successfully without changing the running system.

- [ ] **Step 7: Review the final diff**

Run: `git diff --check && git diff -- apps/tailscale.nix system/firewall.nix apps/impermanence.nix`

Expected: no whitespace errors and only the approved configuration/comment changes. Do not commit unless separately requested.
