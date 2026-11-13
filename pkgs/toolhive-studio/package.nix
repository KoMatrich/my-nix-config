# ToolHive Studio (github.com/stacklok/toolhive-studio) -- desktop UI for
# running and managing MCP servers in containers -- repackaged for NixOS.
# Upstream ships a prebuilt Electron app (.deb/.rpm/flatpak/tarball); this
# unpacks the .deb and patches the Linux x64 ELF binaries with autoPatchelf.
# Applied as pkgs.toolhive-studio by an overlay in flake.nix.
#
# The .deb bundles its own `thv` (the ToolHive CLI/API server, resources/bin/
# linux-x64/thv) and the app drives that copy, NOT pkgs.toolhive. Both share
# ~/.config/toolhive state, so keep them in mind when versions drift: nixpkgs'
# toolhive lags the UI's bundled thv. `toolhive-thv` (below) exposes the bundled
# one for scripts that must match the UI's version.
#
# Update: bump `version` + `hash`. Set `hash = lib.fakeHash;`, run
# `nh os build`, and copy the hash it reports. In-app updates are Nix's job.
{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeShellWrapper
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
, libXScrnSaver
, libXtst
, libxcb
, libxshmfence
, xdg-utils
}:

stdenv.mkDerivation rec {
  pname = "toolhive-studio";
  version = "0.40.2";

  src = fetchurl {
    url = "https://github.com/stacklok/toolhive-studio/releases/download/v${version}/toolhive_${version}_amd64.deb";
    hash = "sha256-UzQNN7wH7VY3UIjH6pvl+T6BqAAlisHumH+s8aPj9KA=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeShellWrapper wrapGAppsHook3 ];

  buildInputs = [
    alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat glib gtk3
    libdrm libgbm libuuid libxkbcommon nspr nss pango pipewire systemd
    libX11 libXcomposite libXdamage libXext libXfixes libXrandr libXScrnSaver libXtst libxcb libxshmfence
    stdenv.cc.cc.lib
  ];

  # dlopen()ed at runtime, so not visible to autoPatchelf's NEEDED scan.
  runtimeDependencies = [
    libGL libappindicator-gtk3 libnotify libsecret systemd vulkan-loader
  ];

  dontWrapGApps = true;
  dontConfigure = true;
  dontBuild = true;
  dontAutoPatchelf = true; # done selectively in postFixup

  # setuid chrome-sandbox cannot be extracted inside the build sandbox; it is removed anyway.
  unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --exclude=./usr/lib/toolhive/chrome-sandbox";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    cp -r usr/lib/toolhive $out/lib/toolhive
    install -Dm444 usr/share/pixmaps/toolhive.png $out/share/pixmaps/toolhive.png
    install -Dm444 usr/share/applications/toolhive.desktop \
      $out/share/applications/toolhive.desktop

    # Setuid helper cannot work from the store; Electron falls back to user
    # namespaces for its sandbox, which NixOS enables by default.
    rm -f $out/lib/toolhive/chrome-sandbox

    # better-sqlite3 ships a musl prebuild too; unused on glibc and it would
    # fail autoPatchelf (libc.musl not found).
    rm -rf $out/lib/toolhive/resources/app.asar.unpacked/node_modules/better-sqlite3/prebuilds/linuxmusl-x64.node

    runHook postInstall
  '';

  postFixup = ''
    autoPatchelf \
      $out/lib/toolhive/*.so* $out/lib/toolhive/ToolHive \
      $out/lib/toolhive/chrome_crashpad_handler \
      $out/lib/toolhive/resources/bin \
      $out/lib/toolhive/resources/app.asar.unpacked

    # ANGLE/Chromium dlopen libGL themselves; runtimeDependencies only reach the
    # main executable's RUNPATH.
    for lib in $out/lib/toolhive/libvulkan.so.1 $out/lib/toolhive/libvk_swiftshader.so; do
      [ -e "$lib" ] && patchelf --add-rpath ${lib.makeLibraryPath [ libGL vulkan-loader ]} "$lib"
    done

    # `toolhive` starts the GUI (also used by the .desktop entry). Name the
    # keyring so secrets are stored encrypted rather than in plaintext under
    # Hyprland, where Electron cannot auto-detect it.
    #
    # thv does not discover rootless Docker (our only daemon the user can reach,
    # see apps/virtualization.nix) on its own: without TOOLHIVE_DOCKER_SOCKET it
    # fails with "no container runtime available". A GUI launch has no shell
    # profile, hence set here (default only, so an explicit value still wins).
    makeShellWrapper $out/lib/toolhive/ToolHive $out/bin/toolhive \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --run 'export TOOLHIVE_DOCKER_SOCKET="''${TOOLHIVE_DOCKER_SOCKET:-$XDG_RUNTIME_DIR/docker.sock}"' \
      --add-flags "--password-store=gnome-libsecret"

    # The bundled thv, version-matched to this UI (see header comment).
    makeShellWrapper $out/lib/toolhive/resources/bin/linux-x64/thv $out/bin/toolhive-thv \
      --run 'export TOOLHIVE_DOCKER_SOCKET="''${TOOLHIVE_DOCKER_SOCKET:-$XDG_RUNTIME_DIR/docker.sock}"'

    substituteInPlace $out/share/applications/toolhive.desktop \
      --replace-fail "Exec=toolhive %U" "Exec=$out/bin/toolhive %U"
  '';

  meta = {
    description = "ToolHive Studio - desktop UI to install, run and manage MCP servers";
    homepage = "https://github.com/stacklok/toolhive-studio";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "toolhive";
  };
}
