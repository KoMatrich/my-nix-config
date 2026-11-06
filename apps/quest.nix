# Meta Quest development: sideload Unity Android builds with adb, and
# (optionally) stream a PC OpenXR session to the headset with WiVRn.
# unityhub itself is already installed from home.nix; install the editor's
# "Android Build Support" modules (OpenJDK, SDK & NDK) from inside the Hub.
#
# Meta's Quest Link / Air Link are Windows-only, so they are not an option here.
{ config, lib, pkgs, ... }:
{
  # adb. There is no programs.adb in nixos-26.05: systemd 258 tags Android
  # devices with `uaccess` by itself, so the package alone is enough (see
  # the programs.adb.enable removal message in nixos/modules/rename.nix).
  # unzip: Unity Hub's module installer shells out to it (it is not in the
  # Hub's FHS env), so installing Android OpenJDK/SDK fails with
  # "Command 'unzip' not found in PATH" without it.
  # scrcpy: mirror the headset's display in a window on the PC, over USB or
  # Wi-Fi (adb). Usage: enable Developer Mode in the Meta Horizon phone app,
  # plug in the Quest (accept the "Allow USB debugging" prompt in the
  # headset), then run `scrcpy`. Wireless: `adb tcpip 5555`, unplug, then
  # `adb connect <quest-ip>:5555 && scrcpy`.
  environment.systemPackages = [ pkgs.android-tools pkgs.unzip pkgs.scrcpy ];

  # WiVRn: OpenXR runtime that streams to the Quest's WiVRn client app. Not
  # started at login; run `systemctl --user start wivrn` when wanted. The
  # client app on the headset must match this server's version.
  services.wivrn = {
    enable = true;
    openFirewall = true;
    autoStart = false;
  };
}
