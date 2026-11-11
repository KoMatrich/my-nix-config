# ClankerJail: a sandbox where Claude Code (driven from T3 Code) runs with no
# permission prompts and can install whatever it wants, without touching the
# host. Full usage: docs/CLANKERJAIL.md. Day to day it is just `clanker`.
#
# Design:
#  - A rootless Docker container (apps/virtualization.nix), so "root" inside is
#    the unprivileged host user outside: even a container escape lands as
#    komatrich, not root, and there is no docker socket inside to abuse.
#  - Image (./image) is a mutable Debian box: the agent is root there and may
#    apt/pip/npm/cargo install freely. Those installs live in the container's
#    own layer; `clanker reset` throws them away.
#  - Claude Code + T3 Code install themselves into the home volume
#    (`clankerjail-home` -> /root) on first start, together with the Claude
#    login and T3 Code's threads, so they survive resets and self-update.
#  - The ONLY host path the agent can see is the workspace (~/ClankerJail ->
#    /work). Clone/copy projects there to let the agent at them.
#  - T3 Code's server runs inside and is published on 127.0.0.1:${port} only;
#    the host T3 Code app (or a browser) pairs with it via `clanker pair`.
#
# Not isolated: outbound network. The container can reach the internet (it
# must, for the API and package installs) and also the LAN/ZeroTier/Tailscale
# networks the host is on; host loopback services are NOT reachable (rootless
# Docker's default). Persistence: Docker data (~/.local/share/docker) and the
# workspace are both under /home, so impermanence needs nothing.
{ config, lib, pkgs, ... }:
let
  user = config.local.user;
  homeDir = config.users.users.${user}.home;

  workspace = "${homeDir}/ClankerJail";
  port = 3780; # host side, 127.0.0.1 only; 3773 inside the container
  memory = "16g"; # of 32 GB; the container is OOM-killed, not the desktop
  pidsLimit = 8192; # a fork bomb stays inside the jail

  # Rebuilt image <=> changed tag: the tag is a hash of the image directory.
  context = ./image;
  tag = builtins.substring 0 12 (builtins.hashString "sha256" "${context}");

  clanker = pkgs.writeShellApplication {
    name = "clanker";
    runtimeInputs = [ config.virtualisation.docker.package pkgs.jq pkgs.coreutils pkgs.gnused ];
    text = ''
      name=clankerjail
      image=clankerjail:${tag}
      volume=clankerjail-home
      workspace=${lib.escapeShellArg workspace}
      port=${toString port}

      # Always the rootless daemon, even if DOCKER_HOST points elsewhere: the
      # rootful one would make container root real root on the host.
      export DOCKER_HOST="unix://''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"

      say() { printf '\033[1;36mclanker:\033[0m %s\n' "$*"; }
      die() { printf '\033[1;31mclanker:\033[0m %s\n' "$*" >&2; exit 1; }

      exists() { docker container inspect "$name" >/dev/null 2>&1; }
      running() { [ "$(docker container inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ]; }
      need_running() { running || die "not running; start it with: clanker up"; }

      build() {
        say "building image $image (Debian base + tools, a few minutes the first time)"
        docker build --pull -t "$image" ${context}
      }

      create() {
        docker image inspect "$image" >/dev/null 2>&1 || build
        mkdir -p "$workspace"
        say "creating container (workspace: $workspace -> /work)"
        # --init: tini as PID 1 reaps the zombies agents leave behind.
        # --restart unless-stopped: comes back with the rootless daemon at
        # login, until `clanker stop`.
        docker run -d \
          --name "$name" --hostname "$name" \
          --label clankerjail.image="$image" \
          --init --restart unless-stopped \
          --memory ${memory} --pids-limit ${toString pidsLimit} \
          --security-opt no-new-privileges \
          -p "127.0.0.1:$port:3773" \
          -v "$volume:/root" \
          -v "$workspace:/work" \
          -w /work \
          "$image" >/dev/null
      }

      up() {
        if ! exists; then
          create
          say "first start installs Claude Code + T3 Code into the jail; watch it with: clanker logs"
        elif ! running; then
          docker start "$name" >/dev/null
        fi
        have=$(docker container inspect -f '{{index .Config.Labels "clankerjail.image"}}' "$name")
        if [ "$have" != "$image" ]; then
          say "the image changed in /etc/nixos; run 'clanker reset' to switch to it"
          say "(drops apt installs made in the jail; keeps /root and /work)"
        fi
        say "running. T3 Code server: http://127.0.0.1:$port"
        say "connect the T3 Code app to it with: clanker pair"
      }

      wait_server() {
        for _ in $(seq 120); do
          docker exec "$name" curl -fsS -o /dev/null http://127.0.0.1:3773/.well-known/t3/environment 2>/dev/null && return 0
          running || die "the container stopped; see: clanker logs"
          sleep 2
        done
        die "T3 Code server did not come up in 4 minutes; see: clanker logs"
      }

      pair() {
        need_running
        wait_server
        # t3 pair prints the container's own address; only the token is
        # useful from out here, the host reaches the server on 127.0.0.1.
        # -w /root: inside a git worktree t3 would look for a per-worktree
        # server instead.
        token=$(docker exec -w /root "$name" t3 pair --label "host" "$@" | sed -n 's/^Token: //p')
        [ -n "$token" ] || die "t3 pair printed no token"
        url="http://127.0.0.1:$port/pair#token=$token"
        applink="t3code://pair?$(jq -rn --arg u "$url" '"pairingUrl=" + ($u | @uri)')"
        echo
        echo "  Web:      $url"
        echo "  T3 app:   Settings -> Environments -> Add environment, paste the Web URL"
        echo "  App link: $applink"
        echo
        echo "  One-time link. Run 'clanker pair' again for each new device/browser."
      }

      reset() {
        if exists; then
          say "removing the container (apt installs go; /root volume and $workspace stay)"
          docker rm -f "$name" >/dev/null
        fi
        up
      }

      usage() {
        cat <<EOF
      clanker - sandbox for unrestricted Claude Code / T3 Code (docs/CLANKERJAIL.md)

        clanker [up]        create/start the jail (T3 Code server on 127.0.0.1:$port)
        clanker pair        pairing link for the T3 Code app or a browser
        clanker claude ...  Claude Code CLI in /work, permissions skipped
        clanker shell       root shell in the jail (first time: run 'claude' to log in)
        clanker logs        follow the server log
        clanker status      container state, image, sizes
        clanker stop        stop it (stays stopped until 'clanker up')
        clanker reset       recreate the container: drops apt installs, keeps home + /work
        clanker rebuild     rebuild the image from scratch (fresh Debian), then reset
        clanker nuke        delete container, image AND home volume (Claude login, threads)

      Only $workspace is visible to the agent, as /work.
      EOF
      }

      cmd=''${1:-up}
      [ $# -gt 0 ] && shift
      case $cmd in
        up|start) up ;;
        pair) pair "$@" ;;
        shell) need_running; exec docker exec -it -w /work "$name" bash -l ;;
        claude) need_running; exec docker exec -it -w /work "$name" claude --dangerously-skip-permissions "$@" ;;
        logs) exec docker logs -f --tail 100 "$name" ;;
        status)
          if exists; then
            docker ps -a --size --filter "name=^$name$" --format 'table {{.Status}}\t{{.Image}}\t{{.Size}}'
          else
            echo "no container (run: clanker up)"
          fi
          docker system df -v 2>/dev/null | grep -E "^VOLUME NAME|^$volume " || true
          ;;
        stop) docker stop "$name" >/dev/null && say "stopped" ;;
        reset) reset ;;
        rebuild) build; reset ;;
        nuke)
          read -r -p "Delete the jail, its image and its home volume (Claude login, T3 threads)? $workspace is kept. [y/N] " ok
          [ "$ok" = y ] || exit 1
          docker rm -f "$name" >/dev/null 2>&1 || true
          docker volume rm "$volume" >/dev/null 2>&1 || true
          docker image ls -q clankerjail | xargs -r docker image rm -f >/dev/null
          say "gone"
          ;;
        -h|--help|help) usage ;;
        *) usage >&2; exit 1 ;;
      esac
    '';
  };
in
{
  # The jail needs the rootless daemon from apps/virtualization.nix.
  assertions = [{
    assertion = config.virtualisation.docker.rootless.enable;
    message = "apps/clanker-jail needs virtualisation.docker.rootless.enable (apps/virtualization.nix).";
  }];

  environment.systemPackages = [ clanker ];

  # The workspace exists (and is the user's) before the first `clanker up`.
  systemd.tmpfiles.rules = [ "d ${workspace} 0755 ${user} users - -" ];
}
