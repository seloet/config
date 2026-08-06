{ config, pkgs, lib, ... }:

{
  # cliphist is a clipboard manager that holds clipboard and primary selection
  # data persistently, making middle-click paste work on Wayland (especially
  # on Hyprland where the primary selection protocol may not retain selections
  # across clients).
  #
  # The built-in services.cliphist module monitors the regular clipboard via
  # `wl-paste --watch`. We add an extra systemd service that also monitors
  # the primary selection via `wl-paste --primary --watch` so that
  # middle-click paste (X11-style primary selection) is captured and held
  # by cliphist as a persistent selection owner.

  services.cliphist = {
    enable = true;
    package = pkgs.cliphist;
    # Default extraOptions: ["-max-dedupe-search" "10" "-max-items" "500"]
  };

  # Extra service: monitor primary selection and feed it to cliphist store.
  systemd.user.services.cliphist-primary = {
    Unit = {
      Description = "cliphist primary selection watcher";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --primary --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ config.wayland.systemd.target ];
    };
  };
}
