{
  config,
  const,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.codexLocal;
  modelsDir = "${cfg.dir}/models";

  searxng-mcp = pkgs.writeShellApplication {
    name = "searxng-mcp";
    runtimeInputs = [pkgs.nodejs_22];
    text = "exec npx -y mcp-searxng \"$@\"";
  };
in {
  options.my.codexLocal = {
    enable = lib.mkEnableOption "Codex local wrapper backed by Ollama";

    dir = lib.mkOption {
      type = lib.types.path;
      default = "${config.home.homeDirectory}/.local/share/ollama";
      defaultText = lib.mkDefault "~/.local/share/ollama";
      description = "Directory for Ollama data and downloaded models.";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["qwen:3.5:27b"];
      description = "List of Ollama models to pre-download for local Codex usage.";
    };

    localModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.5:27b";
      description = "Model name passed to the codex-local wrapper.";
    };

    searxngUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = lib.attrByPath ["services" "searxng" "url"] null const;
      description = "SearXNG URL injected into the local Codex wrapper.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [searxng-mcp];

    home.sessionVariables = {
      OLLAMA_MODELS = modelsDir;
      CODEX_LOCAL_LLM_API_KEY = "ollama";
      CODEX_LOCAL_MODEL = cfg.localModel;
    };

    home.activation.downloadOllamaModels =
      if cfg.models != []
      then
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          for model in ${lib.escapeShellArg (lib.concatStringsSep " " cfg.models)}; do
            echo "Downloading Ollama model: $model"
            ${pkgs.ollama}/bin/ollama pull "$model" || true
          done
        ''
      else
        "";

    xdg.configFile.".mcp.json".text = builtins.toJSON {
      mcpServers = lib.optionalAttrs (cfg.searxngUrl != null) {
        searxng = {
          type = "stdio";
          command = "searxng-mcp";
          args = [];
          env = {
            SEARXNG_URL = cfg.searxngUrl;
          };
        };
      };
    };

    home.file.".local/bin/codex-local" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec codex \
          -c 'model_provider="local-ollama"' \
          -c 'model_reasoning_effort="medium"' \
          -c 'model_providers.local-ollama.name="Local Ollama"' \
          -c 'model_providers.local-ollama.base_url="http://127.0.0.1:11434/v1"' \
          -c 'model_providers.local-ollama.env_key="CODEX_LOCAL_LLM_API_KEY"' \
          -c 'model_providers.local-ollama.wire_api="responses"' \
          ${lib.optionalString (cfg.searxngUrl != null) ''
          -c 'mcp_servers.searxng.command="searxng-mcp"' \
          -c 'mcp_servers.searxng.env.SEARXNG_URL="${cfg.searxngUrl}"' \
          ''} \
          --model "''${CODEX_LOCAL_MODEL:?CODEX_LOCAL_MODEL must be set}" \
          "$@"
      '';
    };

    programs.zsh.shellAliases = {
      co = "codex-local";
    };
  };
}
