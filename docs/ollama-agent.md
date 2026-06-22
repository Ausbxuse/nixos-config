# Ollama Agent

The `razy` host runs Ollama as its local LLM backend via `services.ollama-agent`.
Ollama handles model downloads, loading/unloading, and the OpenAI-compatible
HTTP API itself — so there's no custom gateway.

## Behavior

- `ollama serve` is available as a user systemd service on `127.0.0.1:11434`.
- Ollama exposes an OpenAI-compatible API at `http://127.0.0.1:11434/v1`.
- On `razy`, the default local model is `qwen3.6:27b`.
- The `razy` profile uses a practical local-coding balance for the 24GB 5090 Laptop GPU:
  32K context, Flash Attention, Q4 KV cache, one parallel slot, and one loaded
  model.
- `OLLAMA_KEEP_ALIVE=-1` keeps the loaded model hot after the first request.
- If `preloadModel` is set, the `ollama-preloader` service keeps that model
  resident indefinitely when docked and on AC power by calling the API with
  `keep_alive: -1`.

## Managing models

Use the `ollama` CLI directly:

```sh
# Pull the default model
ollama pull qwen3.6:27b

# List installed models
ollama list

# Remove a model
ollama rm <tag>

# Run interactively for a quick sanity check
ollama run qwen3.6:27b
```

To change which model Codex uses without rebuilding:

```sh
# One-shot
CODEX_LOCAL_MODEL=qwen3.6:27b codex-local

# Or switch your current shell
export CODEX_LOCAL_MODEL=qwen3.6:27b
codex-local
```

The default shell value comes from `home.sessionVariables.CODEX_LOCAL_MODEL` in
`machines/razy/home.nix`, but `codex-local` reads the model at launch time
instead of pinning it in `~/.codex/config.toml`.

If you want the docked preloader to keep a different model hot by default, set
`services.ollama-agent.preloadModel` and rebuild.


## Performance tuning

All the relevant flags are exposed as module options:

| Option | Ollama env var | Default |
|---|---|---|
| `flashAttention` | `OLLAMA_FLASH_ATTENTION` | `true` |
| `kvCacheType` | `OLLAMA_KV_CACHE_TYPE` | `"q8_0"` |
| `contextLength` | `OLLAMA_CONTEXT_LENGTH` | `16384` |
| `parallel` | `OLLAMA_NUM_PARALLEL` | `1` |
| `maxLoadedModels` | `OLLAMA_MAX_LOADED_MODELS` | `1` |
| `modelsDir` | `OLLAMA_MODELS` | `~/.local/share/ollama/models` |
| `idleKeepAlive` | `OLLAMA_KEEP_ALIVE` | `"30m"` |

KV cache quantization requires flash attention to be enabled.

For `qwen3.6:27b` on the 5090 Laptop 24GB, the useful profiles are:

- Practical local-coding default: `contextLength = 32768`, `kvCacheType = "q4_0"`.
- Short-context max-quality fallback: `contextLength = 16384`, `kvCacheType = "q8_0"`.

The 32K Q4 KV profile keeps `qwen3.6:27b` fully resident on the 24GB GPU. Q8 KV
at 32K spills part of the dense 27B model to CPU on this machine, so use the
short-context fallback only for small focused sessions.

## Power policy

- `autoStart = true` by default.
- `preloadOnlyOnACPower = true` by default.
- If `preloadModel` is empty, docked preloading is disabled.
- Set `services.ollama-agent.preloadOnlyOnACPower = false` to preload whenever
  docked regardless of power state.
