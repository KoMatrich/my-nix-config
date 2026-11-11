# ClankerJail

A sandbox where Claude Code runs with **no permission prompts** (T3 Code's
"Full access" / `--dangerously-skip-permissions`) and can install any package
it needs, without being able to touch the rest of the machine.

Module: `apps/clanker-jail/` (image in `apps/clanker-jail/image/`).
Command: `clanker`.

## What it is

```
 host (komatrich)                           clankerjail container (rootless Docker)
 ─────────────────                          ─────────────────────────────────────
 T3 Code app / browser ── 127.0.0.1:3780 ──▶ t3 serve :3773 ──▶ claude (bypass mode)
 ~/ClankerJail ───────────── bind mount ───▶ /work         (the only shared path)
 docker volume clankerjail-home ───────────▶ /root         (login, t3 threads, tools)
```

- **Rootless Docker** (`apps/virtualization.nix`): root inside the container is
  your own unprivileged user outside. No sudo, no docker socket, no GPU, no
  display inside. Even a container escape lands as `komatrich`, not root.
- **Mutable Debian trixie** with a dev baseline (git, gh, build-essential,
  python, node, ripgrep, ...). The agent is root there and is told (via
  `/root/.claude/CLAUDE.md`) to `apt-get`/`pip`/`npm`/`cargo install` freely.
- **Claude Code and T3 Code live in the home volume**, installed by the
  container on first start with their official installers. They update
  themselves and survive `clanker reset` and image rebuilds.
- **Limits**: 16 GB RAM and 8192 processes (`apps/clanker-jail/default.nix`),
  so a runaway build gets OOM-killed inside the jail instead of freezing the
  desktop.

## First run

```sh
rebuild
clanker            # builds the image (a few minutes), starts the jail
clanker logs       # watch Claude Code + T3 Code install; Ctrl+C when the server is up
clanker shell      # then, inside:  claude   → /login (opens a link you paste back)
                   #                gh auth login   (optional, see "GitHub" below)
clanker pair       # prints a one-time link
```

Open the link in a browser, or in the T3 Code desktop app use
**Settings → Environments → Add environment** and paste it. The jail then
shows up as its own environment next to your normal local one; projects go
under `/work/...`. New threads default to **Full access** in T3 Code.

For plain CLI use there is `clanker claude`, which runs Claude Code in `/work`
with permissions skipped.

## Giving it a project

The agent only sees `~/ClankerJail`. Clone or copy projects there:

```sh
git clone git@github.com:me/thing ~/ClankerJail/thing
```

A symlink from elsewhere in your home does **not** work (the target is not
mounted), which is the point. Files the agent creates there are owned by you
on the host.

## Lifecycle

| Command | Container | apt installs | `/root` (login, threads) | `~/ClankerJail` |
|---|---|---|---|---|
| `clanker stop` / `up` | stopped / started | kept | kept | kept |
| `clanker reset` | recreated | **lost** | kept | kept |
| `clanker rebuild` | new image + recreated | **lost** | kept | kept |
| `clanker nuke` | deleted with image | **lost** | **lost** | kept |

The container restarts with the rootless Docker daemon at login until you
`clanker stop` it. If you edit `apps/clanker-jail/image/` and `rebuild`, the
next `clanker` says so; run `clanker reset` to move to the new image.

## What it does NOT isolate

- **Network.** It has full outbound access: the internet (needed for the API
  and installs) but also your LAN, ZeroTier and Tailscale networks. Your
  host's own `127.0.0.1` services are not reachable (rootless Docker default).
- **Credentials you hand it.** Whatever you log into inside the jail (Claude,
  `gh`, SSH keys you copy in) is usable by the agent. Prefer a fine-grained
  GitHub token limited to the repos it works on over your full `gh` login.
- **`~/ClankerJail` itself.** It can delete or rewrite anything there. The
  directory is on `zroot/safe/home`, so sanoid snapshots (every 15 min) are
  the undo button: `ls /home/.zfs/snapshot/` or see [RECOVERY.md](RECOVERY.md).
- **Kernel.** It is a container, not a VM: it shares the host kernel. For
  hostile code (rather than an over-eager agent) use a VM.

## GitHub

Inside the jail, `gh auth login` with a fine-grained personal access token
scoped to the repositories under `~/ClankerJail` lets the agent push branches
and open pull requests without access to the rest of your account.
