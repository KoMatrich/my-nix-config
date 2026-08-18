{ config, lib, pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;

    loadModels = [
      "smtek/Qwen3.8-27B:IQ2_XXS"
    ];
  };
}