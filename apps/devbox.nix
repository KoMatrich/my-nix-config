# devbox: a throwaway, FHS (Debian) container for untrusted work.
#
# Goals: run npm/pnpm installs, builds and tests, and Claude Code with
# --dangerously-skip-permissions, without giving any of it access to the host.
# Debian userland, so prebuilt binaries (npm postinstall downloads, pip wheels,
# Electron, Playwright...) just work, with none of NixOS' dynamic-linking pain.
#
#   cd ~/Repos/foo && devbox            # bash in the sandbox, project at /work/foo
#   devbox npm ci && devbox npm test    # one-off commands
#   yolo                                # claude --dangerously-skip-permissions inside
#   devbox -p 5173 npm run dev          # dev server on http://127.0.0.1:5173
#   devbox --offline npm test           # no network at all
#
# What the sandbox can touch (full write-up: docs/DEVBOX.md):
#  - ONLY the current git repo (or $PWD), mounted read-write at /work/<name>.
#    Nothing else from $HOME: no ~/.ssh, ~/.config/gh, browser profiles,
#    ~/.npmrc tokens, other projects. Refuses to run with $HOME or a parent of
#    it as the project.
#  - Files that the HOST later executes on its own are mounted read-only, so
#    a poisoned package can't use them to break out: .git/config (fsmonitor,
#    filter drivers), .git/hooks + core.hooksPath, .envrc, flake.nix/lock,
#    shell.nix, .direnv (nix-direnv's cached shell, sourced on every cd).
#    Anything else the host might run later (Makefile, scripts, other .nix
#    files, .vscode) is reported after exit if it changed.
#  - Its own home: the podman volume `devbox-home`, shared by all projects
#    (Claude login, npm/pnpm caches). `podman volume rm devbox-home` resets it.
#  - Network: internet + LAN, but not the host's own services (pasta
#    --map-guest-addr none; host loopback is never mapped). --offline cuts it.
#  - Rootless Podman, a non-root user inside (no sudo), all capabilities
#    dropped, no-new-privileges. The kernel is shared with the host: this
#    is not a VM boundary (see docs/DEVBOX.md for the microVM upgrade path).
{ config, lib, pkgs, ... }:
let
  cfg = config.local.devbox;

  containerfileText = ''
    # node:24 full image = Debian trixie + buildpack-deps: git, curl, gcc,
    # make, python3 already included.
    FROM docker.io/library/node:24-trixie
    RUN apt-get update \
     && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          ripgrep fd-find jq less nano unzip zip pkg-config libssl-dev \
          python3-venv python3-pip ${lib.concatStringsSep " " cfg.extraPackages} \
     && rm -rf /var/lib/apt/lists/*
    # Claude Code and pnpm in the image, so `devbox --rebuild` is the one
    # update path (the auto-updater can't write /usr/local as `node` anyway).
    RUN npm install -g @anthropic-ai/claude-code pnpm && npm cache clean --force
    ENV DISABLE_AUTOUPDATER=1 \
        NPM_CONFIG_PREFIX=/home/node/.npm-global \
        PATH=/home/node/.npm-global/bin:/home/node/.local/bin:$PATH
    USER node
    WORKDIR /home/node
  '';
  containerfile = pkgs.writeTextDir "Containerfile" containerfileText;
  # New tag whenever the Containerfile changes -> rebuilt on next use.
  image = "localhost/devbox:${lib.substring 0 12 (builtins.hashString "sha256" containerfileText)}";

  devbox = pkgs.writeShellApplication {
    name = "devbox";
    runtimeInputs = [ config.virtualisation.podman.package pkgs.git pkgs.coreutils pkgs.findutils pkgs.diffutils ];
    text = ''
      usage() {
        cat <<'EOF'
      devbox [options] [command...]   Run command (default: bash) in a sandbox
                                      that only sees the current project.
        -p, --port N    publish port N on 127.0.0.1:N (repeatable)
        --offline       no network at all
        --rebuild       re-pull the base image and rebuild (updates Claude Code)
        -h, --help      this help
      Docs: /etc/nixos/docs/DEVBOX.md
      EOF
      }
      die() { printf 'devbox: %s\n' "$*" >&2; exit 1; }

      image=${lib.escapeShellArg image}
      offline=0 rebuild=0 ports=()
      while [ $# -gt 0 ]; do
        case $1 in
          -p|--port) [ $# -ge 2 ] || die "$1 needs a port"; ports+=("$2"); shift 2 ;;
          --offline) offline=1; shift ;;
          --rebuild) rebuild=1; shift ;;
          -h|--help) usage; exit 0 ;;
          --) shift; break ;;
          *) break ;;
        esac
      done

      if [ "$rebuild" = 1 ] || ! podman image exists "$image"; then
        echo "devbox: building $image (first run takes a few minutes)" >&2
        nocache=()
        [ "$rebuild" = 1 ] && nocache=(--no-cache)
        podman build --pull=always "''${nocache[@]}" -t "$image" ${containerfile}
        if [ "$rebuild" = 1 ] && [ $# -eq 0 ]; then exit 0; fi
      fi

      here=$(pwd -P)
      project=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$here")
      project=$(realpath "$project")
      home=$(realpath "$HOME")
      # $HOME itself or any parent of it would expose every secret in it.
      case "$home/" in "$project"/*) die "refusing to expose $project (contains your home); cd into a project" ;; esac
      [ "$project" = / ] && die "refusing to expose /"

      name=$(basename "$project")
      work="/work/$name"
      rel=''${here#"$project"}

      args=(
        --rm --init --interactive
        --hostname devbox
        "--userns=keep-id:uid=1000,gid=1000" --user 1000:1000
        --cap-drop=all --security-opt=no-new-privileges
        --pids-limit=4096
        --label devbox=1
        -v devbox-home:/home/node
        -v "$project:$work"
        -w "$work$rel"
        -e HOME=/home/node
        # The repo's owner uid can differ from the container user's (e.g. a
        # checkout made by root); git would then refuse to work in it.
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e "GIT_CONFIG_VALUE_0=*"
      )
      [ -t 0 ] && [ -t 1 ] && args+=(--tty)

      # Git identity for commits made inside; no credentials, so no pushes.
      for v in name email; do
        val=$(git config --global "user.$v" 2>/dev/null || true)
        [ -n "$val" ] || continue
        up=''${v^^}
        args+=(-e "GIT_AUTHOR_$up=$val" -e "GIT_COMMITTER_$up=$val")
      done

      # Host-executed files: read-only inside.
      ro() { [ -e "$project/$1" ] && args+=(-v "$project/$1:$work/$1:ro"); return 0; }
      for f in .envrc flake.nix flake.lock shell.nix default.nix devenv.nix devenv.yaml .direnv; do ro "$f"; done
      if [ -d "$project/.git" ]; then
        mkdir -p "$project/.git/hooks"
        while IFS= read -r -d "" p; do ro "''${p#"$project"/}"; done < <(
          find "$project/.git" -maxdepth 3 \
            \( -path "$project/.git/objects" -o -path "$project/.git/refs" -o -path "$project/.git/logs" \) -prune \
            -o \( -name config -o -name config.worktree -o -name hooks \) -print0)
        hp=$(git -C "$project" config --get core.hooksPath 2>/dev/null || true)
        case $hp in
          "") ;;
          /*) case $hp in "$project"/*) ro "''${hp#"$project"/}" ;; esac ;;
          *) ro "$hp" ;;
        esac
      fi

      if [ "$offline" = 1 ]; then
        args+=(--network=none)
      else
        args+=("--network=pasta:--map-guest-addr,none")
        for p in "''${ports[@]}"; do args+=(-p "127.0.0.1:$p:$p"); done
      fi

      # Snapshot the files the host would run later, to report changes on exit.
      watched() {
        git -C "$project" ls-files -co --exclude-standard -z 2>/dev/null |
          grep -zE '(^|/)(Makefile|justfile|Justfile|Taskfile\.ya?ml|package\.json|[^/]*\.(nix|sh|bash|zsh|ps1)|\.envrc[^/]*|\.vscode/[^/]+|\.github/workflows/[^/]+|\.pre-commit-config\.yaml|\.husky/[^/]+)$' |
          (cd "$project" && xargs -0r sha256sum) || true
      }
      before=$(watched)

      [ $# -eq 0 ] && set -- bash
      status=0
      podman run "''${args[@]}" "$image" "$@" || status=$?

      changed=$(diff <(printf '%s\n' "$before") <(watched) | sed -n 's/^> [0-9a-f]*  /  /p' || true)
      if [ -n "$changed" ]; then
        printf '\n\033[1;33mdevbox: files the host may execute changed — review before running them outside:\033[0m\n%s\n' "$changed" >&2
      fi
      exit "$status"
    '';
  };
in
{
  options.local.devbox.extraPackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "libgtk-3-0" "xvfb" ];
    description = "Extra Debian packages baked into the devbox image (it is rebuilt automatically when this changes).";
  };

  config = {
    # Rootless by default, daemonless, and --userns=keep-id makes files the
    # sandbox writes in the project owned by you, not a subuid. Lives next to
    # rootless Docker (apps/virtualization.nix); the two stores are separate.
    # Storage: ~/.local/share/containers, on the persisted /home dataset.
    virtualisation.podman.enable = true;

    environment.systemPackages = [
      devbox
      # Claude Code's built-in Bash sandbox (/sandbox, `sandbox.enabled`) on
      # Linux needs these two on PATH. That is the lighter option for normal,
      # permission-prompted sessions on the host; devbox is for YOLO mode.
      pkgs.bubblewrap
      pkgs.socat
    ];
  };
}
