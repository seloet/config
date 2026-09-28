{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  beeLlama =
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}."beellama-${config.workstation.llmBackend}";
  mach1Llama =
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}."mach1-${config.workstation.mach1Backend}";
in
{
  home.packages =
    (with pkgs; [
      anki
      brave
      zed-editor
      glow
      fsel
      fastfetch
      fd
      ripgrep
      jq
      gh
      codex
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
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp
      bk
      thunderbird
      protonmail-bridge-gui
      grim
      slurp
      wl-clipboard
      smassh
    ])
    ++ lib.optionals config.workstation.portableWidgets [ pkgs.tuxedo ];

  programs.btop.enable = true;
  stylix.targets.btop.enable = true;
}
