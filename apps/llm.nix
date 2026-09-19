{ config, lib, pkgs, nixpkgs-llama, ... }:
let
  # See flake.nix: nixos-26.05 ships llama.cpp b9190, which has neither DFlash
  # nor DSpark speculative decoding. This pin has 0.4.0.
  pkgsLlama = import nixpkgs-llama {
    inherit (pkgs) system;
    config.allowUnfree = true;   # CUDA
  };
in
{
  # Local LLM daemon for opencode: swaps the loaded model per-request
  # (gpt-oss:20b vs qwen3:4b), unlike llama-server which serves one
  # already-loaded model at a time.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    # Static user instead of the default DynamicUser: DynamicUser only
    # auto-fixes ownership on directories systemd itself manages
    # (StateDirectory), not on an external mount we point OLLAMA_MODELS at,
    # so the ephemeral per-start UID kept fighting the zstorage mount below.
    user = "ollama";
    group = "ollama";
    # Model files are huge and re-downloadable; keep them off the small,
    # nearly-full zroot pool. Mounted from zstorage/ollama-models (see
    # disko-config.nix), like zstorage/comfyui-models.
    models = "/var/lib/ollama-models";
    # Only 4GB VRAM: never keep two models resident at once, always
    # unload the previous model before loading the newly requested one.
    environmentVariables = {
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };

  environment.systemPackages = [
    pkgs.llmfit
    # llama-server with --spec-type draft-dspark, for MiniCPM5-2B + its DSpark
    # draft head (~1.55x decode on the 1650). See ~/Tools/llm.
    (pkgsLlama.llama-cpp.override { cudaSupport = true; })
  ];

  # The upstream module hardcodes DynamicUser=true even when user/group are
  # set to a static account: systemd then still tries its DynamicUser
  # symlink dance for StateDirectory (/var/lib/ollama -> /var/lib/private/
  # ollama), which fails with "File exists" because /var/lib/ollama is a
  # real directory here, not a symlink. Force it off now that we have a
  # real static user.
  systemd.services.ollama.serviceConfig = {
    DynamicUser = lib.mkForce false;
    ReadWritePaths = lib.mkForce [ "/var/lib/ollama-models" ];
  };

  # Not persisted: only holds ollama's own small identity/config state,
  # which regenerates harmlessly. Actual model weights are the separate,
  # persistent zstorage/ollama-models mount above.
}
