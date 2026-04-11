# Ollama Agent

The `razy` host runs Ollama as its local LLM backend via `services.ollama-agent`.
Ollama handles model downloads, loading/unloading, and the OpenAI-compatible
HTTP API itself — so there's no custom gateway.

## Behavior

- `ollama serve` runs as a user systemd service on `127.0.0.1:11434`.
- Ollama exposes an OpenAI-compatible API at `http://127.0.0.1:11434/v1`.
- Models are unloaded automatically after `idleKeepAlive` (default `30m`).
- When booted in the `docked` specialisation and on AC power, the
  `ollama-preloader` service keeps `preloadModel` resident indefinitely
  by calling the API with `keep_alive: -1`.
- When docked but on battery (or undocked), the preloader reverts to the
  default idle behavior.

## Managing models

Use the `ollama` CLI directly:

```sh
# Pull a new model
ollama pull gemma4:31b

# List installed models
ollama list

# Remove a model
ollama rm <tag>

# Run interactively for a quick sanity check
ollama run gemma4:31b
```

To change which model Codex uses without rebuilding:

```sh
# One-shot
CODEX_LOCAL_MODEL=gemma4:27b codex-local

# Or switch your current shell
export CODEX_LOCAL_MODEL=gemma4:27b
codex-local
```

The default shell value comes from `home.sessionVariables.CODEX_LOCAL_MODEL` in
`machines/razy/home.nix`, but `codex-local` now reads the model at launch time
instead of pinning it in `~/.codex/config.toml`.

If you want the docked preloader to keep a different model hot by default, update
`services.ollama-agent.preloadModel` and rebuild.

## Performance tuning

All the relevant flags are exposed as module options:

| Option | Ollama env var | Default |
|---|---|---|
| `flashAttention` | `OLLAMA_FLASH_ATTENTION` | `true` |
| `kvCacheType` | `OLLAMA_KV_CACHE_TYPE` | `"q8_0"` |
| `contextLength` | `OLLAMA_CONTEXT_LENGTH` | `16384` |
| `parallel` | `OLLAMA_NUM_PARALLEL` | `1` |
| `idleKeepAlive` | `OLLAMA_KEEP_ALIVE` | `"30m"` |

KV cache quantization requires flash attention to be enabled.

## Power policy

- `preloadOnlyOnACPower = true` by default.
- If the machine is docked but on battery, models use the default idle timeout.
- Set `services.ollama-agent.preloadOnlyOnACPower = false` to preload whenever
  docked regardless of power state.
