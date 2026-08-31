{ config, lib, pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;

    # The GTX 1650 has 3715 MiB usable, so the model shape matters far more
    # than any tuning knob. Two lanes:
    loadModels = [
      # Fast lane: 2.3 GB dense, sits entirely in VRAM. No CPU involvement.
      "qwen3:4b"
      # Quality lane: 21B MoE, but only 3.6B params are active per token, so
      # the CPU only reads ~1.6 GB per token instead of the 6.8 GB the old
      # dense 27B needed. Backbone + attention + KV go on the GPU, the expert
      # FFNs stay in RAM (see LLAMA_ARG_CPU_MOE below).
      "gpt-oss:20b"
    ];

    environmentVariables = {
      # Keep MoE expert weights on the CPU so all VRAM goes to the dense
      # backbone and the KV cache. Read by llama-server, which ollama spawns
      # with its own environment; a no-op for the dense qwen3:4b, so it is
      # safe to set service-wide. Use LLAMA_ARG_N_CPU_MOE=<N> instead to keep
      # only the first N layers' experts on the CPU if VRAM is left spare.
      LLAMA_ARG_CPU_MOE = "1";

      # The unit is manually started (wantedBy is forced empty below), so a
      # model should stay resident for the life of the service rather than
      # reloading on a 60s timer. Stop the unit to hand VRAM back to games.
      OLLAMA_KEEP_ALIVE = "-1";

      # No OLLAMA_CONTEXT_LENGTH: each model gets its full advertised context
      # (gpt-oss 131072, qwen3 40960) and ollama fits what it can into VRAM,
      # spilling the rest of the KV cache to RAM. opencode needs the room -
      # its system prompt plus tool definitions alone run to several thousand
      # tokens before any conversation starts.

      # Quantized KV cache. At full context this is what keeps the cache
      # affordable at all: q8_0 roughly halves it against f16.
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      # Turing (SM 7.5) supports flash attention; gpt-oss requires it.
      OLLAMA_FLASH_ATTENTION = "1";
      # No concurrent requests expected, avoid reserving a second KV cache slot.
      OLLAMA_NUM_PARALLEL = "1";
      # Keep several models resident so switching lanes does not re-read
      # gigabytes from disk. Only one model's weights fit the 3715 MiB card,
      # so the others sit in RAM while idle - that is the intended trade.
      OLLAMA_MAX_LOADED_MODELS = "3";
    };
  };

  # Models live on their own dataset so the blank-snapshot rollback in
  # system/zfs.nix does not erase them on every boot (see disko-config.nix).
  # It is mounted at /var/lib/private/ollama, not /var/lib/ollama: the module
  # runs ollama under DynamicUser, so systemd owns /var/lib/ollama as a symlink
  # into private/ and puts the real StateDirectory there. Ownership needs no
  # tmpfiles rule - systemd's StateDirectory= sets it on every start, and with
  # DynamicUser there is no static `ollama` user to chown to anyway.

  # The model loader ships as WantedBy=multi-user.target *and* ollama.service,
  # so it would fire on every boot and every rebuild - pulling ~15 GB - even
  # though ollama itself is manual-start. Drop the multi-user.target half so
  # models are fetched when the service is actually started, not before.
  systemd.services.ollama-model-loader.wantedBy = lib.mkForce [ "ollama.service" ];

  # Don't autostart on boot; run `systemctl start ollama` (or `ollama serve`) when needed.
  systemd.services.ollama.wantedBy = lib.mkForce [ ];
}
