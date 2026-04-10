{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.llamacpp-agent;
  modelCfg = cfg.model;
  managedModelPath = "${modelCfg.dir}/${modelCfg.fileName}";
  resolvedModelPath =
    if modelCfg.url != null
    then managedModelPath
    else modelCfg.path;

  llamaCpp = pkgs.llama-cpp.override {
    cudaSupport = cfg.cudaSupport;
  };

  downloadScript = pkgs.writeShellApplication {
    name = "llamacpp-agent-download-model";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnugrep
    ];
    text = ''
      set -euo pipefail

      target="''${LLAMACPP_MODEL_TARGET:?}"
      dir="$(dirname "$target")"
      tmp="''${target}.part"
      expected="''${LLAMACPP_MODEL_SHA256:?}"
      url="''${LLAMACPP_MODEL_URL:?}"

      mkdir -p "$dir"

      if [ -f "$target" ]; then
        current="$(sha256sum "$target" | cut -d' ' -f1)"
        if [ "$current" = "$expected" ]; then
          exit 0
        fi
        rm -f "$target"
      fi

      auth_args=()
      if [ -n "''${LLAMACPP_HF_TOKEN_FILE:-}" ] && [ -f "''${LLAMACPP_HF_TOKEN_FILE}" ]; then
        token="$(tr -d '\n' < "''${LLAMACPP_HF_TOKEN_FILE}")"
        auth_args=(-H "Authorization: Bearer $token")
      fi

      ${pkgs.curl}/bin/curl \
        --fail \
        --location \
        --continue-at - \
        --output "$tmp" \
        "''${auth_args[@]}" \
        "$url"

      downloaded="$(sha256sum "$tmp" | cut -d' ' -f1)"
      if [ "$downloaded" != "$expected" ]; then
        echo "sha256 mismatch for $tmp" >&2
        echo "expected: $expected" >&2
        echo "actual:   $downloaded" >&2
        exit 1
      fi

      mv "$tmp" "$target"
    '';
  };

  gatewayScript = pkgs.writeText "llamacpp-gateway.mjs" ''
    import fs from "node:fs";
    import http from "node:http";
    import { spawn } from "node:child_process";

    const host = process.env.LLAMACPP_HOST ?? "127.0.0.1";
    const publicPort = Number(process.env.LLAMACPP_PUBLIC_PORT ?? "8080");
    const backendPort = Number(process.env.LLAMACPP_BACKEND_PORT ?? "18080");
    const modelPath = process.env.LLAMACPP_MODEL_PATH;
    const contextSize = process.env.LLAMACPP_CONTEXT_SIZE ?? "16384";
    const gpuLayers = process.env.LLAMACPP_GPU_LAYERS ?? "99";
    const parallel = process.env.LLAMACPP_PARALLEL ?? "1";
    const flashAttention = process.env.LLAMACPP_FLASH_ATTENTION ?? "on";
    const cacheTypeK = process.env.LLAMACPP_CACHE_TYPE_K ?? "q8_0";
    const cacheTypeV = process.env.LLAMACPP_CACHE_TYPE_V ?? "q8_0";
    const idleMs = Number(process.env.LLAMACPP_IDLE_TIMEOUT_MS ?? "1800000");
    const dockedMarker = process.env.LLAMACPP_DOCKED_MARKER ?? "/etc/llamacpp/docked";
    const preloadOnlyOnAC = (process.env.LLAMACPP_PRELOAD_ONLY_ON_AC ?? "1") === "1";
    const powerSupplyRoot = process.env.LLAMACPP_POWER_SUPPLY_ROOT ?? "/sys/class/power_supply";
    const llamaServer = process.env.LLAMACPP_SERVER_BIN;

    if (!modelPath || modelPath === "null") {
      throw new Error("LLAMACPP_MODEL_PATH is required");
    }

    if (!llamaServer) {
      throw new Error("LLAMACPP_SERVER_BIN is required");
    }

    let backendProc = null;
    let backendReady = null;
    let stopTimer = null;
    let lastActivity = 0;
    let activeRequests = 0;

    const log = (...args) => console.log("[llamacpp-gateway]", ...args);
    const isDocked = () => fs.existsSync(dockedMarker);

    function isOnACPower() {
      try {
        const entries = fs.readdirSync(powerSupplyRoot, { withFileTypes: true });
        const onlineValues = entries
          .filter((entry) => entry.isDirectory())
          .map((entry) => {
            const onlinePath = `${powerSupplyRoot}/${entry.name}/online`;
            if (!fs.existsSync(onlinePath)) {
              return null;
            }
            return fs.readFileSync(onlinePath, "utf8").trim();
          })
          .filter((value) => value !== null);

        if (onlineValues.length > 0) {
          return onlineValues.some((value) => value === "1");
        }

        const statusValues = entries
          .filter((entry) => entry.isDirectory())
          .map((entry) => {
            const statusPath = `${powerSupplyRoot}/${entry.name}/status`;
            if (!fs.existsSync(statusPath)) {
              return null;
            }
            return fs.readFileSync(statusPath, "utf8").trim();
          })
          .filter((value) => value !== null);

        return statusValues.some((value) => value === "Charging" || value === "Full");
      } catch (error) {
        log("failed to read AC state", error);
        return false;
      }
    }

    function shouldKeepLoaded() {
      if (!isDocked()) {
        return false;
      }

      if (!preloadOnlyOnAC) {
        return true;
      }

      return isOnACPower();
    }

    function clearStopTimer() {
      if (stopTimer) {
        clearTimeout(stopTimer);
        stopTimer = null;
      }
    }

    function markActivity() {
      lastActivity = Date.now();
    }

    function backendArgs() {
      return [
        "-m", modelPath,
        "-ngl", gpuLayers,
        "-c", contextSize,
        "--flash-attn", flashAttention,
        "--cache-type-k", cacheTypeK,
        "--cache-type-v", cacheTypeV,
        "--parallel", parallel,
        "--host", host,
        "--port", String(backendPort),
      ];
    }

    function backendIsRunning() {
      return backendProc !== null && backendProc.exitCode === null && !backendProc.killed;
    }

    async function waitForBackend(timeoutMs = 300000) {
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const ready = await new Promise((resolve) => {
          const req = http.request(
            {
              host,
              port: backendPort,
              method: "GET",
              path: "/health",
              timeout: 1000,
            },
            (res) => {
              res.resume();
              resolve(res.statusCode !== undefined && res.statusCode < 500);
            },
          );

          req.on("timeout", () => {
            req.destroy();
            resolve(false);
          });
          req.on("error", () => resolve(false));
          req.end();
        });

        if (ready) {
          return;
        }

        await new Promise((resolve) => setTimeout(resolve, 1000));
      }

      throw new Error("Timed out waiting for llama-server to become ready");
    }

    async function ensureBackend() {
      if (backendIsRunning()) {
        return;
      }

      if (backendReady) {
        await backendReady;
        return;
      }

      log("starting backend", { modelPath, backendPort });
      backendProc = spawn(llamaServer, backendArgs(), {
        stdio: "inherit",
      });

      backendProc.on("exit", (code, signal) => {
        log("backend exited", { code, signal });
        backendProc = null;
        backendReady = null;
      });

      backendReady = waitForBackend().then(() => {
        log("backend ready", { backendPort });
      });

      try {
        await backendReady;
      } catch (error) {
        backendReady = null;
        if (backendProc) {
          backendProc.kill("SIGTERM");
        }
        throw error;
      }
    }

    function stopBackend(reason) {
      clearStopTimer();

      if (!backendIsRunning()) {
        return;
      }

      log("stopping backend", { reason });
      backendProc.kill("SIGTERM");
      stopTimer = setTimeout(() => {
        if (backendIsRunning()) {
          log("forcing backend stop", { reason });
          backendProc.kill("SIGKILL");
        }
      }, 20000);
    }

    setInterval(() => {
      if (!backendIsRunning()) {
        if (shouldKeepLoaded()) {
          markActivity();
          ensureBackend().catch((error) => {
            log("failed to prewarm backend", error);
          });
        }
        return;
      }

      if (shouldKeepLoaded()) {
        return;
      }

      if (activeRequests === 0 && Date.now() - lastActivity >= idleMs) {
        stopBackend("idle timeout");
      }
    }, 30000);

    if (shouldKeepLoaded()) {
      markActivity();
      ensureBackend().catch((error) => {
        log("failed to prewarm backend", error);
      });
    }

    const server = http.createServer(async (req, res) => {
      markActivity();
      activeRequests += 1;

      const finishRequest = () => {
        activeRequests = Math.max(0, activeRequests - 1);
        markActivity();
      };

      res.once("close", finishRequest);

      try {
        await ensureBackend();
      } catch (error) {
        res.writeHead(503, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: String(error) }));
        return;
      }

      const upstream = http.request(
        {
          host,
          port: backendPort,
          method: req.method,
          path: req.url,
          headers: req.headers,
        },
        (upstreamRes) => {
          res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
          upstreamRes.pipe(res);
        },
      );

      upstream.on("error", (error) => {
        res.writeHead(502, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: String(error) }));
      });

      req.pipe(upstream);
    });

    server.listen(publicPort, host, () => {
      log("gateway listening", {
        host,
        publicPort,
        backendPort,
        docked: isDocked(),
        onACPower: isOnACPower(),
        keepLoaded: shouldKeepLoaded(),
      });
    });

    function shutdown(signal) {
      log("shutting down", { signal });
      server.close(() => process.exit(0));
      stopBackend(signal);
      setTimeout(() => process.exit(0), 25000);
    }

    process.on("SIGINT", () => shutdown("SIGINT"));
    process.on("SIGTERM", () => shutdown("SIGTERM"));
  '';
