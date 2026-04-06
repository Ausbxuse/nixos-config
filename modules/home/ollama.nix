{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ollama;
  modelsDir = "${cfg.dir}/models";
  ollamaDir = "${cfg.dir}";

  # SearXNG MCP server wrapper (like ~/src/public/ollama/flake.nix)
  searxng-mcp = pkgs.writeShellApplication {
    name = "searxng-mcp";
    runtimeInputs = [pkgs.nodejs_22];
    text = "exec npx -y mcp-searxng \"$@\"";
  };
in
{
  options.services.ollama = {
    enable = lib.mkEnableOption "Ollama - local LLM inference server";

    dir = lib.mkOption {
      type = lib.types.path;
      default = "${config.home.homeDirectory}/.local/share/ollama";
      defaultText = lib.mkDefault "~/.local/share/ollama";
      description = "Directory for Ollama data and models";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["qwen:3.5:27b"];
      description = "List of model names to download (e.g., [\"llama3.2\" \"gemma2\"])";
    };

    mcp = {
      enable = lib.mkEnableOption "MCP (Model Context Protocol) support";

      searxng = {
        enable = lib.mkEnableOption "SearXNG MCP server";
        url = lib.mkOption {
          type = lib.types.str;
          default = "https://search.zhenyuzhao.com";
          description = "Self-hosted SearXNG instance URL";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [ollama];

    xdg.dataDirs = [modelsDir];

    home.sessionVariables = {
      OLLAMA_MODELS = modelsDir;
    };

    home.activation.downloadOllamaModels =
      if cfg.models != [] then
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          for model in ${lib.escapeShellArg (lib.concatStringsSep " " cfg.models)}; do
            echo "Downloading Ollama model: $model"
            ollama pull "$model" || true
          done
        ''
      else
        "";
  };

  # MCP configuration
  config = lib.mkIf (cfg.mcp.enable || cfg.mcp.searxng.enable) {
    services.ollama.mcp.enable = true;

    home.packages = [searxng-mcp];

    xdg.configFile.".mcp.json".text = builtins.toJSON {
      mcpServers =
        lib.optionalAttrs cfg.mcp.searxng.enable {
          searxng = {
            type = "stdio";
            command = "searxng-mcp";
            args = [];
            env = {
              SEARXNG_URL = cfg.mcp.searxng.url;
            };
          };
        };
    };
  };
}
