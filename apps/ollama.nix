{ config, lib, pkgs, ... }:
{
  # Local LLM daemon for opencode: swaps the loaded model per-request
  # (gpt-oss:20b vs qwen3:4b), unlike llama-server which serves one
  # already-loaded model at a time.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    # Only 4GB VRAM: never keep two models resident at once, always
    # unload the previous model before loading the newly requested one.
    environmentVariables = {
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };

  # ollama uses DynamicUser=true, so systemd stores data in
  # /var/lib/private/ollama and symlinks /var/lib/ollama → that path.
  # We persist the real path; impermanence can't bind-mount over a symlink.
  environment.persistence."/persist" = {
    directories = [
      "/var/lib/private/ollama"
    ];
  };
}
