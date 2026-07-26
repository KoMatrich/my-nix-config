# Persistent nix dev shells + stale-project cleanup.
#
# Problem: `nix develop` creates no GC roots, and `nh clean` additionally
# deletes direnv GC roots older than --keep-since. Dev shells died within
# 7 days and could not be re-entered offline.
#
# Design:
#  - nix-direnv caches each dev shell in <project>/.direnv and registers GC
#    roots (shell profile + flake inputs). It refreshes the roots' symlink
#    mtimes on EVERY load, so symlink mtime == last time the shell was used.
#  - nh clean gets --no-direnv (system/shell.nix); the devshell-cleanup
#    timer below is instead the sole authority: it deletes .direnv dirs
#    unused for 30 days, and the next GC reclaims the closure.
#  - node-modules-cleanup deletes node_modules in npm projects with no file
#    activity for 60 days (regenerable with npm/pnpm install).
#
# Per-project onboarding: `cd project && mkenvrc` (once). See `cheat`.
{ config, lib, pkgs, ... }:
let
  homeDir = "/home/komatrich";
  shellMaxAgeDays = 30;
  nodeModulesMaxAgeDays = 60;

  devshellCleanup = pkgs.writeShellScript "devshell-cleanup" ''
    set -euo pipefail
    cutoff=$(date -d "${toString shellMaxAgeDays} days ago" '+%Y-%m-%d %H:%M:%S')
    echo "removing dev shell caches unused since: $cutoff"
    # Hidden dirs (except .direnv itself) are pruned: app data like
    # ~/.vscode or ~/.local must never be touched, and projects live in
    # visible paths anyway.
    find ${homeDir} \
        \( -name node_modules -o \( -name '.*' ! -name .direnv \) \) -prune \
        -o -type d -name .direnv -prune -print0 |
    while IFS= read -r -d ''' dir; do
      case $dir in ${homeDir}/*) ;; *) continue ;; esac
      # Only touch dirs that actually have nix-direnv's layout.
      find "$dir" -maxdepth 1 \( -name 'flake-profile*' -o -name 'nix-profile*' \) \
        -print -quit | grep -q . || continue
      # nix-direnv touch -h's these symlinks on every load; anything newer
      # than the cutoff means the shell is still in use. find without -L
      # tests the symlink itself, matching touch -h.
      if find "$dir" -maxdepth 2 \
           \( -name 'flake-profile*' -o -name 'nix-profile*' -o -path '*/flake-inputs/*' \) \
           -newermt "$cutoff" -print -quit | grep -q .; then
        continue
      fi
      echo "stale, deleting: $dir"
      rm -rf -- "$dir"
    done
  '';

  nodeModulesCleanup = pkgs.writeShellScript "node-modules-cleanup" ''
    set -euo pipefail
    cutoff=$(date -d "${toString nodeModulesMaxAgeDays} days ago" '+%Y-%m-%d %H:%M:%S')
    echo "removing node_modules of projects inactive since: $cutoff"
    # All hidden dirs are pruned: node_modules under e.g. ~/.vscode
    # (installed extensions), ~/.local/share/containers (image layers!)
    # or .output/.nuxt build dirs belong to apps, not to projects.
    find ${homeDir} \
        -name '.*' -prune \
        -o -type d -name node_modules -prune -print0 |
    while IFS= read -r -d ''' nm; do
      case $nm in ${homeDir}/*) ;; *) continue ;; esac
      proj=$(dirname "$nm")
      [ -f "$proj/package.json" ] || continue   # only real npm projects
      # Active if ANY file outside generated dirs changed in the window;
      # -quit short-circuits on the first hit, so this stays cheap.
      if find "$proj" \
           \( -name node_modules -o -name '.*' -o -name dist -o -name build \) -prune \
           -o -type f -newermt "$cutoff" -print -quit | grep -q .; then
        continue
      fi
      size=$(du -sh "$nm" 2>/dev/null | cut -f1 || echo '?')
      echo "stale, deleting: $nm ($size)"
      rm -rf -- "$nm"
    done
  '';

  mkService = desc: script: {
    Unit.Description = desc;
    Service = {
      Type = "oneshot";
      ExecStart = "${script}";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  mkTimer = desc: {
    Unit.Description = desc;
    Timer = {
      OnCalendar = "weekly";
      Persistent = true; # stamps live in ~/.local/share/systemd/timers (persisted)
      RandomizedDelaySec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
  };
in
{
  # Keep the .drv chain and build-time deps of everything rooted, so a shell
  # can be re-evaluated/rebuilt offline after e.g. a flake.nix tweak.
  # Costs some extra store space; GC honours both.
  nix.settings = {
    keep-outputs = true;
    keep-derivations = true;
  };

  environment.systemPackages = [
    # List every cached dev shell with last-used age and closure size.
    (pkgs.writeShellScriptBin "devshells" ''
      now=$(date +%s)
      find ${homeDir} \( -name node_modules -o \( -name '.*' ! -name .direnv \) \) -prune \
          -o -type d -name .direnv -prune -print0 |
      while IFS= read -r -d ''' dir; do
        profile=$(find "$dir" -maxdepth 1 \( -name 'flake-profile*' -o -name 'nix-profile*' \) \
                    ! -name '*.rc' -print -quit)
        [ -n "$profile" ] || continue
        last=$(stat -c %Y "$profile")   # stat without -L = the symlink itself
        size=$(nix path-info -Sh "$(readlink -f "$profile")" 2>/dev/null | awk '{print $NF}')
        printf '%4d days ago  %8s  %s\n' $(( (now - last) / 86400 )) "''${size:-?}" "''${dir%/.direnv}"
      done | sort -rn
    '')
    # Bootstrap direnv in the current project.
    (pkgs.writeShellScriptBin "mkenvrc" ''
      set -e
      [ -e .envrc ] && { echo ".envrc already exists" >&2; exit 1; }
      if [ -f flake.nix ]; then echo "use flake" > .envrc
      elif [ -f shell.nix ] || [ -f default.nix ]; then echo "use nix" > .envrc
      else echo "use flake" > .envrc; echo "note: no flake.nix/shell.nix here yet" >&2; fi
      direnv allow
    '')
    # Guided wizard: scaffold flake.nix for a dev shell, then create .envrc if needed.
    (pkgs.writeShellScriptBin "mkflake" ''
      set -euo pipefail

      if [ -f flake.nix ]; then
        printf 'flake.nix already exists\n' >&2; exit 1
      fi

      default_name=$(basename "$PWD")
      printf 'Project name [%s]: ' "$default_name"
      read -r proj_name
      proj_name=''${proj_name:-$default_name}

      printf '\nTech stack:\n'
      printf '  1) Rust\n  2) Go\n  3) Python 3\n  4) Node.js / TypeScript\n'
      printf '  5) Java\n  6) C / C++\n  7) Generic (no language preset)\n'
      printf 'Choice [7]: '
      read -r choice
      choice=''${choice:-7}

      case "$choice" in
        1) lang_pkgs="rustc cargo rust-analyzer clippy rustfmt" ;;
        2) lang_pkgs="go gopls" ;;
        3) lang_pkgs="python3 python3Packages.pip" ;;
        4) lang_pkgs="nodejs_22 typescript nodePackages.typescript-language-server" ;;
        5) lang_pkgs="jdk17 gradle" ;;
        6) lang_pkgs="gcc gnumake cmake pkg-config" ;;
        *) lang_pkgs="" ;;
      esac

      printf 'Extra packages (space-separated nix attrs, enter to skip): '
      read -r extra_pkgs

      all_pkgs=$(printf '%s\n%s\n' "$lang_pkgs" "$extra_pkgs" \
        | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort -u)

      {
        echo '{'
        echo "  description = \"$proj_name dev shell\";"
        echo ""
        echo '  inputs = {'
        echo '    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";'
        echo '    flake-utils.url = "github:numtide/flake-utils";'
        echo '  };'
        echo ""
        echo '  outputs = { self, nixpkgs, flake-utils }:'
        echo '    flake-utils.lib.eachDefaultSystem (system:'
        echo '      let pkgs = nixpkgs.legacyPackages.''${system};'
        echo '      in {'
        echo '        devShells.default = pkgs.mkShell {'
        echo '          packages = with pkgs; ['
        if [ -n "$all_pkgs" ]; then
          printf '%s\n' "$all_pkgs" | sed 's/^/            /'
        else
          echo '            # add packages here, e.g. git curl jq'
        fi
        echo '          ];'
        echo '        };'
        echo '      });'
        echo '}'
      } > flake.nix

      printf 'Created flake.nix\n'

      if [ ! -e .envrc ]; then
        echo 'use flake' > .envrc
        direnv allow
        printf 'Created .envrc + direnv allow\n'
      else
        printf '.envrc already exists, not modified\n'
      fi

      printf "\nDone. Run 'direnv reload' or re-enter the directory to build the shell.\n"
      printf "Edit flake.nix to add/remove packages, then run 'direnv reload'.\n"
    '')
  ];

  home-manager.users.komatrich = {
    # Caches dev shell envs in .direnv/ and creates GC roots -> instant,
    # offline-capable, reboot/GC-proof shells. (programs.direnv.enable
    # itself lives in home.nix.)
    programs.direnv.nix-direnv.enable = true;

    systemd.user.services.devshell-cleanup =
      mkService "Remove dev shell caches unused for ${toString shellMaxAgeDays} days" devshellCleanup;
    systemd.user.timers.devshell-cleanup =
      mkTimer "Weekly stale dev shell cleanup";

    systemd.user.services.node-modules-cleanup =
      mkService "Remove node_modules of projects inactive for ${toString nodeModulesMaxAgeDays} days" nodeModulesCleanup;
    systemd.user.timers.node-modules-cleanup =
      mkTimer "Weekly stale node_modules cleanup";
  };
}
