# OWON VDS1022/I USB oscilloscope GUI.
# https://github.com/florentbr/OWON-VDS1022
#
# Not in nixpkgs. Upstream ships prebuilt binaries only (jars + a JNI
# libusb bridge for linux/amd64) — there's no source to compile, so this
# just repackages the release tarball: autoPatchelf fixes up the two
# native .so's to find nixpkgs' libusb1 + glibc, and a wrapper launches
# java with an explicit classpath and java.library.path (upstream's own
# launch script relies on /opt + ldconfig, neither of which exist here).
#
# USB access is granted the same way install-linux.sh does it: a udev
# rule matching the device's vendor/product ID, shipped via
# services.udev.packages so NixOS installs/reloads it automatically.
{ config, lib, pkgs, ... }:
let
  owon-vds1022 = pkgs.stdenv.mkDerivation {
    pname = "owon-vds1022";
    version = "1.1.5-cf19";

    src = pkgs.fetchzip {
      url = "https://github.com/florentbr/OWON-VDS1022/archive/refs/tags/1.1.5-cf19.tar.gz";
      hash = "sha256-HZHm487XrClEpH4vz4Ee1FS78r7cQWq4Gjcfl/ihoBk=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper pkgs.copyDesktopItems ];
    buildInputs = [ pkgs.libusb1 ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      libdir=$out/share/owon-vds1022/lib
      mkdir -p "$libdir" "$out/share/owon-vds1022/fwr" "$out/bin"

      cp lib/*.jar "$libdir/"
      cp lib/linux/amd64/* "$libdir/"
      cp -r fwr/* "$out/share/owon-vds1022/fwr/"

      # libusbJava.so needs libusb-0.1.so.4, its sibling in $libdir; that's
      # not a "well-known" lib output dir, so tell autoPatchelf about it.
      addAutoPatchelfSearchPath "$libdir"

      for px in 32 48 64 96 128 256; do
        mkdir -p "$out/share/icons/hicolor/''${px}x''${px}/apps"
        cp "ico/icon-''${px}.png" "$out/share/icons/hicolor/''${px}x''${px}/apps/owon-vds1022.png"
      done

      mkdir -p "$out/etc/udev/rules.d"
      cat > "$out/etc/udev/rules.d/70-owon-vds1022.rules" <<'EOF'
      SUBSYSTEMS=="usb", ATTRS{idVendor}=="5345", ATTRS{idProduct}=="1234", MODE="0666"
      EOF

      # Explicit colon-joined classpath instead of java's "dir/*" wildcard
      # syntax, so it can't be mangled by wrapper/shell quoting.
      classpath=$(find "$libdir" -maxdepth 1 -name '*.jar' | paste -sd: -)

      makeWrapper ${pkgs.jdk}/bin/java "$out/bin/owon-vds1022" \
        --add-flags "-Djava.library.path=$libdir" \
        --add-flags "-cp" \
        --add-flags "$classpath" \
        --add-flags "com.owon.vds.tiny.Main"

      runHook postInstall
    '';

    desktopItems = [
      (pkgs.makeDesktopItem {
        name = "owon-vds1022";
        exec = "owon-vds1022";
        icon = "owon-vds1022";
        desktopName = "OWON VDS1022";
        genericName = "Oscilloscope";
        comment = "Application for the OWON VDS1022 oscilloscope";
        categories = [ "Utility" "Electronics" "Engineering" ];
      })
    ];

    meta = with lib; {
      description = "Unofficial application for the OWON VDS1022/I USB oscilloscope";
      homepage = "https://github.com/florentbr/OWON-VDS1022";
      license = licenses.unfree; # closed-source jar, no license file upstream
      platforms = [ "x86_64-linux" ];
      mainProgram = "owon-vds1022";
    };
  };
in
{
  environment.systemPackages = [ owon-vds1022 ];

  # MODE 0666 on the matching idVendor/idProduct, same as upstream's rule.
  services.udev.packages = [ owon-vds1022 ];
}
