# Godot 4 editors (moved in from the standalone flake that used to live at
# ~/Tools/godot, so the toolchain is self-contained in /etc/nixos instead of
# depending on a path in /home). Installed as system packages rather than
# `nix run` from a project directory, so:
#   - the binaries survive `gc` (they're rooted by the system generation,
#     unlike a flake's own `result` symlink or per-run store paths)
#   - they're on PATH everywhere, including SSH/remote sessions
#   - the path is stable across rebuilds: /run/current-system/sw/bin/godot-X.Y
{ config, lib, pkgs, ... }:
let
  # Godot dlopen's everything at runtime — all libs go in LD_LIBRARY_PATH.
  # The binary's only DT_NEEDED entries are standard libc components.
  godotLibs = with pkgs; [
    fontconfig
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxinerama
    libxi
    libxrandr
    libxext
    libxfixes
    libGL
    vulkan-loader
    mesa
    alsa-lib
    libpulseaudio
    dbus
    udev
    speechd
  ];

  mkGodot = { version, hash }:
    let
      bin     = "Godot_v${version}-stable_linux.x86_64";
      exeName = "godot-${version}";
    in
    pkgs.stdenv.mkDerivation {
      pname = "godot4";
      inherit version;

      src = pkgs.fetchurl {
        url  = "https://github.com/godotengine/godot/releases/download/${version}-stable/${bin}.zip";
        inherit hash;
      };

      nativeBuildInputs = with pkgs; [ autoPatchelfHook unzip makeWrapper ];

      unpackPhase = "unzip $src";

      installPhase = ''
        mkdir -p $out/bin
        cp ${bin} $out/bin/${exeName}
        chmod +x $out/bin/${exeName}
      '';

      postFixup = ''
        wrapProgram $out/bin/${exeName} \
          --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath godotLibs}"
      '';

      meta.mainProgram = exeName;
    };
in
{
  environment.systemPackages = [
    (mkGodot { version = "4.4";   hash = "sha256-BdLE1vm1KmIN9Li5vdUROhpT6oP27dFgQtYJ/STsdaQ="; })
    (mkGodot { version = "4.5.1"; hash = "sha256-AuxT0cx9u5zGNVOTxhuatD0SRHUaEk8QJIpIAoMHiM0="; })
    (mkGodot { version = "4.7";   hash = "sha256-CxpsVMLGGcEuFp/pJB7dpLgQgLUZRRzsKYS/DSxstzw="; })
  ];
}
