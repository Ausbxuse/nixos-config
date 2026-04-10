# llama.cpp Agent

The `razy` host now manages its local `llama.cpp` endpoint declaratively through
`services.llamacpp-agent`.

Current model source:

- Publisher: `unsloth/Qwen3.5-27B-GGUF`
- File: `Qwen3.5-27B-Q4_K_M.gguf`
- SHA-256: `84b5f7f112156d63836a01a69dc3f11a6ba63b10a23b8ca7a7efaf52d5a2d806`
- Source page: <https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/blob/main/Qwen3.5-27B-Q4_K_M.gguf>

Behavior:

- A user service exposes the stable endpoint on `127.0.0.1:8080`.
- The first request cold-starts `llama-server`.
- When booted in the `docked` specialisation and external power is online, the
  model is preloaded and kept resident.
- Otherwise, the backend unloads after `idleTimeoutSeconds`.
- The model file is downloaded to `~/.local/share/llamacpp/models/`.

Power policy:

- `preloadOnlyOnACPower = true` by default.
- If the machine is docked but on battery, the backend stays on-demand and will
  unload after the idle timeout.
- Set `services.llamacpp-agent.preloadOnlyOnACPower = false` to restore the old
  "always keep loaded while docked" behavior.

To change models:

1. Update `services.llamacpp-agent.model.fileName`.
2. Update `services.llamacpp-agent.model.url`.
3. Update `services.llamacpp-agent.model.sha256`.
4. Rebuild the system.

For gated or private Hugging Face models:

1. Store a token in a local file, for example `~/.config/huggingface/token`.
2. Set `services.llamacpp-agent.model.huggingfaceTokenFile` to that path.
3. Rebuild the system.

If you do not want managed downloads, set `services.llamacpp-agent.model.path`
to an existing GGUF path and leave `model.url = null`.
