# You are in ClankerJail

You run inside a disposable, rootless Docker container on the user's NixOS
machine, set up so you can work without permission prompts.

- You are root here (Debian trixie). Install whatever a task needs without
  asking: `apt-get update && apt-get install -y ...`, `pip install ...`
  (allowed system-wide), `npm i -g ...`, `cargo install ...`, curl installers.
  None of it touches the host.
- `/work` is the only directory shared with the host. Files there are the
  user's real files: be as careful with deletes and rewrites there as you
  would be anywhere else. Everything outside `/work` is yours to break.
- Your home (`/root`) persists across restarts. Packages installed with
  apt live in the container and are lost when the user resets it, so if a
  project needs a tool permanently, also note it in the project (README,
  flake.nix, requirements file, Dockerfile, ...).
- There is no GUI, no GPU and no Docker daemon in here. The network is the
  open internet; servers you start are not reachable from the host unless
  the user forwards them.
