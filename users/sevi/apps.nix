{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  anki = pkgs.anki.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pkg-config ];
    buildInputs = old.buildInputs ++ [ pkgs.zstd ];
    env = old.env // {
      # nixpkgs' offline wheel list omits hatchling's tomlkit dependency.
      UV_FIND_LINKS = pkgs.symlinkJoin {
        name = "anki-uv-wheels";
        paths = [
          old.env.UV_FIND_LINKS
          pkgs.anki.python.pkgs.tomlkit.dist
        ];
      };
    };
  });
  beeLlama =
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}."beellama-${config.workstation.llmBackend}";
  mach1Llama =
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}."mach1-${config.workstation.mach1Backend}";
  llmAgentPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  upstreamCodex = llmAgentPkgs.codex;
  codex = pkgs.runCommand "codex-${upstreamCodex.version}-packaged" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p "$out/libexec/codex/"{bin,codex-path,codex-resources} "$out/bin"
    cp -a ${upstreamCodex}/libexec/codex/bin/. "$out/libexec/codex/bin/"
    install -m 755 ${pkgs.ripgrep}/bin/rg "$out/libexec/codex/codex-path/rg"
    install -m 755 ${pkgs.bubblewrap}/bin/bwrap "$out/libexec/codex/codex-resources/bwrap"
    cp ${upstreamCodex}/libexec/codex/codex-package.json "$out/libexec/codex/"

    makeWrapper "$out/libexec/codex/bin/codex" "$out/bin/codex" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.bubblewrap ]}
    ln -s ../libexec/codex/bin/codex-code-mode-host "$out/bin/codex-code-mode-host"
    ln -s ../libexec/codex/bin/logs_client "$out/bin/logs_client"
    ln -s ${upstreamCodex}/share "$out/share"
  '';
in
{
  home.packages =
    (with pkgs; [
      anki
      zed-editor
      glow
      fsel
      fastfetch
      fd
      ripgrep
      jq
      gh
      codex
      llmAgentPkgs.antigravity-cli
      rclone
      llama-cpp
      beeLlama
      mach1Llama
      python3Packages.huggingface-hub
      keepassxc
      yt-dlp
      qbittorrent
      vlc
      cliamp
      kaggle
      llmAgentPkgs.omp
      bk
      thunderbird
      protonmail-bridge-gui
      grim
      slurp
      wl-clipboard
      smassh
      libreoffice-qt
    ])
    ++ lib.optionals config.workstation.portableWidgets [ pkgs.tuxedo ];

  programs.btop.enable = true;
  stylix.targets.btop.enable = true;
}
