{ user, lib, ... }:

{
  services.local-assistant = {
    enable = true;
    speechConfig = "/home/${user}/LocalAssistant/config/speech.yaml";
    playChime = true;
    notifications = true;
  };

  systemd.user.services.local-assistant.Install.WantedBy = lib.mkForce [ ];
}
