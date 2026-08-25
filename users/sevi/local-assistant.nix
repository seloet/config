{ user, ... }:

{
  services.local-assistant = {
    enable = true;
    speechConfig = "/home/${user}/LocalAssistant/config/speech.yaml";
    playChime = true;
    notifications = true;
  };
}
