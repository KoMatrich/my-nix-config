# Orca (onorca.dev, github.com/stablyai/orca) -- desktop app for running
# coding agents side by side in git worktrees -- repackaged for NixOS.
# Not the GNOME screen reader of the same name: that one is pkgs.orca, so this
# package is pkgs.orca-ide, named after upstream's .deb and binary.
#
# Upstream ships a prebuilt Electron app (AppImage/.deb/.rpm); this unpacks the
# .deb and patches the Linux x64 ELF binaries with autoPatchelf.
# Applied as pkgs.orca-ide by an overlay in flake.nix.
#
# Update: bump `version` + `hash` below. Newest version is the `version:` in
#   https://github.com/stablyai/orca/releases/latest/download/latest-linux.yml
# (its sha512 is for the .deb too, but Nix wants sha256: easiest is to set
# `hash = lib.fakeHash;`, run `nh os build`, and copy the hash it reports).
# In-app updates are disabled (see installPhase); Nix is the updater.
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
, gobject-introspection
, python3
, xdg-utils
, xdotool
, xclip
, xvfb-run
}:

let
  # Computer use (resources/computer-use-linux/runtime.py) needs a python3
  # with PyGObject plus the AT-SPI typelib; the .deb depends on
  # python3-gi + gir1.2-atspi-2.0 for the same thing.
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenv.mkDerivation rec {
  pname = "orca-ide";
  version = "1.4.255";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-ide_${version}_amd64.deb";
    hash = "sha256-bfU/T2yRn9HxDf41EZQJNKzJQKd1TrGw6JbSxi5K3Vo=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper wrapGAppsHook3 gobject-introspection ];

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
  # Patched selectively in postFixup: orcad-template/ holds prebuilt daemons
  # (incl. musl, arm64, macOS, Windows) that Orca copies to *remote* SSH hosts,
  # and must stay byte-for-byte unpatched for those hosts.
  dontAutoPatchelf = true;

  # setuid chrome-sandbox cannot be extracted inside the build sandbox; it is removed anyway.
  unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --exclude=./opt/Orca/chrome-sandbox";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    cp -r opt/Orca $out/lib/orca
    cp -r usr/share/icons $out/share/icons
    install -Dm444 usr/share/applications/orca-ide.desktop \
      $out/share/applications/orca-ide.desktop

    # setuid helper cannot work from the store; Electron falls back to user
    # namespaces for its sandbox, which NixOS enables by default.
    rm -f $out/lib/orca/chrome-sandbox

    # Without the "deb" marker the updater cannot pick a package manager, so
    # it never tries `pkexec dpkg -i` on a read-only store path.
    rm -f $out/lib/orca/resources/package-type

    # Bundled binaries for other platforms; only linux-x64 runs here.
    rm -rf $out/lib/orca/resources/ripgrep/{darwin,win32}-* \
      $out/lib/orca/resources/app.asar.unpacked/resources/darwin

    runHook postInstall
  '';

  postFixup = ''
    autoPatchelf \
      $out/lib/orca/*.so* $out/lib/orca/orca-ide $out/lib/orca/chrome_crashpad_handler \
      $out/lib/orca/resources/agent-browser-linux-x64 \
      $out/lib/orca/resources/bin \
      $out/lib/orca/resources/ripgrep \
      $out/lib/orca/resources/node_modules

    # runtimeDependencies only land in the executable's RUNPATH, but ANGLE's
    # libEGL/libGLESv2 do the dlopen("libGL.so.1") themselves; without this the
    # GPU process cannot initialise GL. (Not LD_LIBRARY_PATH: that would leak
    # into every agent terminal Orca spawns.)
    patchelf --add-rpath ${lib.makeLibraryPath [ libGL ]} \
      $out/lib/orca/libEGL.so $out/lib/orca/libGLESv2.so

    # Env-only wrapper around the Electron binary itself (no flags): the
    # bundled `orca-ide` CLI re-runs that same binary with
    # ELECTRON_RUN_AS_NODE=1, where extra flags would break Node.
    # Electron 43 picks Wayland vs X11 on its own.
    wrapProgram $out/lib/orca/orca-ide \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ python xdg-utils xdotool xclip xvfb-run ]}

    # `orca-ide` is upstream's CLI (agents use it to drive the app; bare
    # `orca-ide` prints help). It resolves the app relative to its symlink
    # target.
    ln -s $out/lib/orca/resources/bin/orca-ide $out/bin/orca-ide

    # `orca-desktop` starts the GUI (also used by the .desktop entry). Orca
    # cannot detect the keyring under Hyprland and would store secrets
    # unencrypted; both our sessions run gnome-keyring, so name it.
    makeWrapper $out/lib/orca/orca-ide $out/bin/orca-desktop \
      --add-flags "--password-store=gnome-libsecret"

    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail "Exec=/opt/Orca/orca-ide" "Exec=$out/bin/orca-desktop"
  '';

  meta = {
    description = "Orca - IDE for running coding agents in parallel git worktrees";
    homepage = "https://www.onorca.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "orca-ide";
  };
}
