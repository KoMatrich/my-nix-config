# NVIDIA open kernel module: test plan

Question: should BLACK-BOX (GTX 1650 Mobile, Turing, PRIME offload with
RTD3 `finegrained` power management) switch from the proprietary NVIDIA
kernel module to NVIDIA's open one (`hardware.nvidia.open = true`)?
NVIDIA recommends the open module for Turing and newer, but the things that
matter here are battery life and that nothing GPU-dependent breaks.

Everything lives in `apps/nvidia-open-test.nix`:

- **`nvidia-open` boot entry**: a specialisation identical to the normal
  system except for `hardware.nvidia.open = true`. The default entry stays on
  the proprietary module, so a bad result costs one reboot.
- **`gpu-driver-test`**: one command that measures and checks everything
  below and logs it to `~/gpu-driver-test/<flavor>-<date>.log`.

## What `gpu-driver-test` checks

| Phase | What | Why |
|---|---|---|
| Idle (180 s) | % of time the dGPU is runtime-suspended (RTD3), average battery draw | The biggest battery difference between the modules is whether the dGPU actually powers off when unused. Nothing touches the GPU in this phase (even `nvidia-smi` would wake it); it first lists processes holding `/dev/nvidia*`, which keep it awake. |
| Driver | `nvidia-smi` name / version / pstate / power | Driver loads and talks to the card |
| CUDA (60 s) | PyTorch: `cuda.is_available()`, GPU matmul vs CPU result, sustained fp32 TFLOPS; battery + GPU watts under load | "GPU computing from Python still works", and performance/power under load |
| Graphics | `nvidia-offload glxinfo` / `vulkaninfo` report the NVIDIA GPU | PRIME offload for games and apps |
| Suspend (`--suspend`) | Suspends via systemd for ~40 s (RTC wake), then re-checks CUDA and prints NVIDIA kernel messages | Suspend/resume is the classic open-module regression |

PyTorch comes from this system's nixpkgs (`torch-bin`, prebuilt CUDA wheels).
The first run downloads ~3 GB; it is not part of the system closure and goes
away with the next `gc`. To test your own environment instead (e.g. a
project venv), run with `GPU_TEST_PYTHON=/path/to/venv/bin/python`.

## Procedure

Do both runs under the same conditions: **on battery**, same screen
brightness, same apps open (ideally none), lid open, Wi-Fi on. The script
warns when it is on AC, because battery watt readings are meaningless then.

1. After `rebuild`, reboot normally (proprietary module). Unplug the charger,
   let the machine settle for a minute, then:

   ```sh
   gpu-driver-test --suspend
   ```

2. Reboot and hold **Space** at power-on to get the boot menu, pick the entry
   tagged **nvidia-open**. Confirm the module:

   ```sh
   grep -o "Open Kernel Module" /proc/driver/nvidia/version
   ```

   Then run the same `gpu-driver-test --suspend`.

3. While still on nvidia-open, use it normally for a while and try what you
   actually rely on: a game through Steam (`nvidia-offload %command%`), ollama
   / llama-server with CUDA, Blender Cycles on CUDA, an external monitor if the
   HDMI port is wired to the dGPU, and a real lid-close suspend.

4. Compare:

   ```sh
   gpu-driver-test --compare
   ```

   prints the `SUMMARY` lines of every run side by side. Repeat each run once
   or twice: idle battery draw varies by a few hundred mW between runs.

## Deciding

Switch to the open module if, on nvidia-open:

- `idle_dgpu_suspended_pct` is about as high as on proprietary (ideally over
  90%; if both are low, something keeps the dGPU awake — see the process list
  at the top of the log),
- `idle_battery_w` is no worse (within ~0.3 W),
- `cuda`, `gl`, `vulkan` and `resume` are all `ok`, and nothing in step 3
  broke.

Then:

- **Switch:** set `open = true;` in `nvidia.nix`, remove
  `apps/nvidia-open-test.nix` and its import in `configuration.nix`.
- **Stay:** just remove `apps/nvidia-open-test.nix` and its import (or keep it
  around to re-test after a driver update).

The boot entry only exists while the module is imported, and boot entries
are capped at 10 generations, so nothing needs cleaning up afterwards.
