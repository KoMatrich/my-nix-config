{ config, lib, pkgs, ... }:
{
  # OBS Studio: screen recording with an explicitly chosen microphone.
  # Screen capture goes through the PipeWire portal, so the same setup works
  # in GNOME and in the hyprland specialisation.
  # One-time setup after install: Sources -> + -> "Screen Capture (PipeWire)",
  # and Settings -> Audio -> Mic/Auxiliary Audio -> HyperX QuadCast (the
  # system default input is the built-in audio, so pick the mic by name).
  # Scenes and settings live in ~/.config/obs-studio (persisted on /home).
  programs.obs-studio.enable = true;

  # VAAPI/QSV encoding on the Intel iGPU, which renders the desktop under
  # PRIME offload. Without it OBS falls back to x264 software encoding.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
}