in {
  options.services.llamacpp-agent = {
    enable = lib.mkEnableOption "On-demand llama.cpp gateway with idle model unload";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind host for the public gateway and backend listener.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Stable public port for the local gateway.";
    };

    backendPort = lib.mkOption {
      type = lib.types.port;
      default = 18080;
      description = "Internal llama-server port used behind the gateway.";
    };

    model = {
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Absolute path to an existing GGUF file when not using managed downloads.";
      };

      dir = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.dataHome}/llamacpp/models";
        description = "Directory for declaratively managed GGUF downloads.";
      };

      fileName = lib.mkOption {
        type = lib.types.str;
        default = "model.gguf";
        description = "Filename for the managed GGUF download.";
      };

      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Remote GGUF URL to fetch declaratively.";
      };

      sha256 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Expected SHA-256 for the downloaded GGUF file.";
      };

      huggingfaceTokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional file containing a Hugging Face token for gated/private downloads.";
      };
    };

    contextSize = lib.mkOption {
      type = lib.types.int;
      default = 16384;
      description = "Context window passed to llama-server.";
    };

    gpuLayers = lib.mkOption {
      type = lib.types.int;
      default = 99;
      description = "Number of layers to offload to GPU.";
    };

    parallel = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Parallel request slots for llama-server.";
    };

    idleTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 1800;
      description = "How long to keep the model loaded after the last request when not docked.";
    };

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Build llama.cpp with CUDA support.";
    };

    dockedMarker = lib.mkOption {
      type = lib.types.str;
      default = "/etc/llamacpp/docked";
      description = "Marker file that indicates the system booted into docked mode.";
    };

    preloadOnlyOnACPower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require AC power before keeping the backend preloaded in docked mode.";
    };

    powerSupplyRoot = lib.mkOption {
      type = lib.types.str;
      default = "/sys/class/power_supply";
      description = "Runtime sysfs directory used to detect AC power state.";
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.port != cfg.backendPort;
        message = "services.llamacpp-agent.port and backendPort must be different.";
      }
      {
        assertion = (modelCfg.url != null) || (modelCfg.path != null);
        message = "Set either services.llamacpp-agent.model.url for managed downloads or services.llamacpp-agent.model.path for an existing local GGUF.";
      }
      {
        assertion = (modelCfg.url == null) || (modelCfg.sha256 != null);
        message = "services.llamacpp-agent.model.sha256 is required when model.url is set.";
      }
    ];

    home.packages = [
      pkgs.nodejs_22
      llamaCpp
    ] ++ lib.optionals (modelCfg.url != null) [downloadScript];

    systemd.user.services.llamacpp-agent-model = lib.mkIf (modelCfg.url != null) {
      Unit = {
        Description = "Download declarative llama.cpp model";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${downloadScript}/bin/llamacpp-agent-download-model";
        Environment = [
          "LLAMACPP_MODEL_URL=${modelCfg.url}"
          "LLAMACPP_MODEL_SHA256=${modelCfg.sha256}"
          "LLAMACPP_MODEL_TARGET=${managedModelPath}"
        ] ++ lib.optionals (modelCfg.huggingfaceTokenFile != null) [
          "LLAMACPP_HF_TOKEN_FILE=${modelCfg.huggingfaceTokenFile}"
        ];
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };

    systemd.user.services.llamacpp-agent = {
      Unit = {
        Description = "On-demand llama.cpp gateway";
      }
      // lib.optionalAttrs (modelCfg.url != null) {
        After = ["llamacpp-agent-model.service"];
        Wants = ["llamacpp-agent-model.service"];
      };
      Service = {
        ExecStart = "${pkgs.nodejs_22}/bin/node ${gatewayScript}";
        Restart = "always";
        RestartSec = 3;
        Environment = [
          "LLAMACPP_HOST=${cfg.host}"
          "LLAMACPP_PUBLIC_PORT=${toString cfg.port}"
          "LLAMACPP_BACKEND_PORT=${toString cfg.backendPort}"
          "LLAMACPP_MODEL_PATH=${resolvedModelPath}"
          "LLAMACPP_CONTEXT_SIZE=${toString cfg.contextSize}"
          "LLAMACPP_GPU_LAYERS=${toString cfg.gpuLayers}"
          "LLAMACPP_PARALLEL=${toString cfg.parallel}"
          "LLAMACPP_IDLE_TIMEOUT_MS=${toString (cfg.idleTimeoutSeconds * 1000)}"
          "LLAMACPP_DOCKED_MARKER=${cfg.dockedMarker}"
          "LLAMACPP_PRELOAD_ONLY_ON_AC=${if cfg.preloadOnlyOnACPower then "1" else "0"}"
          "LLAMACPP_POWER_SUPPLY_ROOT=${cfg.powerSupplyRoot}"
          "LLAMACPP_SERVER_BIN=${llamaCpp}/bin/llama-server"
          "LLAMACPP_FLASH_ATTENTION=on"
          "LLAMACPP_CACHE_TYPE_K=q8_0"
          "LLAMACPP_CACHE_TYPE_V=q8_0"
        ];
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
