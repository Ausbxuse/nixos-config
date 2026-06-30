{
  config,
  lib,
  ...
}: let
  defaultLocalModel = "qwen3.6:27b";
in {
  imports = [
    ../../modules/home/slimevr.nix
    ../../modules/home/gnome-tweaks.nix
    ../../modules/home/codex-local.nix
    ../../modules/home/ollama-agent.nix
  ];

  my.codexLocal = {
    enable = true;
    localModel = defaultLocalModel;
    models = [defaultLocalModel];
  };

  services.ollama-agent = {
    enable = true;
    port = 11434;
    contextLength = 32768;
    flashAttention = true;
    kvCacheType = "q4_0";
    parallel = 1;
    maxLoadedModels = 1;
    idleKeepAlive = "30m";
    autoStart = false;
    preloadModel = "";
    stopOnBattery = false;
  };

  programs.firefox.profiles.betterfox.extraConfig = lib.mkAfter ''
    user_pref("browser.uidensity", 1);
  '';
}
