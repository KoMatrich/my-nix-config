{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeWrapper
, wrapGAppsHook3
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, expat
, glib
, gtk3
, libappindicator-gtk3
, libdrm
, libGL
, libgbm
, libnotify
, libsecret
, libuuid
, libxkbcommon
, nspr
, libcap_ng
, libseccomp
, nss
, pango
, pipewire
, systemd
, vulkan-loader
, libX11
, libXcomposite
, libXdamage
, libXext
, libXfixes
, libXrandr
, libXtst
, libxcb
, libxshmfence
, xdg-utils
, trash-cli
}:

stdenv.mkDerivation rec {
  pname = "claude-desktop";
  version = "2.37337.1";

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
    hash = "sha256-QXRbCRTw/1FjGh/xu0A7g2v1yZWEXMpnQt05vKOi2hQ=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper wrapGAppsHook3 ];

  buildInputs = [
    alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat glib gtk3
    libcap_ng libdrm libgbm libseccomp libuuid libxkbcommon nspr nss pango pipewire
    libX11 libXcomposite libXdamage libXext libXfixes libXrandr libXtst libxcb libxshmfence
    stdenv.cc.cc.lib
  ];

  # dlopen()ed at runtime, so not visible to autoPatchelf's NEEDED scan.
  runtimeDependencies = [
    libGL libappindicator-gtk3 libnotify libsecret systemd vulkan-loader
  ];

  dontWrapGApps = true;
  dontConfigure = true;
  dontBuild = true;

  # setuid chrome-sandbox cannot be extracted inside the build sandbox; it is removed anyway.
  unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --exclude=./usr/lib/claude-desktop/chrome-sandbox";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/share
    cp -r usr/lib/claude-desktop $out/lib/claude-desktop
    cp -r usr/share/icons $out/share/icons
    install -Dm444 usr/share/applications/com.anthropic.Claude.desktop \
      $out/share/applications/com.anthropic.Claude.desktop

    # setuid helper cannot work from the store; Electron falls back to user
    # namespaces for its sandbox, which NixOS enables by default.
    rm -f $out/lib/claude-desktop/chrome-sandbox

    runHook postInstall
  '';

  postFixup = ''
    # NIXOS_OZONE_WL=1 (set by the Hyprland/GNOME Wayland sessions) switches
    # Electron to native Wayland; otherwise it stays on XWayland/X11.
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils trash-cli ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

    # The .desktop file uses a bare `claude-desktop`, which is on PATH.
    substituteInPlace $out/share/applications/com.anthropic.Claude.desktop \
      --replace-fail "Exec=claude-desktop" "Exec=$out/bin/claude-desktop"
  '';

  meta = {
    description = "Claude desktop app (Chat, Cowork, Claude Code) - Anthropic's official Linux beta";
    homepage = "https://code.claude.com/docs/en/desktop-linux";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "claude-desktop";
  };
}
