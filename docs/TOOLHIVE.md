# ToolHive (MCP server manager)

- `toolhive` — Studio UI (`pkgs/toolhive-studio`, repackaged from the upstream `.deb`).
- `thv` — nixpkgs CLI (`pkgs.toolhive`, lags upstream).
- `toolhive-thv` — the `thv` bundled in the UI, version-matched to it. Prefer this one
  for anything that touches the UI's state (`~/.config/toolhive`, secrets, workloads).

## Container runtime

MCP servers run in the **rootless** Docker daemon (`apps/virtualization.nix`). `thv` ignores
`DOCKER_HOST`, so `TOOLHIVE_DOCKER_SOCKET=$XDG_RUNTIME_DIR/docker.sock` is exported in the
session and in the `toolhive`/`toolhive-thv` wrappers. Symptom without it:
`no container runtime available`.

## Secrets

Tokens live in ToolHive's secrets store, never in this repo or the Nix store:

    toolhive-thv secret setup        # once: pick "encrypted", choose a password (kept in the keyring)
    toolhive-thv secret set <name>   # reads the value from stdin

Remote servers reference them with `--remote-forward-headers-secret Authorization=<secret-name>`;
container servers with `--secret <secret-name>,target=ENV_NAME`.

## Updating the UI

Bump `version` and `hash` in `pkgs/toolhive-studio/package.nix` (set `hash = lib.fakeHash;`, run
`nh os build`, copy the reported hash).
