{
  lib,
  pkgs,
  ...
}:

let
  wallpaperDirectory = ../../modules/themes/wallpapers;
  wallpaperEntries = builtins.readDir wallpaperDirectory;
  wallpaperNames = builtins.attrNames (
    lib.filterAttrs (
      name: type: type == "regular" && builtins.match ".*\\.(png|PNG|jpe?g|JPE?G|webp|WEBP)" name != null
    ) wallpaperEntries
  );
  wallpapers = map (name: wallpaperDirectory + "/${name}") wallpaperNames;
  wallpaperArgs = lib.concatMapStringsSep " " lib.escapeShellArg wallpapers;

  wallpaperCycle = pkgs.writeShellApplication {
    name = "wallpaper-cycle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.jq
    ];
    text = ''
      wallpapers=( ${wallpaperArgs} )

      if [[ -n "''${WALLPAPER_CYCLE_TEST_WALLPAPERS:-}" ]]; then
        mapfile -t wallpapers <<< "$WALLPAPER_CYCLE_TEST_WALLPAPERS"
      fi

      if (( ''${#wallpapers[@]} == 0 )); then
        echo "wallpaper-cycle: no supported wallpapers found" >&2
        exit 1
      fi

      mode="''${1:---next}"
      if [[ "$mode" != "--next" && "$mode" != "--restore" ]]; then
        echo "usage: wallpaper-cycle [--next|--restore]" >&2
        exit 2
      fi

      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state_file="''${WALLPAPER_CYCLE_STATE_FILE:-$state_home/wallpaper-cycle/index}"
      hyprctl_command="''${WALLPAPER_CYCLE_HYPRCTL:-hyprctl}"
      current=-1
      if [[ -r "$state_file" ]]; then
        read -r current < "$state_file"
      fi
      if [[ ! "$current" =~ ^[0-9]+$ ]]; then
        current=-1
      fi

      if [[ "$mode" == "--restore" ]]; then
        (( current < 0 )) && current=0
        index=$((current % ''${#wallpapers[@]}))
      else
        index=$(((current + 1) % ''${#wallpapers[@]}))
      fi
      selected="''${wallpapers[$index]}"

      mapfile -t monitors < <("$hyprctl_command" monitors -j | jq -r '.[].name')
      if (( ''${#monitors[@]} == 0 )); then
        echo "wallpaper-cycle: no active monitors found" >&2
        exit 1
      fi
      for monitor in "''${monitors[@]}"; do
        applied=false
        for _attempt in {1..50}; do
          if "$hyprctl_command" hyprpaper wallpaper "$monitor,$selected,cover" >/dev/null 2>&1; then
            applied=true
            break
          fi
          sleep 0.1
        done
        if [[ "$applied" != true ]]; then
          echo "wallpaper-cycle: could not set wallpaper on $monitor" >&2
          exit 1
        fi
      done

      mkdir -p "$(dirname "$state_file")"
      temporary="$state_file.tmp.$$"
      printf '%s\n' "$index" > "$temporary"
      mv "$temporary" "$state_file"
    '';
  };
in
{
  assertions = [
    {
      assertion = wallpapers != [ ];
      message = "Wallpaper cycling requires at least one PNG, JPEG, or WebP image.";
    }
  ];

  home.packages = [ wallpaperCycle ];

  services.hyprpaper = {
    enable = true;
    settings.splash = false;
  };

  # Restore the saved index once Hyprpaper starts. The script retries until
  # Hyprpaper's IPC socket is ready.
  systemd.user.services.hyprpaper.Service.ExecStartPost = [
    "${wallpaperCycle}/bin/wallpaper-cycle --restore"
  ];
}
