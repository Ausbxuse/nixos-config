{lib, ...}: {
  imports = [
    ../../modules/home/slimevr.nix
    ../../modules/home/gnome-tweaks.nix
    ../../modules/home/llamacpp-agent.nix
  ];

  services.llamacpp-agent = {
    enable = true;
    port = 8080;
    backendPort = 18080;
    contextSize = 16384;
    gpuLayers = 99;
    idleTimeoutSeconds = 1800;
    model = {
      fileName = "Qwen3.5-27B-Q4_K_M.gguf";
      url = "https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/Qwen3.5-27B-Q4_K_M.gguf";
      sha256 = "84b5f7f112156d63836a01a69dc3f11a6ba63b10a23b8ca7a7efaf52d5a2d806";
    };
  };

  programs.firefox.profiles.betterfox.extraConfig = lib.mkAfter ''
    user_pref("browser.uidensity", 1);
  '';
}
