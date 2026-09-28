{ pkgs, ... }:

let
  syncInterval = "*:0/5";

  calendarSync = pkgs.writeShellApplication {
    name = "calendar-sync";
    runtimeInputs = [ pkgs.calcurse ];
    text = ''
      config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/calcurse/caldav/config"
      if [ ! -f "$config_file" ]; then
        echo "calendar-sync: no CalDAV config at $config_file" >&2
        echo "calendar-sync: finish the one-time OAuth setup first (see users/sevi/calendar.nix)" >&2
        exit 1
      fi
      exec calcurse-caldav -v "$@"
    '';
  };

  calendarOpen = pkgs.writeShellApplication {
    name = "calendar-open";
    runtimeInputs = [ pkgs.calcurse ];
    text = ''
      if [ "$#" -gt 0 ] && [ -f "$1" ]; then
        calcurse -i "$1" >/dev/null
      fi
      exec calcurse
    '';
  };
in
{
  home.packages = [
    pkgs.calcurse
    pkgs.libsecret
    calendarSync
    calendarOpen
  ];

  xdg.configFile."calcurse/conf".text = ''
    general.autosave=yes
    general.confirmdelete=yes
    general.confirmquit=yes
    general.firstdayofweek=Monday
    appearance.calendarview=monthly
  '';

  systemd.user.services.calcurse-sync = {
    Unit = {
      Description = "Synchronise calcurse with Google Calendar";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = "%h/.config/calcurse/caldav/config";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${calendarSync}/bin/calendar-sync";
    };
  };

  systemd.user.timers.calcurse-sync = {
    Unit.Description = "Periodic calcurse <-> Google Calendar sync";
    Timer = {
      OnCalendar = syncInterval;
      Persistent = true;
      Unit = "calcurse-sync.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  xdg.desktopEntries.calcurse = {
    name = "calcurse";
    genericName = "Calendar";
    comment = "Terminal calendar and todo manager";
    exec = "${pkgs.ghostty}/bin/ghostty -o background-opacity=1 -e ${calendarOpen}/bin/calendar-open %f";
    terminal = false;
    type = "Application";
    mimeType = [ "text/calendar" ];
    categories = [
      "Office"
      "Calendar"
    ];
  };
}
