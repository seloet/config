{ ... }:

{
  systemd.user.services.moshi-hook = {
    Unit = {
      Description = "Moshi agent hooks and phone gateway";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = "%h/.local/bin/moshi-hook";
    };

    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/moshi-hook serve";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
