{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ollama-agent;

  ollamaPkg =
    if cfg.cudaSupport
    then pkgs.ollama-cuda
    else pkgs.ollama;

  preloaderScript = pkgs.writeShellApplication {
    name = "ollama-preloader";
    runtimeInputs = with pkgs; [coreutils curl];
    text = ''
      set -euo pipefail

      host="${cfg.host}:${toString cfg.port}"
      docked_marker="${cfg.dockedMarker}"
      preload_only_on_ac="${
        if cfg.preloadOnlyOnACPower
        then "1"
        else "0"
      }"
      power_root="${cfg.powerSupplyRoot}"
      preload_model="${cfg.preloadModel}"
      idle_keep_alive="${cfg.idleKeepAlive}"

      if [ -z "$preload_model" ]; then
        echo "ollama-preloader: no preloadModel configured, exiting"
        exit 0
      fi

      is_docked() {
        [ -f "$docked_marker" ]
      }

      is_on_ac() {
        local any_online=0
        for dir in "$power_root"/*; do
          [ -d "$dir" ] || continue
          if [ -f "$dir/online" ]; then
            if [ "$(cat "$dir/online")" = "1" ]; then
              return 0
            fi
            any_online=1
          fi
        done
        if [ "$any_online" = "1" ]; then
          return 1
        fi
        for dir in "$power_root"/*; do
          [ -d "$dir" ] || continue
          if [ -f "$dir/status" ]; then
            case "$(cat "$dir/status")" in
              Charging|Full) return 0 ;;
            esac
          fi
        done
        return 1
      }

      should_preload() {
        is_docked || return 1
        if [ "$preload_only_on_ac" = "1" ]; then
          is_on_ac || return 1
        fi
        return 0
      }

      # Wait for ollama to be reachable
      for _ in $(seq 1 60); do
        if curl -sf "http://$host/api/tags" > /dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      call_keep_alive() {
        local ka="$1"
        curl -sf -X POST "http://$host/api/generate" \
          -H "Content-Type: application/json" \
          -d "{\"model\":\"$preload_model\",\"prompt\":\"\",\"keep_alive\":$ka}" \
          > /dev/null || true
      }

      state="unknown"
      while true; do
        if should_preload; then
          new="preload"
        else
          new="idle"
        fi

        if [ "$state" != "$new" ]; then
          if [ "$new" = "preload" ]; then
            echo "ollama-preloader: preloading $preload_model (docked+AC)"
            call_keep_alive "-1"
          else
            echo "ollama-preloader: reverting to idle keep_alive=$idle_keep_alive"
            call_keep_alive "\"$idle_keep_alive\""
          fi
          state="$new"
        fi

        sleep 30
      done
    '';
  };

  powerStateScript = pkgs.writeShellApplication {
    name = "ollama-power-state";
    runtimeInputs = with pkgs; [coreutils systemd];
    text = ''
      set -euo pipefail

      power_root="${cfg.powerSupplyRoot}"

      is_on_ac() {
        local any_online=0
        for dir in "$power_root"/*; do
          [ -d "$dir" ] || continue
          if [ -f "$dir/online" ]; then
            if [ "$(cat "$dir/online")" = "1" ]; then
              return 0
            fi
            any_online=1
          fi
        done
        if [ "$any_online" = "1" ]; then
          return 1
        fi
        for dir in "$power_root"/*; do
          [ -d "$dir" ] || continue
          if [ -f "$dir/status" ]; then
            case "$(cat "$dir/status")" in
              Charging|Full) return 0 ;;
            esac
          fi
        done
        return 1
      }

      state="unknown"
      while true; do
        if is_on_ac; then
          new="ac"
        else
          new="battery"
        fi

        if [ "$state" != "$new" ]; then
          if [ "$new" = "ac" ]; then
            echo "ollama-power-state: AC power detected, starting ollama"
            systemctl --user start ollama.service
          else
            echo "ollama-power-state: battery power detected, stopping ollama"
            systemctl --user stop ollama.service
          fi
          state="$new"
        fi

        sleep 30
      done
    '';
  };
in {
  options.services.ollama-agent = {
    enable = lib.mkEnableOption "Ollama server with AC-power-aware model preload";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind host for ollama serve.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Bind port for ollama serve.";
    };

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use the CUDA build of Ollama.";
    };

    contextLength = lib.mkOption {
      type = lib.types.int;
      default = 16384;
      description = "Default context window (OLLAMA_CONTEXT_LENGTH).";
    };

    flashAttention = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable flash attention (required for KV cache quantization).";
    };

    kvCacheType = lib.mkOption {
      type = lib.types.enum ["f16" "q8_0" "q4_0"];
      default = "q8_0";
      description = "KV cache quantization type (OLLAMA_KV_CACHE_TYPE).";
    };

    parallel = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Parallel request slots (OLLAMA_NUM_PARALLEL).";
    };

    idleKeepAlive = lib.mkOption {
      type = lib.types.str;
      default = "30m";
      description = "Default OLLAMA_KEEP_ALIVE value (e.g. \"30m\", \"1h\", \"0\").";
    };

    preloadModel = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Model tag to preload when docked + on AC. Empty disables preloading.";
    };

    dockedMarker = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ollama/docked";
      description = "Marker file that indicates the system booted into docked mode.";
    };

    preloadOnlyOnACPower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require AC power before preloading the model in docked mode.";
    };

    stopOnBattery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Stop the Ollama user service whenever the system is on battery power.";
    };

    powerSupplyRoot = lib.mkOption {
      type = lib.types.str;
      default = "/sys/class/power_supply";
      description = "sysfs directory used to detect AC power state.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ollamaPkg];

    systemd.user.services.ollama = {
      Unit = {
        Description = "Ollama server";
        After = ["network.target"];
      };
      Service = {
        ExecStart = "${ollamaPkg}/bin/ollama serve";
        Restart = "always";
        RestartSec = 3;
        Environment = [
          "OLLAMA_HOST=${cfg.host}:${toString cfg.port}"
          "OLLAMA_KEEP_ALIVE=${cfg.idleKeepAlive}"
          "OLLAMA_FLASH_ATTENTION=${
            if cfg.flashAttention
            then "1"
            else "0"
          }"
          "OLLAMA_KV_CACHE_TYPE=${cfg.kvCacheType}"
          "OLLAMA_CONTEXT_LENGTH=${toString cfg.contextLength}"
          "OLLAMA_NUM_PARALLEL=${toString cfg.parallel}"
        ];
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };

    systemd.user.services.ollama-preloader = lib.mkIf (cfg.preloadModel != "") {
      Unit = {
        Description = "Ollama docked/AC-power preloader";
        After = ["ollama.service"];
        Wants = ["ollama.service"];
      };
      Service = {
        ExecStart = "${preloaderScript}/bin/ollama-preloader";
        Restart = "always";
        RestartSec = 10;
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };

    systemd.user.services.ollama-power-state = lib.mkIf cfg.stopOnBattery {
      Unit = {
        Description = "Ollama AC/battery power-state manager";
        After = ["default.target"];
      };
      Service = {
        ExecStart = "${powerStateScript}/bin/ollama-power-state";
        Restart = "always";
        RestartSec = 10;
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
