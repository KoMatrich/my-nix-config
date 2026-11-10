# devbox: sandbox for npm, builds and Claude YOLO mode

`devbox` (`apps/devbox.nix`) runs a command in a throwaway rootless Podman
container with a Debian userland that can see **only the current project**.
Use it for anything you don't want to trust with your home directory:
`npm install` of unknown packages, building/running other people's code, and
`claude --dangerously-skip-permissions` (alias `yolo`).

```sh
cd ~/Repos/foo
devbox                    # bash inside, project at /work/foo
devbox npm ci             # one-off command
yolo                      # Claude Code, no permission prompts, inside the box
devbox -p 5173 npm run dev   # dev server reachable at http://127.0.0.1:5173
devbox --offline npm test    # no network at all
devbox --rebuild          # re-pull Debian/Node, update Claude Code and pnpm
```

First run builds the image (a few minutes). In a new box run `claude` once to
log in; the login is kept in the `devbox-home` volume.

## What it protects

| | Inside the box |
|---|---|
| Your files | Only the git repo you are in (or `$PWD`), read-write. No `~/.ssh`, `~/.config/gh`, browser profiles, `~/.npmrc` tokens, other repos, `/etc/nixos`. Refuses to run from `$HOME` itself. |
| Home dir | Its own: podman volume `devbox-home` (Claude login, npm/pnpm caches), shared by all projects. Reset with `podman volume rm devbox-home`. |
| Host-executed files | Read-only: `.git/config` (fsmonitor/filter commands), `.git/hooks` and `core.hooksPath`, `.envrc`, `flake.nix`/`flake.lock`, `shell.nix`, `default.nix`, `.direnv` (nix-direnv's cached shell, sourced on every `cd`). |
| Other files the host may run | After the box exits, devbox lists any changed `Makefile`, `package.json`, `*.nix`, `*.sh`, `.vscode/*`, workflow files etc. Review them before running them on the host. |
| Network | Internet and the LAN. The host's own services are not mapped in (pasta `--map-guest-addr none`, host loopback never mapped). `--offline` removes networking. |
| Privileges | Non-root user (no sudo), all capabilities dropped, `no-new-privileges`, pid limit. Files it writes in the project are owned by you (`--userns=keep-id`). |
| Git | Your name/email are passed in, so commits work. No credentials, so it **cannot push**: push from the host after reviewing. |
| GPU, display, audio, D-Bus, SSH agent, Docker socket | Not available. |

FHS: it is plain Debian trixie with Node 24, gcc, make, python3, so prebuilt
binaries (Playwright, Electron, esbuild, prisma, pip wheels) work without any
nix-ld/patchelf tricks. Extra Debian packages go in
`local.devbox.extraPackages` (the image rebuilds itself on next use).

## What it does not protect

- **The project itself.** Anything inside can read, modify or exfiltrate the
  repo's source and any secrets in it (`.env`!). Keep production secrets out
  of repos you open in the box.
- **The Claude login token** in `devbox-home` (a malicious package in any
  project could steal it). Log out / revoke it if a box was compromised.
- **The kernel.** Containers share the host kernel; a kernel exploit escapes.
  Rootless + no capabilities makes that the main remaining risk, not an easy
  one. For a VM boundary see "Stronger isolation" below.
- **Code you later run on the host.** The box can edit any normal file. A
  changed `package.json` script, `Makefile` or `.nix` file imported by
  `flake.nix` runs on the host the next time *you* run it there. Read the
  exit report and `git diff` first.
- **The LAN.** Something inside can reach other devices on your network.
  Use `--offline` for code you don't trust at all.

## Why this approach

Options looked at (2026-11):

| Option | Isolation | FHS / linking | Setup on this host | Verdict |
|---|---|---|---|---|
| **Rootless Podman + Debian image (devbox)** | Namespaces, own fs view, shared kernel | Native | One module, no daemon, no root | **Chosen**: best balance; starts in ~1 s |
| Rootless Docker (already enabled) | Same | Native | Exists | Works too, but no `keep-id`: files written by the non-root user inside end up owned by a subuid on the host |
| distrobox | **None for files**: mounts your whole `$HOME` by default | Native | Exists | Convenience tool, not a sandbox |
| bubblewrap / firejail | Namespaces; you hand-pick binds | No (NixOS host userland) | Small | Good building block; Claude Code's own `/sandbox` uses bwrap. firejail is setuid with a large attack surface |
| Claude Code built-in sandbox | Bash tool only, writes limited to cwd, network via allowlist proxy; reads most of `$HOME` by default; file tools, hooks, MCP outside it | Host | `bubblewrap`+`socat` (now installed) | Good for normal prompted sessions; not meant for `--dangerously-skip-permissions` |
| NixOS containers / systemd-nspawn | Namespaces, root-managed | NixOS inside | Declarative but root-only, networking setup | Better for long-running services than per-project shells |
| devcontainers (VS Code / `devcontainer` CLI) | Same as the container engine | Native | Needs a `devcontainer.json` per repo | Use with Podman if a repo already ships one; Anthropic publishes a reference devcontainer for Claude Code with an egress firewall |
| microVM (microvm.nix, cloud-hypervisor/qemu) | Separate kernel | NixOS guest (nix-ld) or Debian guest | New flake input, guest config, virtiofs share | Strongest; heavier and slower to iterate |

## Stronger isolation (if you ever need it)

- **Offline by default** for untrusted code: `devbox --offline`.
- **Egress allowlist**: run the box behind a filtering proxy (only
  `registry.npmjs.org`, `api.anthropic.com`, GitHub...) like Anthropic's
  reference devcontainer does with an iptables allowlist.
- **VM boundary with the same image**: Podman can run containers in a
  microVM with `--runtime krun` (libkrun) or under gVisor (`--runtime runsc`),
  keeping the devbox workflow; or move to a microvm.nix guest with a virtiofs
  share of `~/Repos/<project>`.
