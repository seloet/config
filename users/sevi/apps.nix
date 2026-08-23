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
in
{
  home.packages =
    (with pkgs; [
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
      keepassxc
      yt-dlp
      qbittorrent
      vlc
      cliamp
      kaggle
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp
      bk
    ])
    ++ lib.optionals config.workstation.portableWidgets [ pkgs.tuxedo ];

  programs.btop.enable = true;
  stylix.targets.btop.enable = true;
}
