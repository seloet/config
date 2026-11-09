{ pkgs, lib, ... }:

let
  # Helium is not yet in nixpkgs; use the hash-pinned official Linux AppImage.
  helium = pkgs.appimageTools.wrapType2 (finalAttrs: {
    pname = "helium";
    version = "0.21.1.1";
    src = pkgs.fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${finalAttrs.version}/helium-${finalAttrs.version}-x86_64.AppImage";
      hash = "sha256-pivECBuZcJsxFxZc96vnER07VEZxqxcjL0KbmwVEs/o=";
    };

    extraInstallCommands = ''
      install -Dm644 ${finalAttrs.contents}/helium.desktop "$out/share/applications/helium.desktop"
      install -Dm644 ${finalAttrs.contents}/helium.png "$out/share/icons/hicolor/256x256/apps/helium.png"
      substituteInPlace "$out/share/applications/helium.desktop" \
        --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
    '';

    meta = {
      description = "Private, fast, and honest Chromium-based web browser";
      homepage = "https://helium.computer/";
      changelog = "https://github.com/imputnet/helium-linux/releases/tag/${finalAttrs.version}";
      license = lib.licenses.gpl3Only;
      platforms = [ "x86_64-linux" ];
      mainProgram = "helium";
    };
  });
in
{
  home.packages = [ helium ];
  home.sessionVariables.BROWSER = "helium";

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "helium.desktop" ];
      "application/xhtml+xml" = [ "helium.desktop" ];
      "x-scheme-handler/http" = [ "helium.desktop" ];
      "x-scheme-handler/https" = [ "helium.desktop" ];
      "x-scheme-handler/about" = [ "helium.desktop" ];
      "x-scheme-handler/unknown" = [ "helium.desktop" ];
    };
  };
}
